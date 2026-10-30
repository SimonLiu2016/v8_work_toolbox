import 'dart:convert';
import '../models/drama_director_contract.dart';
import '../models/studio_models.dart';

/// 分镜看板导出器：支持导出人类可读的 Markdown 分镜表与符合 RFC 4180 的工业 CSV 分镜表。
class StoryboardExporter {
  /// 导出为 Markdown 表格分镜表文档
  static String exportToMarkdown({
    required String seriesTitle,
    required StudioEpisode episode,
    Map<String, String>? characterNames,
    Map<String, String>? propNames,
    Map<String, String>? sceneNames,
  }) {
    final buffer = StringBuffer();
    final totalDuration = episode.shots.fold<double>(
      0.0,
      (acc, s) => acc + s.durationSec,
    );

    buffer.writeln('# 《$seriesTitle》第 ${episode.index} 集：${episode.title} - 导演分镜表');
    buffer.writeln();
    buffer.writeln('- **项目剧名**：$seriesTitle');
    buffer.writeln('- **集数与标题**：第 ${episode.index} 集 · ${episode.title}');
    buffer.writeln('- **镜头总数**：${episode.shots.length} 镜');
    buffer.writeln('- **预估总时长**：${totalDuration.toStringAsFixed(1)} 秒');
    if (episode.scenes.isNotEmpty) {
      buffer.writeln('- **涉及场次数**：${episode.scenes.length} 场');
    }
    buffer.writeln();
    buffer.writeln('---');
    buffer.writeln();

    buffer.writeln(
      '| 镜号 | 场次 | 时长 | 景别 | 运镜 | 画面动作 / 视觉描述 | 角色与对白 | 关键道具 | 资产状态 |',
    );
    buffer.writeln(
      '| :---: | :--- | :---: | :---: | :--- | :--- | :--- | :--- | :---: |',
    );

    for (final shot in episode.shots) {
      final shotNum = '#${shot.number}';
      
      // 场次信息
      String sceneInfo = '-';
      if (shot.sceneId.isNotEmpty) {
        sceneInfo = sceneNames?[shot.sceneId] ?? shot.sceneId;
      }

      final duration = '${shot.durationSec.toStringAsFixed(1)}s';
      final shotSizeLabel = shot.shotSize.label;
      final camera = shot.cameraMove.isNotEmpty ? shot.cameraMove : '-';

      // 画面动作（将换行转为 <br> 以免破坏 Markdown 表格）
      final action = _sanitizeForMarkdownTable(
        shot.actionZh.isNotEmpty ? shot.actionZh : shot.assembledPrompt,
      );

      // 对白与说话角色
      String dialogue = '-';
      if (shot.dialogue.isNotEmpty) {
        final speaker = _resolveSpeaker(shot, characterNames);
        final voiceTag = _voiceTypeTag(shot.voiceType);
        dialogue = '$speaker$voiceTag: "${_sanitizeForMarkdownTable(shot.dialogue)}"';
      }

      // 道具
      String props = '-';
      if (shot.propIds.isNotEmpty) {
        props = shot.propIds
            .map((id) => propNames?[id] ?? id)
            .join('、');
        props = _sanitizeForMarkdownTable(props);
      }

      // 素材状态
      final hasFrame = shot.framePath != null && shot.framePath!.isNotEmpty;
      final hasClip = shot.clipPath != null && shot.clipPath!.isNotEmpty;
      String status = '待生成';
      if (hasClip) {
        status = '视频已就绪';
      } else if (hasFrame) {
        status = '首帧已就绪';
      }

      buffer.writeln(
        '| $shotNum | $sceneInfo | $duration | $shotSizeLabel | $camera | $action | $dialogue | $props | $status |',
      );
    }

    buffer.writeln();
    buffer.writeln('> 导出时间：${DateTime.now().toString().split('.').first}');
    return buffer.toString();
  }

