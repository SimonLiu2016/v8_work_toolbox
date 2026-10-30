/// 说话人状态模型
///
/// 固定数量（首版 3 个）的说话人槽位，每个有名字与固定颜色，通过全局热键切换
/// 当前激活槽位。预留 [SpeakerSlot.source] 以便将来混用自动分离（design D5）。
library;

import 'package:flutter/material.dart';

/// 说话人来源。
enum SpeakerSource {
  /// 手动热键切换（v1 唯一来源）。
  manual,

  /// 自动声学聚类或 diarization API（预留，v1 不用）。
  auto,
}

/// 单个说话人槽位。
class SpeakerSlot {
  SpeakerSlot({
    required this.index,
    required this.name,
    required this.color,
    this.source = SpeakerSource.manual,
  });

  /// 槽位索引（0-based），与热键编号对应。
  final int index;

  /// 说话人显示名（用户可改）。
  String name;

  /// 该说话人的固定颜色。
  final Color color;

  /// 识别来源（预留自动分离扩展）。
  SpeakerSource source;
}

/// 说话人状态集合：固定槽位 + 当前激活槽位。
class SpeakerState {
  SpeakerState()
      : slots = List.generate(3, (i) {
          return SpeakerSlot(
            index: i,
            name: '说话人 ${i + 1}',
            // 三个可区分的默认色：红 / 蓝 / 绿（首版固定配色）。
            color: [
              const Color(0xFFE5534B),
              const Color(0xFF4C8DFF),
              const Color(0xFF3FB950),
            ][i],
          );
        }),
        activeIndex = 0;

  /// 固定 3 个槽位。
  final List<SpeakerSlot> slots;

  /// 当前激活槽位索引。
  int activeIndex;

  SpeakerSlot get active => slots[activeIndex];

  /// 切换激活槽位。索引越界时忽略。
  void setActive(int index) {
    if (index >= 0 && index < slots.length) {
      activeIndex = index;
    }
  }
}
