import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../models/studio_models.dart';

/// 生图规格（尺寸档位与画幅比例）下拉选择组件 (spec: ai-video-studio / series-asset-library)。
///
/// 允许创作者在角色三视图、场景视角与道具生成时自由手动指定规格档位，
/// 直通映射 Agnes Image 2.5 Flash 原生规格。
class ImageDimensionSelector extends StatelessWidget {
  const ImageDimensionSelector({
    super.key,
    required this.selectedPreset,
    required this.onChanged,
    this.compact = false,
    this.enabled = true,
  });

  final StudioImageDimensionPreset selectedPreset;
  final ValueChanged<StudioImageDimensionPreset> onChanged;
  final bool compact;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<StudioImageDimensionPreset>(
      enabled: enabled,
      tooltip: '选择生图规格档位与画幅比例',
      color: context.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: context.borderSubtle),
      ),
      elevation: 4,
      initialValue: selectedPreset,
      onSelected: onChanged,
      itemBuilder: (ctx) {
        return StudioImageDimensionPreset.presets.map((preset) {
          final isSelected = preset.width == selectedPreset.width &&
              preset.height == selectedPreset.height &&
              preset.size == selectedPreset.size &&
              preset.ratio == selectedPreset.ratio;

          return PopupMenuItem<StudioImageDimensionPreset>(
            value: preset,
            height: 38,
            child: Row(
              children: [
                Icon(
                  isSelected ? Icons.check_circle : Icons.crop_original,
                  size: 16,
                  color: isSelected ? context.accentText : context.textTertiary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    preset.label,
                    style: TextStyle(
                      color: isSelected ? context.accentText : context.textPrimary,
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${preset.width}×${preset.height}',
                  style: TextStyle(
                    color: context.textTertiary,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          );
        }).toList();
      },
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: compact ? 4 : 6,
        ),
        decoration: BoxDecoration(
          color: context.bgCard,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: context.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.aspect_ratio, size: 14, color: context.accentText),
            const SizedBox(width: 6),
            Text(
              compact
                  ? '${selectedPreset.ratio} (${selectedPreset.size})'
                  : '${selectedPreset.ratio} · ${selectedPreset.size} (${selectedPreset.width}×${selectedPreset.height})',
              style: TextStyle(
                color: context.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, size: 16, color: context.textTertiary),
          ],
        ),
      ),
    );
  }
}
