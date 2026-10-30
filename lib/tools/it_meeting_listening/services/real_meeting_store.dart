/// 真实会议四层数据的落盘。
///
/// 目录布局（相对 `it_meeting_listening/`）：
///
/// ```
/// real_meetings/
///   meetings/<id>.json     原稿（只读）
///   settings/<id>.json     说话人设定（覆盖层，可整层删）
///   answers/<id>.json      插入的回答（回答层）
///   audio/<id>.json        合成状态（派生，删了重烘）
///   audio/<id>.mp3         整篇音频
///   turns/<id>/g<k>.mp3    逐轮音频（持久，**不进缓存目录**）
/// my_identity.json         「我的身份」（跨会议）
/// ```
///
/// **为什么拆成五个文件**（design D2）：它们的生命周期互不相同——
/// 重新导入替换原稿；改名只动覆盖层；插入回答只动回答层；重建音频只动派生层。
/// 合在一个文件里，任何一种操作都要整体重写，并连累其它三层的读写。
///
/// **为什么逐轮音频不进缓存目录**：界面的「清理缓存」会清空
/// `itMeetingListeningCacheDir`。插入一段回答后的整篇重建依赖这些逐轮文件，
/// 放缓存目录里清一次就退化成重跑几百轮 TTS（design D4）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../services/app_paths.dart';
import '../models/real_meeting_models.dart';

/// 真实会议数据仓库。
///
/// 测试用 [AppPaths.overrideRootForTesting] 换根目录，而不是给每个方法传
/// root——路径只有一个来源，多一个参数就多一处可能不一致。
class RealMeetingStore {
  RealMeetingStore();

  // ---------------------------------------------------------------------
  // 路径
  // ---------------------------------------------------------------------

  Directory get _meetingsDir => AppPaths.realMeetingMeetingsDir;
  Directory get _settingsDir => AppPaths.realMeetingSettingsDir;
  Directory get _answersDir => AppPaths.realMeetingAnswersDir;
  Directory get _audioDir => AppPaths.realMeetingAudioDir;

  File _meetingFile(String id) => File(p.join(_meetingsDir.path, '$id.json'));
  File _settingsFile(String id) => File(p.join(_settingsDir.path, '$id.json'));
  File _answersFile(String id) => File(p.join(_answersDir.path, '$id.json'));
  File _bakeStateFile(String id) => File(p.join(_audioDir.path, '$id.json'));

  /// 某场会议的逐轮音频目录（持久）。
  Directory turnsDir(String meetingId) =>
      AppPaths.realMeetingTurnsDir(meetingId);

  /// 某场会议的整篇音频文件。
  File audioFile(String meetingId) =>
      File(p.join(_audioDir.path, '$meetingId.mp3'));

  /// 某场会议的某个逐轮音频文件。
  File turnAudioFile(String meetingId, String fileName) =>
      File(p.join(turnsDir(meetingId).path, fileName));

  // ---------------------------------------------------------------------
  // 原子读写
  // ---------------------------------------------------------------------

