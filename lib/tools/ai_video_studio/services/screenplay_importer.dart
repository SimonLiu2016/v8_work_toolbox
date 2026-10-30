import '../models/drama_director_contract.dart';
import '../models/studio_models.dart';

/// 剧本导入解析结果
class ScreenplayImportResult {
  final List<DramaScene> scenes;
  final String rawText;
  final bool isStructured;
  final String? parseSummary;

  const ScreenplayImportResult({
    required this.scenes,
    required this.rawText,
    required this.isStructured,
    this.parseSummary,
  });
}

/// 外部剧本文件解析与探测器
class ScreenplayImporter {
  /// 正则匹配常见剧本场次头：
  /// - Markdown 格式: `### 第1场 ...` 或 `## 第 1 场` 或 `# 第1场`
  /// - 纯文本 / 剧本格式: `第1场`、`第一场`、`SCENE 1`
  /// - 欧美制式 / Fountain: `INT. 房间 - DAY`、`EXT. 街道 - NIGHT`、`内景·客厅·日`
  static final RegExp sceneHeaderRegex = RegExp(
    r'^(?:#{1,6}\s*)?(?:第\s*([0-9一二三四五六七八九十百]+)\s*场|SCENE\s*([0-9]+)|(?:INT|EXT|内景|外景)[\.\s·])',
    caseSensitive: false,
    multiLine: true,
  );

  /// 智能解析输入的外部剧本文本
  static ScreenplayImportResult parse(String content) {
    final sanitized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final trimmed = sanitized.trim();
    if (trimmed.isEmpty) {
      return const ScreenplayImportResult(
        scenes: [],
        rawText: '',
        isStructured: false,
        parseSummary: '导入内容为空',
      );
    }

    // 探测是否含有分场标记
    final matches = sceneHeaderRegex.allMatches(trimmed).toList();
    if (matches.isEmpty) {
      // 未检测到分场头，平滑降级为全文 Markdown
      return ScreenplayImportResult(
        scenes: const [],
        rawText: trimmed,
        isStructured: false,
        parseSummary: '未检测到明确的影视分场标记，已作为全文剧本草稿载入',
      );
    }

    // 按场次头切分文本块
    final parsedScenes = <DramaScene>[];
    for (int i = 0; i < matches.length; i++) {
      final startIndex = matches[i].start;
      final endIndex = (i + 1 < matches.length) ? matches[i + 1].start : trimmed.length;
      final sceneBlock = trimmed.substring(startIndex, endIndex).trim();

      final scene = _parseSingleSceneBlock(sceneBlock, i + 1);
      parsedScenes.add(scene);
    }

    if (parsedScenes.isEmpty) {
      return ScreenplayImportResult(
        scenes: const [],
        rawText: trimmed,
        isStructured: false,
        parseSummary: '分场解析未提取到有效场次，已作为全文载入',
      );
    }

    final totalBeats = parsedScenes.fold<int>(0, (sum, s) => sum + s.beats.length);
    return ScreenplayImportResult(
      scenes: parsedScenes,
      rawText: trimmed,
      isStructured: true,
      parseSummary: '成功识别并提取 ${parsedScenes.length} 个分场、共 $totalBeats 个节拍',
    );
  }

