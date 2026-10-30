/// 说话人设定的解析：把「槽位 + 覆盖层 + 我的身份」折成一个可直接用的说话人。
///
/// **为什么单独一层**：界面、合成、词汇表三处都要回答"这一轮是谁在说、什么
/// 声音"，如果各写一遍回落逻辑，迟早会出现"界面上叫 Deepan、音频里是散列音色"
/// 的分叉。回落顺序写在一处，三处一起对。
///
/// 回落顺序：
/// 1. 槽位被标记为「我」→ 用「我的身份」的显示名与音色
/// 2. 覆盖层指定了显示名 / 音色 → 用指定的
/// 3. 都没有 → 显示名回落槽位标识，音色由槽位标识散列决定
///
/// 第 3 步的散列是纯函数：同一槽位在任何一次解析里都拿到同一音色，用户才能
/// "听声辨人"；换了槽位就大概率换声音。这与 `RoleVoiceMap._fallbackFor`
/// 是同一套思路，直接复用，避免两套散列给出不同的声音。
library;

import '../models/real_meeting_models.dart';
import 'role_voice_map.dart';

/// 解析后的说话人（展示与合成共用）。
class ResolvedSpeaker {
  /// 槽位标识（原稿里的「发言人 N」）。
  final String slotId;

  /// 展示用名字。
  final String displayName;

  /// 合成用音色标识。
  final String voiceId;

  /// 是否为「我」。
  final bool isMe;

  const ResolvedSpeaker({
    required this.slotId,
    required this.displayName,
    required this.voiceId,
    required this.isMe,
  });

  /// 展示用署名。
  ///
  /// 「我」加一个标记：用户在逐字稿里要能一眼看出哪句是自己说的——那是他
  /// 要知道"这场会我在哪个位置"的锚点。
  String get label => isMe ? '$displayName（我）' : displayName;
}

/// 说话人设定解析器。
class SpeakerProfileResolver {
  SpeakerProfileResolver._();

  /// 解析一个说话人槽位。
  ///
  /// [fallbackSlotId] 是**合并后的目标槽位**：当这个槽位被合并到别人身上且
  /// 自己又没做过任何设定时，显示名与散列音色都取目标槽位的——否则两个被
  /// 合并的槽位会在界面上显示成两个名字，合并等于没做。
  static ResolvedSpeaker resolve({
    required String slotId,
    required SpeakerSetting setting,
    required MyIdentity identity,
    String? fallbackSlotId,
  }) {
    if (setting.isMe) {
      return ResolvedSpeaker(
        slotId: slotId,
        displayName: identity.name,
        voiceId: identity.voiceId,
        isMe: true,
      );
    }

    final fallback = fallbackSlotId ?? slotId;
    final displayName =
        setting.displayName.trim().isEmpty ? fallback : setting.displayName.trim();
    final voiceId = setting.voiceId.trim().isEmpty
        ? RoleVoiceMap.voiceFor(fallback, '')
        : setting.voiceId.trim();

    return ResolvedSpeaker(
      slotId: slotId,
      displayName: displayName,
      voiceId: voiceId,
      isMe: false,
    );
  }

  /// 一次性解析全部槽位。
  static Map<String, ResolvedSpeaker> resolveAll({
    required Iterable<String> slotIds,
    required MeetingSpeakerSettings settings,
    required MyIdentity identity,
  }) =>
      {
        for (final id in slotIds)
          id: resolve(
            slotId: id,
            setting: settings.of(id),
            identity: identity,
            fallbackSlotId: settings.canonical(id),
          ),
      };
}