  /// 原子写：先写临时文件再 rename。
  ///
  /// 写一半断电会让 JSON 截断，而截断的原稿意味着整场会议要从头导入。rename
  /// 在同一文件系统内是原子的。
  Future<void> _writeAtomic(File file, Object json) async {
    file.parent.createSync(recursive: true);
    final tmp = File('${file.path}.tmp');
    tmp.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(json),
      flush: true,
    );
    tmp.renameSync(file.path);
  }

  /// 读一个 JSON 文件；缺失、空、损坏都返回 null。
  ///
  /// 降级而不是抛异常：单场会议的原稿损坏不该让整个会议列表打不开。
  Future<Map<String, dynamic>?> _readJson(File file) async {
    if (!file.existsSync()) return null;
    try {
      final text = file.readAsStringSync();
      if (text.trim().isEmpty) return null;
      final decoded = jsonDecode(text);
      if (decoded is! Map) return null;
      return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------
  // 原稿
  // ---------------------------------------------------------------------

  Future<void> saveMeeting(RealMeeting meeting) =>
      _writeAtomic(_meetingFile(meeting.id), meeting.toJson());

  Future<RealMeeting?> loadMeeting(String id) async {
    final json = await _readJson(_meetingFile(id));
    return json == null ? null : RealMeeting.fromJson(json);
  }

  /// 全部已导入会议（按导入时间倒序）。
  Future<List<RealMeeting>> listMeetings() async {
    if (!_meetingsDir.existsSync()) return const [];
    final out = <RealMeeting>[];
    for (final entity in _meetingsDir.listSync()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final json = jsonDecode(entity.readAsStringSync());
        out.add(RealMeeting.fromJson(Map<String, dynamic>.from(json as Map)));
      } catch (_) {
        // 单场损坏不影响其余会议。
      }
    }
    out.sort((a, b) => b.importedAt.compareTo(a.importedAt));
    return out;
  }

  /// 按来源路径查找已导入的会议（判定"这次导入是不是同一场会的更新"）。
  Future<RealMeeting?> findBySourcePath(String sourcePath) async {
    for (final m in await listMeetings()) {
      if (m.sourcePath == sourcePath) return m;
    }
    return null;
  }

  /// 删除一场会议的全部痕迹（原稿、设定、回答、合成状态、音频）。
  ///
  /// 逐轮音频目录整体删：按文件逐个删会在中途失败时留下一地孤儿文件，而
  /// 孤儿文件既不会被索引引用，也没有任何入口能清理它们。
  Future<void> deleteMeeting(String meetingId) async {
    for (final f in [
      _meetingFile(meetingId),
      _settingsFile(meetingId),
      _answersFile(meetingId),
      _bakeStateFile(meetingId),
      audioFile(meetingId),
    ]) {
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
    final turns = turnsDir(meetingId);
    if (await turns.exists()) {
      try {
        await turns.delete(recursive: true);
      } catch (_) {}
    }
  }

  // ---------------------------------------------------------------------
  // 覆盖层
  // ---------------------------------------------------------------------

  Future<void> saveSettings(
          String meetingId, MeetingSpeakerSettings settings) =>
      _writeAtomic(_settingsFile(meetingId), settings.toJson());

  /// 读取说话人设定；未设定或文件损坏时返回空设定（全回落默认）。
  Future<MeetingSpeakerSettings> loadSettings(String meetingId) async {
    final json = await _readJson(_settingsFile(meetingId));
    return json == null
        ? const MeetingSpeakerSettings()
        : MeetingSpeakerSettings.fromJson(json);
  }

  /// 删除覆盖层（改名与音色全部回落默认；回答层与原稿不受影响）。
  Future<void> deleteSettings(String meetingId) async {
    final f = _settingsFile(meetingId);
    if (await f.exists()) {
      try {
        await f.delete();
      } catch (_) {}
    }
  }

  // ---------------------------------------------------------------------
  // 回答层
  // ---------------------------------------------------------------------

  Future<void> saveAnswers(String meetingId, List<InsertedAnswer> answers) =>
      _writeAtomic(_answersFile(meetingId), {
        'answers': answers.map((a) => a.toJson()).toList(),
      });

  Future<List<InsertedAnswer>> loadAnswers(String meetingId) async {
    final json = await _readJson(_answersFile(meetingId));
    if (json == null) return const [];
    return ((json['answers'] as List?) ?? const [])
        .map((e) => InsertedAnswer.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  // ---------------------------------------------------------------------
  // 合成状态
  // ---------------------------------------------------------------------

  Future<void> saveBakeState(String meetingId, MeetingBakeState state) =>
      _writeAtomic(_bakeStateFile(meetingId), state.toJson());

  Future<MeetingBakeState?> loadBakeState(String meetingId) async {
    final json = await _readJson(_bakeStateFile(meetingId));
    return json == null ? null : MeetingBakeState.fromJson(json);
  }

  // ---------------------------------------------------------------------
  // 我的身份
  // ---------------------------------------------------------------------

  Future<MyIdentity> loadMyIdentity() async {
    final json = await _readJson(AppPaths.listeningMyIdentityFile);
    return json == null ? const MyIdentity() : MyIdentity.fromJson(json);
  }

  Future<void> saveMyIdentity(MyIdentity identity) =>
      _writeAtomic(AppPaths.listeningMyIdentityFile, identity.toJson());
}
