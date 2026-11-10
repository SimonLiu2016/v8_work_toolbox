import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 实时音频动态波形指示器
///
/// 根据实时音频输入电平 (0.0 ~ 1.0) 驱动多峰对称加权的能量波形柱。
/// 支持宽屏自适应铺展填充容器宽度，声音输入时高频高动态跳跃，静音时平滑贴底。
class LiveWaveformMeter extends StatelessWidget {
  /// 归一化瞬时音量电平 (0.0 ~ 1.0)
  final double level;

  /// 是否处于录音状态
  final bool isRecording;

  /// 波形最大高度 (默认 64.0)
  final double height;

  /// 柱条总数 (若为 null 则根据容器宽度自适应计算)
  final int? barCount;

  /// 柱条宽度 (默认 3.5)
  final double barWidth;

  /// 柱间距 (默认 4.0)
  final double barSpacing;

  /// 激活时的颜色 (为空时采用主题色)
  final Color? activeColor;

  /// 未激活或静音时的基线颜色
  final Color? inactiveColor;

  const LiveWaveformMeter({
    super.key,
    required this.level,
    required this.isRecording,
    this.height = 64.0,
    this.barCount,
    this.barWidth = 3.5,
    this.barSpacing = 4.0,
    this.activeColor,
    this.inactiveColor,
  });

  /// 计算多峰周期谐波权重 (0.25 ~ 1.0)
  @visibleForTesting
  static double calculateHarmonicWeight(int index, int total) {
    if (total <= 1) return 1.0;
    final x = index / (total - 1); // 0.0 ~ 1.0

    // 外包络：两端低、中间高
    final envelope = math.sin(math.pi * x);

    // 三频谐波交织，产生经典均衡器式起伏多峰
    final wave1 = math.sin(3.0 * math.pi * x).abs();
    final wave2 = math.cos(5.0 * math.pi * x).abs();

    final blended = 0.5 * envelope + 0.3 * wave1 * envelope + 0.2 * wave2 * envelope;
    return (blended * 0.75 + 0.25).clamp(0.2, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clampedLevel = level.clamp(0.0, 1.0);
    final effectiveActiveColor = activeColor ?? theme.colorScheme.primary;
    final effectiveInactiveColor = inactiveColor ??
        theme.colorScheme.outlineVariant.withValues(alpha: 0.25);

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final unitWidth = barWidth + barSpacing;

        final int count;
        if (barCount != null && barCount! > 0) {
          count = barCount!;
        } else if (availableWidth.isFinite && availableWidth > 0) {
          // 自适应计算柱条数量（最少 16 根，最多 80 根）
          count = (availableWidth / unitWidth).floor().clamp(16, 80);
        } else {
          count = 36;
        }

        return SizedBox(
          height: height,
          child: Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(count, (index) {
              final weight = calculateHarmonicWeight(index, count);

              final double barHeight;
              final Color barColor;

              if (isRecording && clampedLevel > 0.01) {
                // 结合非线性电平与谐波权重，充分利用垂直空间
                final dynamicHeight = 3.0 + (height - 3.0) * (clampedLevel * weight);
                barHeight = dynamicHeight.clamp(3.0, height);

                // 随能量增强从浅色过渡至饱满高亮
                barColor = Color.lerp(
                  effectiveActiveColor.withValues(alpha: 0.4),
                  effectiveActiveColor,
                  clampedLevel * weight,
                )!;
              } else {
                barHeight = 3.0;
                barColor = effectiveInactiveColor;
              }

              return Padding(
                padding: EdgeInsets.symmetric(horizontal: barSpacing / 2),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 65),
                  curve: Curves.easeOutCubic,
                  width: barWidth,
                  height: barHeight,
                  decoration: BoxDecoration(
                    color: barColor,
                    borderRadius: BorderRadius.circular(barWidth / 2),
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}
