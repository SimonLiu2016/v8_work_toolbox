/// 角色 → 音色的固定映射。
///
/// **为什么按角色固定**：听力工具的价值在于形成"听声辨人"的条件反射。
/// 同一角色在站会与故障排查里都叫 Lena，用户听一遍就记住"Lena 是这个声音"，
/// 第二次遇到任何场景都能对上。轮转分配会破坏这一点。
///
/// **为什么不看音色名**：实测基频（F0，自相关）表明 `step_boy` 是 207Hz —— **女声**；
/// `boyinnansheng` 是 130Hz —— 男声。按名字猜性别会全错。映射表依据的是实测 F0。
///
/// **为什么只有 7 个**：一个会议场景通常 2-4 个说话人，7 个足够。首版接受
/// "非母语感"的音色，换来零额外依赖与零额外成本。
library;

/// 音色性别（由实测 F0 判定）。
enum VoiceGender { male, female }

/// 一个可用音色。
class VoiceProfile {
  /// 音色标识（发往 TTS 供应商的 voice id）。
  final String id;

  /// 展示名。
  final String label;

  /// 性别。
  final VoiceGender gender;

  /// 实测基频（Hz），用于人可读的溯源。
  final int measuredF0;

  const VoiceProfile(this.id, this.label, this.gender, this.measuredF0);
}

/// 首版采用的音色池。
///
/// F0 为 2026-10 在本机对 `stepaudio-2.5-tts` 实测所得（24kHz 单声道，
/// 取有声帧自相关中位数）。音色名与实际音高不符是常态，故此处以实测为准。
class VoicePool {
  static const VoiceProfile stepBoy = VoiceProfile(
      'step_boy', 'Bright (F)', VoiceGender.female, 207);
  static const VoiceProfile boyinnansheng = VoiceProfile(
      'boyinnansheng', 'Calm (M)', VoiceGender.male, 130);
  static const VoiceProfile dushexiaoyu = VoiceProfile(
      'dushexiaoyu', 'Soft (M)', VoiceGender.male, 129);
  static const VoiceProfile ruyananshi = VoiceProfile(
      'ruyananshi', 'Steady (M)', VoiceGender.male, 126);
  static const VoiceProfile cixingnansheng = VoiceProfile(
      'cixingnansheng', 'Mature (M)', VoiceGender.male, 119);
  static const VoiceProfile shenchennanyin = VoiceProfile(
      'shenchennanyin', 'Low (M)', VoiceGender.male, 136);
  static const VoiceProfile zhixingjiejie = VoiceProfile(
      'zhixingjiejie', 'Precise (F)', VoiceGender.female, 205);
  static const VoiceProfile elegantGentle = VoiceProfile(
      'elegantgentle-female', 'Gentle (F)', VoiceGender.female, 188);
  static const VoiceProfile livelyBreezy = VoiceProfile(
      'livelybreezy-female', 'Lively (F)', VoiceGender.female, 240);

  /// 全部音色。
  static const List<VoiceProfile> all = [
    stepBoy,
    boyinnansheng,
    dushexiaoyu,
    ruyananshi,
    cixingnansheng,
    shenchennanyin,
    zhixingjiejie,
    elegantGentle,
    livelyBreezy,
  ];

  /// 男声音色。
  static List<VoiceProfile> get males =>
      all.where((v) => v.gender == VoiceGender.male).toList();

  /// 女声音色。
  static List<VoiceProfile> get females =>
      all.where((v) => v.gender == VoiceGender.female).toList();

  /// 按 id 查找。
  static VoiceProfile? byId(String id) {
    for (final v in all) {
      if (v.id == id) return v;
    }
    return null;
  }
}

/// 角色 → 音色的映射表。
///
/// 键是**归一化后的角色标识**（见 [RoleVoiceMap.normalize]），值是音色 id。
/// 同一角色在所有场景、所有片段中恒定使用同一音色。
class RoleVoiceMap {
  /// 站会场景的角色集合。
  static const List<String> standupRoles = [
    'Scrum Master',
    'Backend',
    'Frontend',
    'QA',
    'Dev',
    'Developer',
  ];

  /// 故障排查场景的角色集合。
  static const List<String> incidentRoles = [
    'Incident Commander',
    'Lead',
    'Engineering Lead',
    'Lead Dev',
    'Comms',
    'DBA',
    'Eng',
    'Timeline',
    'Impact',
  ];

  /// 迭代规划场景的角色集合。
  static const List<String> sprintRoles = [
    'Product Owner',
    'Dev Lead',
    'Scrum Master',
    'Stakeholder',
    'QA',
  ];

  /// 客户支持场景的角色集合。
  static const List<String> supportRoles = [
    'Agent',
    'Support Agent',
    'User',
    'Customer',
  ];