  /// 导出为符合 RFC 4180 标准并带有 UTF-8 BOM 的 CSV 格式分镜表
  static String exportToCsv({
    required String seriesTitle,
    required StudioEpisode episode,
    Map<String, String>? characterNames,
    Map<String, String>? propNames,
    Map<String, String>? sceneNames,
  }) {
    final buffer = StringBuffer();
    // 写入 UTF-8 BOM，防止 Windows / Excel 等出现乱码
    buffer.write('\uFEFF');

    // CSV 列头
    final headers = [
      '镜号',
      '所属片段',
      '所属场次',
      '建议时长(秒)',
      '景别',
      '拍摄角度/机位',
      '运镜方式',
      '情绪基调',
      '分镜功能',
      '画面动作描述',
      '说话角色',
      '发声类型',
      '台词对白',
      '出场角色',
      '出场道具',
      '提示词(Prompt)',
      '首帧状态',
      '视频片段状态',
    ];

    buffer.writeln(headers.map(_escapeCsvCell).join(','));

    for (final shot in episode.shots) {
      final sceneInfo = shot.sceneId.isNotEmpty
          ? (sceneNames?[shot.sceneId] ?? shot.sceneId)
          : '';

      final speaker = _resolveSpeaker(shot, characterNames);
      final voiceType = _voiceTypeLabel(shot.voiceType);

      final charList = shot.characterIds
          .map((id) => characterNames?[id] ?? id)
          .join('; ');

      final propList = shot.propIds
          .map((id) => propNames?[id] ?? id)
          .join('; ');

      final hasFrame = shot.framePath != null && shot.framePath!.isNotEmpty;
      final hasClip = shot.clipPath != null && shot.clipPath!.isNotEmpty;

      final cameraAngleOrStaging = shot.directorDecisions.cameraStaging.isNotEmpty
          ? shot.directorDecisions.cameraStaging
          : (shot.cameraMove.isNotEmpty ? shot.cameraMove : '平视');

      final row = <String>[
        shot.number.toString(),
        shot.segmentId,
        sceneInfo,
        shot.durationSec.toStringAsFixed(1),
        shot.shotSize.label,
        cameraAngleOrStaging,
        shot.cameraMove,
        shot.mood,
        shot.function.label,
        shot.actionZh,
        speaker,
        voiceType,
        shot.dialogue,
        charList,
        propList,
        shot.assembledPrompt,
        hasFrame ? '已生成' : '未生成',
        hasClip ? '已生成' : '未生成',
      ];

      buffer.writeln(row.map((c) => _escapeCsvCell(c)).join(','));
    }

    return buffer.toString();
  }

  static String _resolveSpeaker(
    StudioShot shot,
    Map<String, String>? characterNames,
  ) {
    if (shot.characterIds.isNotEmpty) {
      final firstId = shot.characterIds.first;
      return characterNames?[firstId] ?? firstId;
    }
    return '';
  }

  static String _voiceTypeTag(UtteranceVoiceType type) {
    switch (type) {
      case UtteranceVoiceType.innerVoice:
        return ' (内心OS)';
      case UtteranceVoiceType.narration:
        return ' (旁白)';
      case UtteranceVoiceType.dialogue:
        return '';
    }
  }

  static String _voiceTypeLabel(UtteranceVoiceType type) {
    switch (type) {
      case UtteranceVoiceType.innerVoice:
        return '内心独白';
      case UtteranceVoiceType.narration:
        return '旁白';
      case UtteranceVoiceType.dialogue:
        return '对白';
    }
  }

  static String _sanitizeForMarkdownTable(String input) {
    return input
        .replaceAll('|', '\\|')
        .replaceAll('\r\n', '<br>')
        .replaceAll('\n', '<br>')
        .replaceAll('\r', '<br>')
        .trim();
  }

  /// 符合 RFC 4180 标准的 CSV 单元格转义
  static String _escapeCsvCell(String cell) {
    if (cell.contains(',') ||
        cell.contains('"') ||
        cell.contains('\n') ||
        cell.contains('\r')) {
      return '"${cell.replaceAll('"', '""')}"';
    }
    return cell;
  }
}
