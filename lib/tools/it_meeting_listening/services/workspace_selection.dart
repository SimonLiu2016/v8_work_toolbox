/// 工作区导航与选中状态控制器。
///
/// 将"当前浏览选中"与"当前正在播放"彻底解耦（design D2 / D3）：
/// - 左侧导航支持「真实会议」「排练」与「公开素材各场景」；
/// - 各分区内独立维护选中条目与搜索词；
/// - 切换离开排练或切换排练条目时支持未保存讲稿拦截钩子（`canLeaveRehearsal`）。
library;

import 'package:flutter/foundation.dart';

import '../models/listening_models.dart';

/// 左侧导航分区种类。
enum WorkspaceSectionKind {
  realMeetings,
  rehearsals,
  publicScene,
}

/// 左侧导航目标。
class WorkspaceNavTarget {
  final WorkspaceSectionKind kind;
  final MeetingScene? scene;

  const WorkspaceNavTarget._(this.kind, [this.scene]);

  const WorkspaceNavTarget.realMeetings()
      : this._(WorkspaceSectionKind.realMeetings);

  const WorkspaceNavTarget.rehearsals()
      : this._(WorkspaceSectionKind.rehearsals);

  const WorkspaceNavTarget.publicScene(MeetingScene scene)
      : this._(WorkspaceSectionKind.publicScene, scene);

  bool get isRealMeetings => kind == WorkspaceSectionKind.realMeetings;
  bool get isRehearsals => kind == WorkspaceSectionKind.rehearsals;
  bool get isPublicScene => kind == WorkspaceSectionKind.publicScene;

  @override
  bool operator ==(Object other) =>
      other is WorkspaceNavTarget &&
      other.kind == kind &&
      other.scene == scene;

  @override
  int get hashCode => Object.hash(kind, scene);
}

/// 工作区选中状态。
class WorkspaceSelection extends ChangeNotifier {
  WorkspaceNavTarget _section = const WorkspaceNavTarget.realMeetings();
  String? _selectedRealMeetingId;
  String? _selectedRehearsalId;
  String? _selectedPublicClipId;
  String? _selectedSourceId;
  String _realMeetingSearch = '';
  String _rehearsalSearch = '';
  bool _transcriptDrawerOpen = false;

  /// 离开当前排练前的确认钩子（有未保存讲稿时弹出"保存/放弃/取消"，返回 false 则取消切换）。
  Future<bool> Function()? canLeaveRehearsal;

  WorkspaceNavTarget get section => _section;
  String? get selectedRealMeetingId => _selectedRealMeetingId;
  String? get selectedRehearsalId => _selectedRehearsalId;
  String? get selectedPublicClipId => _selectedPublicClipId;
  String? get selectedSourceId => _selectedSourceId;
  String get realMeetingSearch => _realMeetingSearch;
  String get rehearsalSearch => _rehearsalSearch;
  bool get transcriptDrawerOpen => _transcriptDrawerOpen;

  /// 切换左侧导航分区。
  Future<bool> selectSection(WorkspaceNavTarget target) async {
    if (_section == target) return true;
    if (_section.isRehearsals && !target.isRehearsals) {
      final guard = canLeaveRehearsal;
      if (guard != null && !await guard()) return false;
    }
    _section = target;
    notifyListeners();
    return true;
  }

  /// 同步设置初始导航分区（启动恢复用，不触发离开守卫）。
  void setSectionInitial(WorkspaceNavTarget target) {
    _section = target;
    notifyListeners();
  }

  /// 选中某场真实会议。
  Future<bool> selectRealMeeting(String? meetingId) async {
    if (_selectedRealMeetingId == meetingId && _section.isRealMeetings) {
      return true;
    }
    if (_section.isRehearsals) {
      final guard = canLeaveRehearsal;
      if (guard != null && !await guard()) return false;
    }
    _section = const WorkspaceNavTarget.realMeetings();
    _selectedRealMeetingId = meetingId;
    notifyListeners();
    return true;
  }

  /// 仅更新真实会议选中项（不切分区）。
  void setSelectedRealMeetingId(String? meetingId) {
    if (_selectedRealMeetingId == meetingId) return;
    _selectedRealMeetingId = meetingId;
    notifyListeners();
  }

  /// 选中某场排练。
  Future<bool> selectRehearsal(String? materialId) async {
    if (_selectedRehearsalId == materialId && _section.isRehearsals) {
      return true;
    }
    if (_selectedRehearsalId != null && _selectedRehearsalId != materialId) {
      final guard = canLeaveRehearsal;
      if (guard != null && !await guard()) return false;
    }
    _section = const WorkspaceNavTarget.rehearsals();
    _selectedRehearsalId = materialId;
    notifyListeners();
    return true;
  }

  /// 仅更新排练选中项（不触发离开守卫，用于初始化或删除后回退）。
  void setSelectedRehearsalId(String? materialId) {
    if (_selectedRehearsalId == materialId) return;
    _selectedRehearsalId = materialId;
    notifyListeners();
  }

  /// 选中某条公开素材片段。
  void selectPublicClip(String? clipId) {
    if (_selectedPublicClipId == clipId) return;
    _selectedPublicClipId = clipId;
    notifyListeners();
  }

  /// 设置公开素材来源筛选（null = 全部来源）。
  void setSourceFilter(String? sourceId) {
    if (_selectedSourceId == sourceId) return;
    _selectedSourceId = sourceId;
    notifyListeners();
  }

  /// 设置真实会议搜索词。
  void setRealMeetingSearch(String query) {
    if (_realMeetingSearch == query) return;
    _realMeetingSearch = query;
    notifyListeners();
  }

  /// 设置排练搜索词。
  void setRehearsalSearch(String query) {
    if (_rehearsalSearch == query) return;
    _rehearsalSearch = query;
    notifyListeners();
  }

  /// 打开或关闭右侧精听抽屉。
  void setTranscriptDrawerOpen(bool open) {
    if (_transcriptDrawerOpen == open) return;
    _transcriptDrawerOpen = open;
    notifyListeners();
  }

  void toggleTranscriptDrawer() =>
      setTranscriptDrawerOpen(!_transcriptDrawerOpen);

  /// 根据给定的 [Clip] 跳转到所属分区并选中该条目（例如点击播放条标题或启动恢复）。
  Future<bool> jumpToClip(
    Clip clip, {
    String? Function(String clipId)? resolveRehearsalMaterialId,
  }) async {
    final src = clip.source.sourceId;
    if (src == 'real-meeting') {
      return selectRealMeeting(clip.id);
    }
    if (src == 'rehearsal') {
      final matId = resolveRehearsalMaterialId?.call(clip.id) ??
          (clip.id.startsWith('rehearsal_')
              ? clip.id.substring('rehearsal_'.length)
              : clip.id);
      return selectRehearsal(matId);
    }
    final ok = await selectSection(WorkspaceNavTarget.publicScene(clip.scene));
    if (ok) {
      selectPublicClip(clip.id);
    }
    return ok;
  }
}
