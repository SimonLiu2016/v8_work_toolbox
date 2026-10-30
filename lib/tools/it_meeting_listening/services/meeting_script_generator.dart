/// 模拟会议剧本生成（阶段二）。
///
/// **一次生成整场**（design D2）：会议有弧线（开场→议题→Q&A→收尾），分段生成
/// 会丢失跨段呼应（开场提的议题三要在 Q&A 收尾），人物立场也会漂。LLM 的
/// context 装得下 140-280 轮。
///
/// **轮次目标而非时长目标**：实测 LLM 听到"30 分钟"给出的词数能从 5000 到
/// 15000 差三倍。给明确的轮次区间，再在生成后按语速校验时长（见
/// [MeetingScript.estimatedMs]）——偏离时提示用户，不阻断。
library;

import '../models/rehearsal_models.dart';
import 'material_importer.dart';
import 'rehearsal_llm.dart';

/// 剧本生成失败。
class ScriptGenerationException implements Exception {
  ScriptGenerationException(this.message);
  final String message;
  @override
  String toString() => 'ScriptGenerationException: $message';
}

/// 剧本偏短——**带产物**的异常。
///
/// 用异常承载结果而不是返回一个可空联合：偏短的剧本**是有价值的产物**（用户
/// 可以先拿去用），但调用方必须看到"它偏短"这件事。抛异常保证了这一点不会被
/// 静默忽略；[script] 让调用方仍能拿到剧本本身。
class ScriptTooShortWarning implements Exception {
  ScriptTooShortWarning(this.script);
  final MeetingScript script;

  @override
  String toString() => 'ScriptTooShortWarning: ${script.turns.length} 轮，'
      '预估 ${script.estimatedMs ~/ 60000} 分钟';
}

/// 剧本生成器。
class MeetingScriptGeneratorImpl implements MeetingScriptGenerator {
  /// 轮次目标区间（30-60 分钟按 150wpm 折算）。
  ///
  /// 30 分钟 ≈ 140 轮，60 分钟 ≈ 280 轮（实测：一轮平均 12.9 词 ≈ 5.8 秒）。
  static const int minTurns = 120;
  static const int maxTurns = 300;

  /// 轮次下限的**告警阈值**：低于它只提示、不拒绝。
  ///
  /// 拒绝线（[minTurns]）与提示线的差距是缓冲区：模型给出的轮次落在两者之间时
  /// 说明它确实在按目标生成，只是短了一点——直接拒绝会让用户反复重试同一件事。
  /// 只有明显偏短（少于 30 分钟的一半）才值得让用户决定要不要重来。
  static const int warnTurns = 60;

  final RehearsalTextGenerator _generator;
  final int maxMaterialChars;

  const MeetingScriptGeneratorImpl(
    this._generator, {
    this.maxMaterialChars = 24000,
  });

  @override
  Future<MeetingScript> generateScript({
    required RehearsalMaterial material,
    required SpeechDraft draft,
    required int targetMinutes,
  }) async {
    if (draft.sections.isEmpty) {
      throw ScriptGenerationException('讲稿为空，无法生成会议剧本');
    }

    final prompt = _buildPrompt(material, draft, targetMinutes);
    final String output;
    try {
      output = await _generator.generate(prompt);
    } catch (e) {
      throw ScriptGenerationException('剧本生成失败：$e');
    }

    final turns = parseTurns(output);
    if (turns.isEmpty) {
      throw ScriptGenerationException('剧本解析失败：模型输出里没有可识别的对话轮次');
    }
    if (turns.length < warnTurns) {
      throw ScriptGenerationException(
          '剧本只有 ${turns.length} 轮，远少于 $minTurns 轮——'
          '时长会明显不足 30 分钟，请提高目标时长后重试');
    }

    final script = MeetingScript(
      id: 'script_${material.id}',
      materialId: material.id,
      draftId: draft.id,
      title: '${material.title} · 模拟会议',
      turns: turns,
      targetMinutes: targetMinutes,
      generatedAt: DateTime.now(),
    );

    // 轮次在告警线以上但低于目标：不阻断（spec：提示但不阻断），由调用方
    // 把 warning 显示给用户。
    if (turns.length < minTurns) {
      throw ScriptTooShortWarning(script);
    }
    return script;
  }

