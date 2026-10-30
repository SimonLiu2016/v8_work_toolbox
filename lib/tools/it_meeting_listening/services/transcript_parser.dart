/// 真实会议逐字稿的解析。
///
/// 输入形态（会议记录系统产出）：
///
/// ```
/// # 10-20 AI Agent Security and Governance Review
/// > 转写时长: 20分6秒
/// ## 关键词
///  AI    governance    isolated ...
/// ## 转文字
/// 发言人 1 00:00:01
///
/// 正文……
///
/// 发言人 2 00:00:21
///
/// 正文……
/// ```
///
/// **三个必须踩准的细节**（都来自实测样例）：
///
/// 1. **分隔符是不间断空格 `U+00A0`**，不是普通空格。整份文稿里说话人行与
///    关键词段都是 NBSP——按普通空格解析会得到 0 轮次，且不报错，是最难发现
///    的那种失败。
/// 2. **时间戳是原稿时间**（来自真实录音），与 TTS 合成后的音频时长无关。
///    它只用于"这句在第几分钟"的展示与导入校验，不参与音频定位。
/// 3. **「关键词」段是真术语白名单**，词汇表用它把低频真词（`VPC`）与转写
///    噪声（`aCRI`）区分开，所以必须解析并保留，不能当装饰跳过。
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../models/real_meeting_models.dart';

/// 解析失败（带行号与具体原因）。
///
/// 带行号是因为用户只可能拿着文件去对照——"第 87 行时间戳早于前一轮"能让他
/// 直接定位，而"解析失败"不能。
class TranscriptParseException implements Exception {
  TranscriptParseException(this.message, {this.lineNumber});

  final String message;
  final int? lineNumber;

  @override
  String toString() => lineNumber == null
      ? 'TranscriptParseException: $message'
      : 'TranscriptParseException: 第 $lineNumber 行：$message';
}

/// 解析结果。
class ParsedTranscript {
  final String title;
  final int declaredDurationMs;
  final List<String> keywords;
  final List<MeetingTurn> turns;
  final List<SpeakerSlot> slots;

  /// 文稿里没有「关键词」段。
  ///
  /// 不是错误：豆包导出件就没有。后果是词汇表的噪声折叠更激进（少了那份
  /// 「真术语白名单」），所以要在预览里告诉用户。
  final bool keywordsMissing;

  /// 看起来是人工整理的归档件（说明表格 + 内嵌原文 + 附录），而不是导出原件。
  ///
  /// 只用于预览里标注，不拒绝导入——这类文件往往是用户手边最完整的版本。
  final bool isProcessedDocument;

  const ParsedTranscript({
    required this.title,
    required this.declaredDurationMs,
    required this.keywords,
    required this.turns,
    required this.slots,
    this.keywordsMissing = false,
    this.isProcessedDocument = false,
  });

  /// 最后一轮的时间戳（用于预览里展示时长；无轮次时为 0）。
  int get lastTimestampMs => turns.isEmpty ? 0 : turns.last.timestampMs;

  /// 有效时长：优先用文稿声明的，否则用末轮时间戳。
  int get effectiveDurationMs =>
      declaredDurationMs > 0 ? declaredDurationMs : lastTimestampMs;
}

/// 逐字稿解析器。
class TranscriptParser {
  /// 说话人行。
  ///
  /// 判定依据是**整行结构**而不是固定的槽位名词：可选的标记前缀（`@` `#`
  /// `-` `*` 等）+ 槽位名 + 可选序号 + 时间戳，且行内没有别的字。
  ///
  /// ```
  ///   @说话人 1  01:54     ✓ 前缀 @ · 名 说话人 · 序号 1
  ///   发言人 2 00:00:21    ✓
  ///   李嘉成 00:00:03      ✓ 真实姓名
  ///   Meeting at 10:30     ✗ 名字后面直接是 at，接不上时间
  ///   see you at 10:30 tomorrow  ✗ 行内还有别的字
  /// ```
  ///
  /// **为什么不用槽位名白名单**：每接一个会议平台就要往白名单里加一个词，
  /// 而这几种形态的共同结构就是"整行只有谁 + 什么时候"。按结构判定，新平台
  /// 天然成立。
  ///
  /// 槽位名不允许以数字开头：那会把 `2026-10-22 15:04` 这类时间行误认进来。
  static final RegExp _speakerLine = RegExp(
    r'^[\s@#>*\-]*([^\s\d:：|]{1,20})(?:\s+([0-9]{1,3}))?\s+'
    r'(\d{1,2}:\d{2}(?::\d{2})?)\s*$',
  );

