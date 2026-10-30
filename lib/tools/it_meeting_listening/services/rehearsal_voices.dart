/// 排练会议的固定角色音色表。
///
/// **为什么硬编码**：5 个角色是用户自己定的（Simon 就是用户本人，其余是固定
/// 的客户与合作方），不是通用场景；音色池里只有 5 个实测男声，可选项少到
/// 配置 UI 没有意义（design D6）。
///
/// **为什么不看音色名**：实测基频（F0，自相关）表明 `step_boy` 是 207Hz——
/// **女声**，名字骗人。本表只从实测男声里取，且引用 [VoicePool] 里已量过
/// F0 的 profile，让"全部为男声"这件事可被测试断言，而不是靠名字相信。
library;

import 'role_voice_map.dart';

/// 排练会议的角色 → 音色绑定。
class RehearsalVoices {
  RehearsalVoices._();

  /// 5 个角色各绑一个实测男声。
  ///
  /// `boyinnansheng`(130Hz) / `dushexiaoyu`(129Hz) / `ruyananshi`(126Hz) /
  /// `cixingnansheng`(119Hz) / `shenchennanyin`(136Hz) —— F0 差异 17Hz，
  /// 听感上可区分但都属男声区间。5 个角色用满 5 个男声。
  ///
  /// **跨会议一致**：同一角色在两场不同会议里拿到同一音色，用户才能"听声辨人"。
  /// 这是常量表而不是运行时分配的原因。
  static const Map<String, String> _byRoleId = {
    'simon': 'boyinnansheng',
    'xiaofeng': 'dushexiaoyu',
    'songyang': 'ruyananshi',
    'deepan': 'cixingnansheng',
    'josh': 'shenchennanyin',
  };

  /// 按角色标识取音色 id。未知角色回落到 [fallback]。
  static String voiceFor(String roleId) =>
      _byRoleId[roleId] ?? fallback;

  /// 未知角色的兜底音色（Simon 的）。
  ///
  /// 剧本理论上只有 5 个角色，但 LLM 偶尔会多写一个（比如 "Moderator"）。
  /// 此时宁可用 Simon 的音色，也不要散列到女声池——5 个角色全是男性，
  /// 突然出现女声会让人以为剧本串了。
  static const String fallback = 'boyinnansheng';

  /// 全部绑定（供测试与界面展示）。
  static Map<String, String> get all => Map.unmodifiable(_byRoleId);
}