  /// 轮次是否达到目标区间（供调用方在生成后决定是否提示）。
  static bool meetsTarget(MeetingScript script) =>
      script.turns.length >= minTurns;

  String _buildPrompt(
    RehearsalMaterial material,
    SpeechDraft draft,
    int targetMinutes,
  ) {
    final body = MaterialImporter.truncateForPrompt(material.text,
        maxChars: maxMaterialChars);
    final turnTarget = _turnTargetFor(targetMinutes);
    final roles =
        RehearsalRole.values.map((r) => '- ${r.speaker}: ${r.note}').join('\n');

    return '''
Write the transcript of a simulated English workplace meeting, $targetMinutes minutes long.

PARTICIPANTS (exactly these five, all male):
$roles

STANCE (keep it consistent throughout):
- The client side (xiaofeng, deepan, Josh) pushes back: they ask about risk,
  data, schedule, and demand specifics. They do NOT just agree.
- songyang (Huawei partner) adds coordination-side progress.
- Simon (comall, the presenter) answers and moves the meeting forward.

STRUCTURE (four phases, in order):
1. Opening — Simon introduces the agenda.
2. Topics — Simon presents each agenda item; others question and comment.
3. Q&A — the client side presses with follow-up questions.
4. Closing — action items with owners.

LENGTH: between $turnTarget turns total (one turn = one speaker's single
utterance). Aim for the upper half of that range.

STYLE: spoken English. Short sentences, contractions, occasional "um", "uh",
"Yeah, but...", and interruptions. No written-report phrasing.

SOURCE MATERIAL (facts must come from here; do not invent numbers):
"""
$body
"""

SIMON'S DRAFT (what Simon is there to present):
"""
${draft.fullText}
"""

OUTPUT FORMAT — one turn per line, exactly this shape:
Simon: <what Simon says>
xiaofeng: <what xiaofeng says>
songyang: <what songyang says>

You may prefix a phase change with a line like "[opening]", "[topics]", "[qa]"
or "[closing]". Output only the transcript.''';
  }

  /// 目标时长 → 轮次区间文案。
  ///
  /// 一轮平均约 12.9 词 ≈ 5.8 秒，所以 30 分钟 ≈ 310 轮纯对话；但开场问好、
  /// 行动项宣读等短轮占比高，实测 30 分钟会议约 140 轮。这里按实测值给区间。
  static String _turnTargetFor(int targetMinutes) {
    final scaled = (targetMinutes / 30 * 140).round();
    final lo = (scaled * 0.85).round().clamp(minTurns, maxTurns);
    final hi = (scaled * 1.15).round().clamp(lo + 1, maxTurns);
    return '$lo and $hi';
  }

  /// 解析剧本输出。
  ///
  /// 每行 `角色: 台词`。角色名匹配 [RehearsalRole]（大小写不敏感）；不认识的
  /// 说话人整行忽略——剧本里混入第六个人会破坏"5 角色固定音色"的承诺。
  /// `[phase]` 行切换当前结构段，不影响轮次。
  static List<ScriptTurn> parseTurns(String output) {
    final turns = <ScriptTurn>[];
    var phase = ScriptPhase.opening;
    final speakerPattern =
        RegExp(r'^\s*([A-Za-z][A-Za-z0-9_\- ]{0,20}?)\s*[:：]\s*(.+)$');
    final phasePattern =
        RegExp(r'^\s*[\[\(（]\s*(opening|topics|qa|closing)\s*[\]\)）]',
            caseSensitive: false);

    for (final rawLine in output.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      final phaseMatch = phasePattern.firstMatch(line);
      if (phaseMatch != null) {
        phase = ScriptPhase.fromId(phaseMatch.group(1)!.toLowerCase());
        continue;
      }

      final m = speakerPattern.firstMatch(line);
      if (m == null) continue;
      final role = RehearsalRole.fromSpeaker(m.group(1));
      if (role == null) continue;
      final text = m.group(2)!.trim();
      if (text.isEmpty) continue;
      turns.add(ScriptTurn(role: role, text: text, phase: phase));
    }
    return turns;
  }
}
