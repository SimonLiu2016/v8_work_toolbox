/// 全局通用的音频播放倍速阶梯
///
/// 覆盖从慢速精听 (0.5x, 0.75x, 0.85x) 到标准原速 (1.0x) 以及快速泛听 (1.25x, 1.5x, 1.75x, 2.0x)。
const List<double> kUniversalSpeedSteps = [
  0.5,
  0.75,
  0.8,
  0.85,
  1.0,
  1.25,
  1.5,
  1.75,
  2.0,
];

/// 兼容别名（供原有听力模块引用无缝升级）
const List<double> kListeningSpeedSteps = kUniversalSpeedSteps;
