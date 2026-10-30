import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;

import '../../../theme/app_theme.dart';
import '../services/asset_library.dart';

/// 资产库页：跨剧复用资产的浏览、删除与来源回溯。
///
/// 放在工坊侧导航里而不是只在选择器中出现——资产库的意义在于"我攒了什么"，
/// 只在下拉框里能看到它就不成其为库。
///
/// 这一页**不依赖选中剧集**：资产是跨剧的，用户常常正是为了找一张图才进来。
class AssetLibraryPage extends StatefulWidget {
  const AssetLibraryPage({super.key, required this.session});

  final dynamic session;

  @override
  State<AssetLibraryPage> createState() => _AssetLibraryPageState();
}

class _AssetLibraryPageState extends State<AssetLibraryPage> {
  AssetKind _kind = AssetKind.image;
  AssetCategory? _category;
  final TextEditingController _searchController = TextEditingController();
  List<StudioAsset> _assets = const [];
  bool _loading = true;

  StreamSubscription<List<StudioAsset>>? _streamSub;

  /// 分类是 [AssetLibrary.assetsOf] 的参数，关键词是 [AssetLibrary.search]
  /// 的输入。两者可同时生效：先搜再按 kind / category 过滤——search 是全库
  /// 语义匹配，不该被当前页签悄悄缩小范围。
  @override
  void initState() {
    super.initState();
    _streamSub = AssetLibrary.instance.stream.listen((_) {
      if (mounted) _load();
    });
    _load();
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({bool reload = false}) async {
    if (reload) {
      await AssetLibrary.instance.reload();
    } else {
      await AssetLibrary.instance.ensureLoaded();
    }
    final keyword = _searchController.text;
    List<StudioAsset> list;
    if (keyword.trim().isEmpty) {
      list = await AssetLibrary.instance.assetsOf(_kind, category: _category);
    } else {
      list = (await AssetLibrary.instance.search(keyword))
          .where((a) => a.kind == _kind)
          .where((a) => _category == null || a.category == _category)
          .toList();
    }
    if (!mounted) return;
    setState(() {
      _assets = list;
      _loading = false;
    });
  }

  /// 当前是否有任何筛选生效——空列表时用它区分"没攒过"和"筛掉了"，
  /// 两种情况的提示完全不同（spec: 资产库检索与分类）。
  bool get _hasFilter =>
      _searchController.text.trim().isNotEmpty || _category != null;

  /// 换分类。卡片右下角的分类角标点它——旧资产缺省落在 `other`，
  /// 用户需要一个不改数据的入口把它归位。
  Future<void> _editCategory(StudioAsset asset) async {
    final picked = await showModalBottomSheet<AssetCategory>(
      context: context,
      backgroundColor: context.bgCard,
      builder: (_) => RadioGroup<AssetCategory>(
        groupValue: asset.category,
        onChanged: (v) => Navigator.pop(context, v),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final c in AssetCategory.values)
                RadioListTile<AssetCategory>(
                  value: c,
                  title: Text(
                    c.label,
                    style:
                        TextStyle(color: context.textPrimary, fontSize: 13),
                  ),
                  activeColor: context.accentText,
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || picked == asset.category) return;
    await AssetLibrary.instance.setCategory(asset.id, picked);
    await _load();
  }

  /// 统一编辑资产信息（名称、所属分类与备注）。
  Future<void> _editAsset(StudioAsset asset) async {
    final nameCtrl = TextEditingController(text: asset.name ?? '');
    final noteCtrl = TextEditingController(text: asset.note ?? '');
    AssetCategory selectedCat = asset.category;

    final updated = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: context.bgCard,
              title: Row(
                children: [
                  Icon(Icons.edit_note, size: 22, color: context.accentText),
                  const SizedBox(width: 8),
                  Text(
                    '编辑资产信息',
                    style: TextStyle(
                      color: context.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 440,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '资产标识：${asset.id}',
                        style: TextStyle(
                          color: context.textTertiary,
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: nameCtrl,
                        style: TextStyle(color: context.textPrimary, fontSize: 13),
                        decoration: InputDecoration(
                          labelText: '资产名称',
                          hintText: '如：第1集主角拔剑特写、赛博朋克街道',
                          hintStyle: TextStyle(color: context.textDisabled, fontSize: 12),
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        '所属分类',
                        style: TextStyle(
                          color: context.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final cat in AssetCategory.values)
                            ChoiceChip(
                              label: Text(cat.label),
                              selected: selectedCat == cat,
                              onSelected: (sel) {
                                if (sel) {
                                  setDialogState(() => selectedCat = cat);
                                }
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: noteCtrl,
                        maxLines: 3,
                        style: TextStyle(color: context.textPrimary, fontSize: 13),
                        decoration: InputDecoration(
                          labelText: '备注 (可选)',
                          hintText: '填写该资产的适用场景、制作细节或修改意见...',
                          hintStyle: TextStyle(color: context.textDisabled, fontSize: 12),
                          alignLabelWithHint: true,
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogCtx, true),
                  child: const Text('保存修改'),
                ),
              ],
            );
          },
        );
      },
    );

    if (updated == true) {
      final newName = nameCtrl.text.trim();
      final newNote = noteCtrl.text.trim();
      await AssetLibrary.instance.updateAsset(
        asset.id,
        name: newName.isNotEmpty ? newName : null,
        category: selectedCat,
        note: newNote.isNotEmpty ? newNote : null,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('资产信息已更新')),
        );
      }
    }
  }

  Future<void> _delete(StudioAsset asset) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: context.bgCard,
        title: const Text('删除资产？'),
        content: const Text(
          '删除只影响资产库中的这一份。已把它用作角色或场景参考图的剧集'
          '不受影响——那些卡片持有的是各自的副本。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await AssetLibrary.instance.removeAsset(asset.id);
    await _load();
  }

  void _previewAsset(StudioAsset asset) {
    final file = asset.file;
    if (!file.existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('资产原文件不存在或已被移除')),
      );
      return;
    }
    if (asset.kind == AssetKind.image) {
      _showImageLightbox(context, asset);
    } else {
      _showVideoPlayer(context, asset);
    }
  }

  void _revealInFinder(StudioAsset asset) {
    final file = asset.file;
    if (file.existsSync()) {
      Process.run('open', ['-R', file.path]);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('资产原文件不存在')),
      );
    }
  }

  Future<void> _exportAsset(StudioAsset asset) async {
    final file = asset.file;
    if (!file.existsSync()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('资产原文件不存在')),
        );
      }
      return;
    }
    final ext = p.extension(file.path);
    final isVideo = asset.kind == AssetKind.clip;
    final defaultName =
        'asset_${asset.id}${ext.isNotEmpty ? ext : (isVideo ? ".mp4" : ".png")}';

    String? savePath;
    try {
      savePath = await FilePicker.platform.saveFile(
        dialogTitle: '导出资产到本地',
        fileName: defaultName,
      );
    } catch (_) {
      savePath = null;
    }

    if (savePath == null) {
      final home = Platform.environment['HOME'] ?? '';
      savePath = p.join(home, 'Downloads', defaultName);
    }

    try {
      final destFile = File(savePath);
      await destFile.parent.create(recursive: true);
      await file.copy(savePath);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已成功导出到：$savePath'),
            action: SnackBarAction(
              label: '打开访达',
              onPressed: () {
                if (Platform.isMacOS) {
                  Process.run('open', ['-R', savePath!]);
                }
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    }
  }

  void _showImageLightbox(BuildContext context, StudioAsset asset) {
    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return Dialog(
          backgroundColor: Colors.black87,
          insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 6.0,
                  child: Center(
                    child: Image.file(
                      asset.file,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 12,
                left: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    asset.id,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: '用系统应用打开',
                      icon: const Icon(Icons.open_in_new, color: Colors.white, size: 20),
                      onPressed: () => Process.run('open', [asset.file.path]),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: '在访达中显示',
                      icon: const Icon(Icons.folder_open_outlined, color: Colors.white, size: 20),
                      onPressed: () => _revealInFinder(asset),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: '导出到本地...',
                      icon: const Icon(Icons.download_outlined, color: Colors.white, size: 20),
                      onPressed: () => _exportAsset(asset),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: '关闭',
                      icon: const Icon(Icons.close, color: Colors.white, size: 20),
                      onPressed: () => Navigator.pop(dialogCtx),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showVideoPlayer(BuildContext context, StudioAsset asset) {
    showDialog<void>(
      context: context,
      builder: (_) => _AssetVideoPreviewDialog(
        asset: asset,
        onExport: _exportAsset,
        onRevealInFinder: _revealInFinder,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgContent,
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '资产库',
                  style: TextStyle(
                    color: context.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '跨剧复用。用作参考图的是副本，删这里不影响已有剧集。',
                  style: TextStyle(color: context.textTertiary, fontSize: 11),
                ),
                const Spacer(),
                SegmentedButton<AssetKind>(
                  segments: const [
                    ButtonSegment(
                      value: AssetKind.image,
                      label: Text('图片'),
                      icon: Icon(Icons.image_outlined, size: 14),
                    ),
                    ButtonSegment(
                      value: AssetKind.clip,
                      label: Text('视频片段'),
                      icon: Icon(Icons.movie_outlined, size: 14),
                    ),
                  ],
                  selected: {_kind},
                  onSelectionChanged: (s) {
                    setState(() {
                      _kind = s.first;
                      _loading = true;
                    });
                    _load();
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 220,
                  height: 34,
                  child: TextField(
                    controller: _searchController,
                    style: TextStyle(color: context.textPrimary, fontSize: 12),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '搜提示词或标签',
                      hintStyle: TextStyle(
                        color: context.textTertiary,
                        fontSize: 12,
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        size: 15,
                        color: context.textTertiary,
                      ),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.close, size: 14),
                              onPressed: () {
                                _searchController.clear();
                                _load();
                              },
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: context.borderSubtle),
                      ),
                    ),
                    onSubmitted: (_) => _load(),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 10),
                DropdownButton<AssetCategory?>(
                  value: _category,
                  hint: Text(
                    '全部分类',
                    style: TextStyle(color: context.textTertiary, fontSize: 12),
                  ),
                  dropdownColor: context.bgCard,
                  underline: const SizedBox.shrink(),
                  style: TextStyle(color: context.textPrimary, fontSize: 12),
                  items: [
                    DropdownMenuItem<AssetCategory?>(
                      value: null,
                      child: Text(
                        '全部分类',
                        style:
                            TextStyle(color: context.textPrimary, fontSize: 12),
                      ),
                    ),
                    for (final c in AssetCategory.values)
                      DropdownMenuItem<AssetCategory?>(
                        value: c,
                        child: Text(
                          c.label,
                          style:
                              TextStyle(color: context.textPrimary, fontSize: 12),
                        ),
                      ),
                  ],
                  onChanged: (v) {
                    setState(() => _category = v);
                    _load();
                  },
                ),
                const Spacer(),
                Text(
                  '${_assets.length} 项',
                  style: TextStyle(color: context.textTertiary, fontSize: 11),
                ),
                const SizedBox(width: 8),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: '刷新资产库',
                  icon: const Icon(Icons.refresh, size: 16),
                  color: context.textSecondary,
                  onPressed: () {
                    setState(() => _loading = true);
                    _load(reload: true);
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _assets.isEmpty
                      ? _Empty(kind: _kind, filtered: _hasFilter)
                      : GridView.builder(
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 220,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            childAspectRatio: 0.62,
                          ),
                          itemCount: _assets.length,
                          itemBuilder: (context, i) => _AssetCard(
                            asset: _assets[i],
                            onDelete: _delete,
                            onChangeCategory: _editCategory,
                            onEdit: _editAsset,
                            onPreview: _previewAsset,
                            onRevealInFinder: _revealInFinder,
                            onExport: _exportAsset,
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.kind, this.filtered = false});

  final AssetKind kind;
  final bool filtered;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            kind == AssetKind.image
                ? Icons.photo_library_outlined
                : Icons.video_library_outlined,
            size: 40,
            color: context.textTertiary,
          ),
          const SizedBox(height: 10),
          Text(
            filtered
                ? '没有匹配的资产。\n换个关键词，或把分类切回「全部分类」。'
                : (kind == AssetKind.image
                    ? '还没有图片资产。\n在分镜卡片上「收进资产库」即可积累。'
                    : '还没有视频资产。'),
            textAlign: TextAlign.center,
            style: TextStyle(color: context.textTertiary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _AssetCard extends StatelessWidget {
  const _AssetCard({
    required this.asset,
    required this.onDelete,
    required this.onChangeCategory,
    required this.onEdit,
    required this.onPreview,
    required this.onRevealInFinder,
    required this.onExport,
  });

  final StudioAsset asset;
  final Future<void> Function(StudioAsset) onDelete;
  final Future<void> Function(StudioAsset) onChangeCategory;
  final Future<void> Function(StudioAsset) onEdit;
  final void Function(StudioAsset) onPreview;
  final void Function(StudioAsset) onRevealInFinder;
  final Future<void> Function(StudioAsset) onExport;

  @override
  Widget build(BuildContext context) {
    final file = asset.file;
    final exists = file.existsSync();
    final isVideo = asset.kind == AssetKind.clip;
    final cover = asset.coverFile;

    return Container(
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: AppTheme.borderRadiusSmall,
        border: Border.all(color: context.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(6),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => onPreview(asset),
                        child: exists
                            ? (isVideo
                                ? (cover != null
                                    ? Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          Image.file(
                                            cover,
                                            fit: BoxFit.cover,
                                          ),
                                          Center(
                                            child: Container(
                                              padding: const EdgeInsets.all(7),
                                              decoration: BoxDecoration(
                                                color: Colors.black.withAlpha(140),
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(
                                                Icons.play_arrow,
                                                size: 26,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ],
                                      )
                                    : Container(
                                        decoration: const BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                            colors: [
                                              Color(0xFF1E293B),
                                              Color(0xFF0F172A),
                                            ],
                                          ),
                                        ),
                                        child: const Center(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.play_circle_outline,
                                                size: 38,
                                                color: Colors.white70,
                                              ),
                                              SizedBox(height: 4),
                                              Text(
                                                '视频',
                                                style: TextStyle(
                                                  color: Colors.white38,
                                                  fontSize: 10,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ))
                                : Image.file(file, fit: BoxFit.cover))
                            : Center(
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  color: context.textTertiary,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
                if (isVideo)
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(160),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.videocam, size: 10, color: Colors.white),
                          const SizedBox(width: 3),
                          Text(
                            asset.durationSec != null
                                ? '${asset.durationSec!.toStringAsFixed(1)}s'
                                : '视频',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Positioned(
                  bottom: 4,
                  right: 4,
                  child: InkWell(
                    onTap: () => onEdit(asset),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(160),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            asset.category.label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                            ),
                          ),
                          const SizedBox(width: 2),
                          const Icon(Icons.edit, size: 8, color: Colors.white70),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  asset.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  asset.prompt?.trim().isNotEmpty == true
                      ? asset.prompt!.trim()
                      : (asset.note?.trim().isNotEmpty == true
                          ? asset.note!.trim()
                          : '（无提示词）'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.textSecondary, fontSize: 11),
                ),
                const SizedBox(height: 2),
                Builder(
                  builder: (_) {
                    final dt = asset.createdAt.toLocal();
                    final timeStr =
                        '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
                        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                    return Text(
                      [
                        timeStr,
                        if (asset.model != null && asset.model!.isNotEmpty) asset.model!,
                        '${(asset.sizeBytes / 1024).toStringAsFixed(0)} KB',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: context.textTertiary, fontSize: 9.5),
                    );
                  },
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: '编辑信息',
                        icon: const Icon(Icons.edit_outlined, size: 15),
                        color: context.textSecondary,
                        onPressed: () => onEdit(asset),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: isVideo ? '播放视频' : '查看大图',
                        icon: Icon(
                          isVideo ? Icons.play_arrow_outlined : Icons.visibility_outlined,
                          size: 15,
                        ),
                        color: context.textSecondary,
                        onPressed: () => onPreview(asset),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: '在访达中显示',
                        icon: const Icon(Icons.folder_open_outlined, size: 15),
                        color: context.textSecondary,
                        onPressed: () => onRevealInFinder(asset),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: '导出到本地...',
                        icon: const Icon(Icons.download_outlined, size: 15),
                        color: context.textSecondary,
                        onPressed: () => onExport(asset),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: '删除',
                        icon: const Icon(Icons.delete_outline, size: 15),
                        color: context.errorText,
                        onPressed: () => onDelete(asset),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AssetVideoPreviewDialog extends StatefulWidget {
  const _AssetVideoPreviewDialog({
    required this.asset,
    required this.onExport,
    required this.onRevealInFinder,
  });

  final StudioAsset asset;
  final Future<void> Function(StudioAsset) onExport;
  final void Function(StudioAsset) onRevealInFinder;

  @override
  State<_AssetVideoPreviewDialog> createState() => _AssetVideoPreviewDialogState();
}

class _AssetVideoPreviewDialogState extends State<_AssetVideoPreviewDialog> {
  Player? _player;
  VideoController? _videoController;
  bool _hasError = false;
  String? _errorMessage;
  double _aspectRatio = 9 / 16;
  StreamSubscription? _errorSub;
  StreamSubscription? _videoParamsSub;

  @override
  void initState() {
    super.initState();
    try {
      _player = Player();
      _videoController = VideoController(_player!);
      _errorSub = _player!.stream.error.listen((err) {
        if (mounted) {
          setState(() {
            _hasError = true;
            _errorMessage = err.toString();
          });
        }
      });
      _videoParamsSub = _player!.stream.videoParams.listen((params) {
        if (mounted && params.aspect != null && params.aspect! > 0) {
          setState(() {
            _aspectRatio = params.aspect!;
          });
        }
      });
      _player!.open(Media(widget.asset.file.path));
      _player!.setPlaylistMode(PlaylistMode.loop);
    } catch (e) {
      _hasError = true;
      _errorMessage = e.toString();
    }
  }

  @override
  void dispose() {
    _errorSub?.cancel();
    _videoParamsSub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.bgCard,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 860,
        height: 640,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: context.borderSubtle)),
              ),
              child: Row(
                children: [
                  Icon(Icons.video_library_outlined, size: 16, color: context.accentText),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '视频资产：${widget.asset.displayName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '使用系统播放器打开',
                    icon: const Icon(Icons.open_in_new, size: 16),
                    onPressed: () => Process.run('open', [widget.asset.file.path]),
                  ),
                  IconButton(
                    tooltip: '在访达中显示',
                    icon: const Icon(Icons.folder_open_outlined, size: 16),
                    onPressed: () => widget.onRevealInFinder(widget.asset),
                  ),
                  IconButton(
                    tooltip: '导出到本地...',
                    icon: const Icon(Icons.download_outlined, size: 16),
                    onPressed: () => widget.onExport(widget.asset),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: '关闭',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                color: Colors.black,
                child: _hasError
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline, color: Colors.orange, size: 36),
                            const SizedBox(height: 8),
                            Text('内嵌播放器异常：${_errorMessage ?? "未知错误"}',
                                style: const TextStyle(color: Colors.white70, fontSize: 12)),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: () => Process.run('open', [widget.asset.file.path]),
                              icon: const Icon(Icons.launch, size: 14),
                              label: const Text('使用系统播放器打开'),
                            ),
                          ],
                        ),
                      )
                    : Center(
                        child: AspectRatio(
                          aspectRatio: _aspectRatio,
                          child: Video(controller: _videoController!),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