  /// 二级标题。
  static final RegExp _h2 = RegExp(r'^##\s+(.+?)\s*$');

  /// 一级标题（标题行；`##` 不算）。
  static final RegExp _h1 = RegExp(r'^#(?!#)\s*(.+?)\s*$');

  /// 时长行：钉钉的 `> 转写时长: 20分6秒` 与豆包的 `录音时间：A - B`。
  static final RegExp _durationLine =
      RegExp(r'^\s*>?\s*(转写时长|录音时间)\s*[:：]\s*(.*)$');

  /// 「关键词」小节只收录这些标题下的内容。
  static const String _keywordsSection = '关键词';

  /// 出现这些二级标题说明这是人工整理的归档件。
  static const Set<String> _processedSectionHints = {
    '说明',
    '原文',
    '附录',
    '校验',
    '修正',
    '说话人推定',
  };

  /// 归一化：NBSP → 空格、统一换行、去 BOM。
  ///
  /// 单独暴露成公开方法，是因为"素材内容没变"的判定要在解析前后保持一致——
  /// 归一化只影响空白，不影响内容哈希的语义（哈希算在归一化后的文本上）。
  static String normalize(String raw) {
    var text = raw;
    // UTF-8 BOM：Windows/部分导出工具会带，会让第一个 `#` 匹配不上标题。
    if (text.startsWith('﻿')) text = text.substring(1);
    text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    // 不间断空格与窄空格统一成普通空格。
    text = text.replaceAll(' ', ' ').replaceAll(' ', ' ');
    return text;
  }