  /// 解析单个场次文本块
  static DramaScene _parseSingleSceneBlock(String block, int defaultSceneNumber) {
    final lines = block.split('\n').map((l) => l.trim()).toList();
    if (lines.isEmpty) {
      return DramaScene(
        id: 'scene_$defaultSceneNumber',
        sceneNumber: defaultSceneNumber,
        title: '第$defaultSceneNumber场',
      );
    }

    final headerLine = lines.first;
    final bodyLines = lines.sublist(1);

    int sceneNum = defaultSceneNumber;
    String title = '第$defaultSceneNumber场';
    String setting = '内景';
    String timeOfDay = '日景';
    String location = '';
    String atmosphere = '';

    // 解析场次头信息：例如 "### 第1场 办公室初遇（内景 / 日景 / 总裁办公室）"
    // 或 "INT. COFFEE SHOP - DAY"
    final cleanHeader = headerLine.replaceFirst(RegExp(r'^#{1,6}\s*'), '').trim();

    final numMatch = RegExp(r'第\s*([0-9]+)\s*场|SCENE\s*([0-9]+)', caseSensitive: false).firstMatch(cleanHeader);
    if (numMatch != null) {
      final rawNum = numMatch.group(1) ?? numMatch.group(2);
      if (rawNum != null) {
        sceneNum = int.tryParse(rawNum) ?? defaultSceneNumber;
      }
    }

    if (cleanHeader.contains('外景') || cleanHeader.toUpperCase().contains('EXT')) {
      setting = '外景';
    } else {
      setting = '内景';
    }

    if (cleanHeader.contains('夜') || cleanHeader.toUpperCase().contains('NIGHT')) {
      timeOfDay = '夜景';
    } else if (cleanHeader.contains('黄昏') || cleanHeader.toUpperCase().contains('DUSK')) {
      timeOfDay = '黄昏';
    } else if (cleanHeader.contains('黎明') || cleanHeader.toUpperCase().contains('DAWN')) {
      timeOfDay = '黎明';
    } else {
      timeOfDay = '日景';
    }

    // 尝试提取括号内的地点或分段
    final parenMatch = RegExp(r'[（\(](.*?)[）\)]').firstMatch(cleanHeader);
    if (parenMatch != null) {
      final parts = parenMatch.group(1)!.split(RegExp(r'[/,，、·\-]')).map((s) => s.trim()).toList();
      for (final part in parts) {
        if (part != '内景' && part != '外景' && !part.contains('景') && part.isNotEmpty) {
          location = part;
          break;
        }
      }
    }

    // 提取标题：去掉第X场后剩余的部分
    final titleCandidate = cleanHeader
        .replaceFirst(RegExp(r'第\s*[0-9一二三四五六七八九十百]+\s*场|SCENE\s*[0-9]+', caseSensitive: false), '')
        .replaceAll(RegExp(r'[（\(].*?[）\)]'), '')
        .trim();
    if (titleCandidate.isNotEmpty) {
      title = titleCandidate;
    }

    // 解析节拍列表
    final beats = <DramaBeat>[];
    String currentAction = '';
    String currentDialogue = '';
    String currentSpeaker = '';
    UtteranceVoiceType currentVoiceType = UtteranceVoiceType.dialogue;
    String currentBeatName = '';
    int beatOrder = 1;

    void flushBeat() {
      if (currentAction.isNotEmpty || currentDialogue.isNotEmpty) {
        beats.add(DramaBeat(
          id: 'beat_${sceneNum}_$beatOrder',
          sceneId: 'scene_$sceneNum',
          order: beatOrder,
          name: currentBeatName.isNotEmpty ? currentBeatName : '动作发展',
          action: currentAction.trim(),
          dialogue: currentDialogue.trim(),
          dialogueSpeaker: currentSpeaker.trim(),
          voiceType: currentVoiceType,
        ));
        beatOrder++;
        currentAction = '';
        currentDialogue = '';
        currentSpeaker = '';
        currentVoiceType = UtteranceVoiceType.dialogue;
        currentBeatName = '';
      }
    }

    for (final line in bodyLines) {
      if (line.isEmpty || line == '---') continue;

      if (line.startsWith('> 氛围') || line.startsWith('> 氛围光影：')) {
        atmosphere = line.replaceFirst(RegExp(r'^>\s*(?:氛围光影：|氛围：)?'), '').trim();
        continue;
      }

      // 显式节拍标头：**【节拍 1：开场】**
      final beatMatch = RegExp(r'\*\*【节拍\s*\d+\s*[：:]\s*(.*?)】\*\*').firstMatch(line);
      if (beatMatch != null) {
        flushBeat();
        currentBeatName = beatMatch.group(1) ?? '';
        continue;
      }

      // 动作叙述行优先匹配（避免冒号将“画面动作：”误判为角色名对白）
      if (line.startsWith('画面动作') || line.startsWith('动作：') || line.startsWith('动作:')) {
        final cleanAction = line.replaceFirst(RegExp(r'^(?:画面动作[：:]\s*|动作[：:]\s*)'), '').trim();
        if (cleanAction.isNotEmpty) {
          if (currentAction.isNotEmpty) {
            currentAction += '\n$cleanAction';
          } else {
            currentAction = cleanAction;
          }
        }
        continue;
      }

      // 潜台词
      if (line.startsWith('潜台词') || line.startsWith('> 潜台词')) {
        continue;
      }

      // 对白行解析：
      // "对白（李明）：你好！" 或 "李明（内心 OS）：糟糕" 或 "李明：你好" 或 "旁白：很久很久以前"
      final dialogueMatch = RegExp(
        r'^(?:对白\s*[（\(](.*?)[）\)]|心声\s*[（\(](.*?)[）\)]|旁白|[【\[](.*?)[】\]]|([^\s：:]{1,10}))[：:](.*)$',
      ).firstMatch(line);

      if (dialogueMatch != null) {
        final rawSpeaker = (dialogueMatch.group(1) ??
                dialogueMatch.group(2) ??
                dialogueMatch.group(3) ??
                dialogueMatch.group(4) ??
                '')
            .trim();
        final rawText = (dialogueMatch.group(5) ?? '').trim();

        if (line.startsWith('旁白') || rawSpeaker == '旁白') {
          currentVoiceType = UtteranceVoiceType.narration;
          currentSpeaker = '旁白';
          currentDialogue = rawText;
        } else if (line.startsWith('心声') || rawSpeaker.contains('内心') || rawSpeaker.contains('OS')) {
          currentVoiceType = UtteranceVoiceType.innerVoice;
          currentSpeaker = rawSpeaker.replaceAll(RegExp(r'[·\s]*内心\s*(?:OS)?'), '').trim();
          currentDialogue = rawText;
        } else {
          currentVoiceType = UtteranceVoiceType.dialogue;
          currentSpeaker = rawSpeaker.replaceAll('角色', '').trim();
          currentDialogue = rawText;
        }

        flushBeat();
        continue;
      }

      // 普通动作叙述行（无冒号或未匹配对白的普通行）
      final cleanActionLine = line.trim();
      if (cleanActionLine.isNotEmpty) {
        if (currentAction.isNotEmpty) {
          currentAction += '\n$cleanActionLine';
        } else {
          currentAction = cleanActionLine;
        }
      }
    }

    flushBeat();

    // 如果该场没有任何 beats，至少生成一个默认 beat 容纳文字
    if (beats.isEmpty && bodyLines.isNotEmpty) {
      beats.add(DramaBeat(
        id: 'beat_${sceneNum}_1',
        sceneId: 'scene_$sceneNum',
        order: 1,
        name: '现场剧情',
        action: bodyLines.join('\n').trim(),
      ));
    }

    return DramaScene(
      id: 'scene_$sceneNum',
      sceneNumber: sceneNum,
      title: title,
      location: location,
      setting: setting,
      timeOfDay: timeOfDay,
      atmosphere: atmosphere,
      beats: beats,
    );
  }
}
