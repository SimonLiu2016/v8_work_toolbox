import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../services/asset_library.dart';

/// 资产选择器。
///
/// 角色卡 / 场景卡选参考图、合成面板选片段共用这一个组件——它们的差别只在
/// [AssetKind] 与选中后的回调。为两种用途各写一个选择器会让"资产长什么样"
/// 出现两份实现，而后改的那份一定漏。
class AssetPickerDialog extends StatefulWidget {
  const AssetPickerDialog({super.key, required this.kind, this.title});

  final AssetKind kind;
  final String? title;

  /// 弹出并返回选中的资产；取消返回 null。
  static Future<StudioAsset?> show(
    BuildContext context, {
    required AssetKind kind,
    String? title,
  }) {
    return showDialog<StudioAsset>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => AssetPickerDialog(kind: kind, title: title),
    );
  }

  @override
  State<AssetPickerDialog> createState() => _AssetPickerDialogState();
}

class _AssetPickerDialogState extends State<AssetPickerDialog> {
  List<StudioAsset> _assets = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await AssetLibrary.instance.assetsOf(widget.kind);
    if (!mounted) return;
    setState(() {
      _assets = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.bgCard,
      title: Text(
        widget.title ?? '从资产库选择',
        style: TextStyle(color: context.textPrimary, fontSize: 15),
      ),
      content: SizedBox(
        width: 520,
        height: 420,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _assets.isEmpty
                ? _EmptyHint(kind: widget.kind)
                : GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 140,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                    ),
                    itemCount: _assets.length,
                    itemBuilder: (context, i) =>
                        _AssetCell(asset: _assets[i]),
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.kind});

  final AssetKind kind;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              kind == AssetKind.image
                  ? Icons.photo_library_outlined
                  : Icons.video_library_outlined,
              size: 36,
              color: context.textTertiary,
            ),
            const SizedBox(height: 10),
            Text(
              kind == AssetKind.image
                  ? '资产库里还没有图片。\n在分镜卡片或片段卡片上「收进资产库」即可积累。'
                  : '资产库里还没有视频片段。',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.textTertiary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssetCell extends StatelessWidget {
  const _AssetCell({required this.asset});

  final StudioAsset asset;

  @override
  Widget build(BuildContext context) {
    final file = asset.file;
    return InkWell(
      onTap: () => Navigator.pop(context, asset),
      borderRadius: BorderRadius.circular(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: context.borderSubtle),
                color: context.bgWindow,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: file.existsSync()
                    ? (asset.kind == AssetKind.image
                        ? Image.file(file, fit: BoxFit.cover)
                        : const Center(
                            child: Icon(Icons.play_circle_outline, size: 28),
                          ))
                    : Icon(
                        Icons.broken_image_outlined,
                        color: context.textTertiary,
                      ),
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            asset.id,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: context.textTertiary, fontSize: 9),
          ),
          Text(
            asset.prompt?.trim().isNotEmpty == true
                ? asset.prompt!.trim()
                : (asset.model ?? asset.source.label),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: context.textSecondary, fontSize: 10),
          ),
        ],
      ),
    );
  }
}