  /// 解析一段逐字稿文本。
  static ParsedTranscript parse(String raw) {
    final text = normalize(raw);
    final lines = text.split('\n');

    String title = '';
    int declaredDurationMs = 0;
    var keywords = <String>[];
    final turns = <MeetingTurn>[];

    // 当前所在的二级小节（只有「关键词」还参与语义；其余仅用于加工件识别）。
    var section = '';
    // 正在累积的轮次（未遇到下一个说话人前，正文都归它）。
    String? currentSlot;
    int currentTimestampMs = 0;
    int currentLine = 0;
    final currentBody = <String>[];

    // 代码块围栏状态：导出件会把关键词放进 ``` 里。
    var inFence = false;
    var sawKeywordsSection = false;
    var isProcessed = false;
    var sawSpeakerLine = false;

    void flushTurn() {
      if (currentSlot == null) return;
      final body = currentBody.join(' ').trim();
      currentBody.clear();
      if (body.isEmpty) return;
      turns.add(MeetingTurn(
        index: turns.length,
        slotId: currentSlot,
        timestampMs: currentTimestampMs,
        text: body,
      ));
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lineNo = i + 1;
      final trimmed = line.trim();

      // ``` 围栏内的一切都不是发言（关键词、示例、注释）。
      if (trimmed.startsWith('```')) {
        inFence = !inFence;
        continue;
      }
      if (inFence) continue;

      final h1 = _h1.firstMatch(line);
      if (h1 != null) {
        flushTurn();
        currentSlot = null;
        if (title.isEmpty) {
          // Markdown 转义的下划线（`纪要\_10-20`）去掉反斜杠，其余逐字保留。
          title = h1.group(1)!.replaceAll(r'\_', '_').trim();
        }
        continue;
      }

      final h2 = _h2.firstMatch(line);
      if (h2 != null) {
        flushTurn();
        currentSlot = null;
        section = h2.group(1)!.trim();
        if (section.contains(_keywordsSection)) sawKeywordsSection = true;
        // 首个说话人之前出现整理性标题 → 这是加工件而不是导出原件。
        if (!sawSpeakerLine &&
            _processedSectionHints.any((h) => section.contains(h))) {
          isProcessed = true;
        }
        continue;
      }

      final dur = _durationLine.firstMatch(line);
      if (dur != null) {
        declaredDurationMs = dur.group(1) == '录音时间'
            ? _parseRecordingWindow(dur.group(2)!)
            : _parseDuration(dur.group(2)!);
        continue;
      }

      if (section.contains(_keywordsSection)) {
        // 关键词可能写成 `甲   乙   丙`，也可能被逗号分隔。
        final words = line
            .split(RegExp(r'[\s,，、]+'))
            .map((w) => w.trim())
            .where((w) => w.isNotEmpty)
            .toList();
        keywords = [...keywords, ...words];
        continue;
      }

      // 引用块与表格：放的是元信息、译文、说明，都不是谁说的话。
      // 中英对照件的 `> 【译】…` 若不跳过，会被拼进这一轮正文，TTS 会把
      // 中英两版念一遍。
      if (trimmed.startsWith('>')) {
        continue;
      }
      if (trimmed.startsWith('|')) {
        if (!sawSpeakerLine) isProcessed = true;
        continue;
      }

      final speaker = _speakerLine.firstMatch(line);
      if (speaker != null) {
        flushTurn();
        final name = speaker.group(1)!.trim();
        final index = speaker.group(2);
        final slotId = index == null ? name : '$name $index';
        final ts = _parseTimestamp(speaker.group(3)!, lineNo);
        // 时间戳单调性：倒序一定意味着文稿有问题——最典型的是"一篇文档里
        // 嵌了两场会"，第二场的时间戳会归零。继续解析会产出一条前后错乱的
        // 音频，不如就地失败。
        if (turns.isNotEmpty && ts < turns.last.timestampMs) {
          throw TranscriptParseException(
            '时间戳 ${speaker.group(3)} 早于上一轮的 '
            '${_formatTimestamp(turns.last.timestampMs)}'
            '（若这份文稿里拼了多场会议，请拆开分别导入）',
            lineNumber: lineNo,
          );
        }
        currentSlot = slotId;
        currentTimestampMs = ts;
        currentLine = lineNo;
        sawSpeakerLine = true;
        continue;
      }

      if (currentSlot != null) {
        if (trimmed.isNotEmpty) currentBody.add(trimmed);
      }
      // 首个说话人之前的散文（前言、免责声明）不属于任何轮次，忽略。
    }
    flushTurn();

    if (turns.isEmpty) {
      throw TranscriptParseException(
        '没有解析出任何轮次——说话人行应形如「发言人 1 00:00:01」、'
        '「说话人 1 00:01」或「张三 00:00:03」（整行只有名字与时间）',
        lineNumber: currentLine == 0 ? null : currentLine,
      );
    }

    return ParsedTranscript(
      title: title.isEmpty ? '未命名会议' : title,
      declaredDurationMs: declaredDurationMs,
      keywords: _dedupeKeywords(keywords),
      turns: turns,
      slots: _buildSlots(turns),
      keywordsMissing: !sawKeywordsSection,
      isProcessedDocument: isProcessed,
    );
  }