  /// 角色 → 音色 id。
  ///
  /// 键是**归一化后的角色标识**（小写、单空格），见 [normalize]。
  static const Map<String, String> _byRole = {
    // 站会
    'scrum master': 'step_boy',
    'backend': 'boyinnansheng',
    'frontend': 'elegantgentle-female',
    'qa': 'zhixingjiejie',
    'dev': 'boyinnansheng',
    'developer': 'boyinnansheng',
    // 故障排查
    'incident commander': 'step_boy',
    'lead': 'boyinnansheng',
    'engineering lead': 'boyinnansheng',
    'lead dev': 'boyinnansheng',
    'comms': 'livelybreezy-female',
    'dba': 'ruyananshi',
    'eng': 'dushexiaoyu',
    'timeline': 'zhixingjiejie',
    'impact': 'elegantgentle-female',
    // 迭代规划
    'product owner': 'elegantgentle-female',
    'dev lead': 'boyinnansheng',
    'stakeholder': 'livelybreezy-female',
    // 客户支持
    'agent': 'elegantgentle-female',
    'support agent': 'elegantgentle-female',
    'user': 'boyinnansheng',
    'customer': 'boyinnansheng',
    // 面试
    'interviewer': 'boyinnansheng',
    'candidate': 'elegantgentle-female',
    'hiring manager': 'boyinnansheng',
    'senior': 'boyinnansheng',
    'lead developer': 'boyinnansheng',
    // 新人入职
    'tech lead': 'boyinnansheng',
    'new hire': 'elegantgentle-female',
    // 产品演示
    'sales engineer': 'boyinnansheng',
    'demo': 'boyinnansheng',
    // 技术演讲
    'speaker': 'boyinnansheng',
    'moderator': 'elegantgentle-female',
    'panellist': 'elegantgentle-female',
  };

  /// 说话人姓名 → 角色 id 的显式兜底。
  ///
  /// 源站点的说话人名不总是带角色标注（`IC:`、`Lead:`），但同一站点内名字到
  /// 角色的对应是稳定的。这张表把名字与角色绑定，让**同一角色跨场景**也能
  /// 拿到同一音色——这是"听声辨人"能跨场景成立的前提。
  static const Map<String, String> _bySpeaker = {
    // 站会
    'Lena': 'Scrum Master',
    'Alex': 'Backend',
    'Maria': 'Frontend',
    'Sam': 'QA',
    // 故障排查
    'IC': 'Incident Commander',
    'Lead': 'Lead',
    'DBA': 'DBA',
    'Comms': 'Comms',
    'Eng': 'Eng',
    'Timeline': 'Timeline',
    'Impact': 'Impact',
    // 迭代规划
    'Lisa': 'Product Owner',
    // 客户支持
    'Rachel': 'Agent',
    'Dmitri': 'User',
    // 面试
    'Interviewer': 'Interviewer',
    'Candidate': 'Candidate',
    // 新人入职
    'Sarah': 'Hiring Manager',
    'Leo': 'Tech Lead',
    'Tomasz': 'New Hire',
    // 产品演示
    // 注：Tom 在 sprint-planning 是 Dev Lead、在 product-demos 是 Sales Engineer，
    // 同名不同角色。product-demos 的对话带 `Sales Engineer (Tom):` 角色标注，
    // 走角色映射即可，不需要姓名映射。
    // 技术演讲
    'Speaker': 'Speaker',
  };

  /// 归一化角色标识：去掉多余空白并转小写，作为映射表的键。
  static String normalize(String role) =>
      role.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();

  /// 解析一个说话人（名字 + 可选角色标注）对应的音色 id。
  ///
  /// 优先级：显式角色映射 > 说话人姓名映射 > 按说话人姓名做稳定散列落到性别池。
  ///
  /// 最后一级保证**任何**说话人都拿得到音色，且同一名字每次都拿到同一个
  /// （散列是纯函数）——不会因为解析失败就在不同片段里换声音。
  static String voiceFor(String speaker, String role) {
    final normalizedRole = normalize(role);
    if (normalizedRole.isNotEmpty) {
      final hit = _byRole[normalizedRole];
      if (hit != null) return hit;
    }
    final byName = _bySpeaker[speaker.trim()];
    if (byName != null) {
      final hit = _byRole[normalize(byName)];
      if (hit != null) return hit;
    }
    return _fallbackFor(speaker);
  }

  /// 按名字散列落到音色池。
  ///
  /// 散列目标是"稳定 + 分散"：同一名字恒定，不同名字大概率不同。
  static String _fallbackFor(String speaker) {
    final name = speaker.trim();
    if (name.isEmpty) return VoicePool.stepBoy.id;
    var hash = 0;
    for (final unit in name.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    // 说话人名通常与角色性别无关，但常见约定（Alex/IC/Lead/DBA…）多是男性名。
    // 这里不做性别猜测，改用散列在全部音色上取模，保证可复现。
    return VoicePool.all[hash % VoicePool.all.length].id;
  }
}