  /// 读取并归一化文件内容。
  ///
  /// 解析与内容哈希**共用这一份文本**：两次读取之间文件可能变（用户在编辑器里
  /// 保存），那会让"内容未变"的判定与实际解析的内容对不上。
  static Future<String> readFileText(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw TranscriptParseException('文件不存在：$path');
    }
    final bytes = await file.readAsBytes();
    try {
      return normalize(utf8.decode(bytes));
    } catch (_) {
      throw TranscriptParseException('文件不是合法的 UTF-8 编码：$path');
    }
  }

  /// 从文件解析（UTF-8；解码失败给出明确提示而不是 mojibake）。
  static Future<ParsedTranscript> parseFile(String path) async =>
      parse(await readFileText(path));

  /// 会议标识：只由来源路径决定。
  ///
  /// **不含内容哈希**是有意的：同一份文稿改了几个字还是同一场会，用户的
  /// 改名、音色与已插入的回答都该继续挂在它身上。内容是否变化由
  /// [contentHashOf] 单独记录并比较（spec: 重复导入的两种情形）。
  static String meetingIdFor(String sourcePath) {
    final digest = sha256.convert(utf8.encode(sourcePath)).toString();
    return 'rm_${digest.substring(0, 16)}';
  }

  /// 内容哈希（归一化后）。
  ///
  /// 归一化后计算：仅换行符或 NBSP 不同的两份文稿不该被判成"内容变了"——
  /// 那会触发一次毫无意义的重烘（几百轮 TTS）。
  static String contentHashOf(String raw) =>
      sha256.convert(utf8.encode(normalize(raw))).toString();

  // ---------------------------------------------------------------------

  /// `录音时间：2026-09-24 15:28 - 2026-09-24 16:47` → 差值（毫秒）。
  ///
  /// 取行内**第一个与最后一个** `H:MM`。日期里没有冒号，所以不会被误取；
  /// 跨零点时按"第二天"处理。识别不了返回 0——时长只用于展示，不该阻断导入。
  static int _parseRecordingWindow(String raw) {
    final times = RegExp(r'(\d{1,2}):(\d{2})').allMatches(raw).toList();
    if (times.length < 2) return 0;
    final start = int.parse(times.first.group(1)!) * 60 +
        int.parse(times.first.group(2)!);
    final end =
        int.parse(times.last.group(1)!) * 60 + int.parse(times.last.group(2)!);
    final minutes = end >= start ? end - start : end + 24 * 60 - start;
    return minutes * 60 * 1000;
  }

  /// `20分6秒` / `1小时2分3秒` / `1:02:03` → 毫秒。识别不了返回 0。
  static int _parseDuration(String raw) {
    final text = raw.replaceAll(' ', '');
    final hms = RegExp(r'^(\d+):(\d{1,2}):(\d{1,2})$').firstMatch(text);
    if (hms != null) {
      return (int.parse(hms.group(1)!) * 3600 +
              int.parse(hms.group(2)!) * 60 +
              int.parse(hms.group(3)!)) *
          1000;
    }
    var ms = 0;
    var matched = false;
    final parts = <RegExp, int>{
      RegExp(r'(\d+)\s*(?:小时|时|h)', caseSensitive: false): 3600,
      RegExp(r'(\d+)\s*(?:分|分钟|m)', caseSensitive: false): 60,
      RegExp(r'(\d+)\s*(?:秒|s)'): 1,
    };
    parts.forEach((re, unit) {
      final m = re.firstMatch(text);
      if (m != null) {
        ms += int.parse(m.group(1)!) * unit * 1000;
        matched = true;
      }
    });
    return matched ? ms : 0;
  }

  /// `HH:MM:SS` 或 `MM:SS` → 毫秒。
  static int _parseTimestamp(String raw, int lineNo) {
    final parts = raw.split(':').map(int.tryParse).toList();
    if (parts.any((p) => p == null)) {
      throw TranscriptParseException('时间戳格式无法识别：$raw', lineNumber: lineNo);
    }
    final nums = parts.cast<int>();
    if (nums.length == 3) {
      return (nums[0] * 3600 + nums[1] * 60 + nums[2]) * 1000;
    }
    if (nums.length == 2) {
      return (nums[0] * 60 + nums[1]) * 1000;
    }
    throw TranscriptParseException('时间戳格式无法识别：$raw', lineNumber: lineNo);
  }

  static String _formatTimestamp(int ms) {
    final total = ms ~/ 1000;
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    return '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }

  /// 关键词去重（保留首次出现的顺序与原大小写）。
  static List<String> _dedupeKeywords(List<String> words) {
    final seen = <String>{};
    final out = <String>[];
    for (final w in words) {
      final key = w.toLowerCase();
      if (seen.add(key)) out.add(w);
    }
    return out;
  }

  /// 按首次出现顺序构建槽位，并统计每个槽位的轮次数。
  static List<SpeakerSlot> _buildSlots(List<MeetingTurn> turns) {
    final counts = <String, int>{};
    for (final t in turns) {
      counts[t.slotId] = (counts[t.slotId] ?? 0) + 1;
    }
    return [
      for (final e in counts.entries)
        SpeakerSlot(id: e.key, turnCount: e.value),
    ];
  }
}
