import 'dart:io';
import 'package:flutter/material.dart';
import '../../services/ai_config_store.dart';
import '../../services/settings_store.dart';
import '../../services/system_service.dart';
import '../../shell/app_shell.dart';
import '../../theme/app_theme.dart';
import 'ai_disk_diagnostics_service.dart';
import 'disk_scanner_service.dart';
import 'slimmer_models.dart';

class SmartDiskSlimmerPage extends StatefulWidget {
  const SmartDiskSlimmerPage({super.key});

  @override
  State<SmartDiskSlimmerPage> createState() => _SmartDiskSlimmerPageState();
}

class _SmartDiskSlimmerPageState extends State<SmartDiskSlimmerPage> {
  final DiskScannerService _scanner = DiskScannerService();
  DiskSpaceInfo _diskSpace = const DiskSpaceInfo(totalBytes: 0, freeBytes: 0);

  List<SlimCandidateItem> _items = [];
  SlimmerCategory? _selectedCategory;
  ScanProgress? _scanProgress;
  bool _isBatchDiagnosing = false;
  String _aiDiagnosingStatus = ''; // AI 研判进度文本
  bool _hasScanned = false;

  @override
  void initState() {
    super.initState();
    _loadDiskSpace();
    // 移除自动扫描，由用户主动点击按钮触发
  }

  Future<void> _loadDiskSpace() async {
    final info = await SystemService.instance.getRootDiskSpace();
    if (mounted) {
      setState(() => _diskSpace = info);
    }
  }

  void _startScan() {
    setState(() {
      _hasScanned = true;
      _items = [];
      _scanProgress = null;
    });

    _scanner.startScan(
      onProgress: (progress) {
        if (mounted) {
          setState(() => _scanProgress = progress);
        }
      },
    ).listen((items) {
      if (mounted) {
        setState(() {
          _items = items;
        });
        // 扫描完成后应用用户保留标记
        _applyKeepList();
      }
    }, onDone: () {
      _loadDiskSpace();
      _autoBatchDiagnoseIfNeeded();
    });
  }

  /// 应用用户保留标记：将已标记为保留的条目设置为未勾选
  Future<void> _applyKeepList() async {
    final keepList = await SettingsStore.instance.getSlimmerKeepList();
    if (keepList.isEmpty || !mounted) return;

    setState(() {
      for (int i = 0; i < _items.length; i++) {
        final item = _items[i];
        if (keepList.contains(item.path)) {
          _items[i] = item.copyWith(isSelected: false, userMarkedKeep: true);
        }
      }
    });
  }

  /// 处理用户手动切换复选框，持久化保留决策
  void _onItemSelectionChanged(SlimCandidateItem item, bool newValue) {
    setState(() {
      final idx = _items.indexWhere((it) => it.id == item.id);
      if (idx != -1) {
        _items[idx] = item.copyWith(isSelected: newValue, userMarkedKeep: false);
      }
    });

    // 如果用户取消勾选一个"安全清理"条目，记录为保留
    if (!newValue && item.safety == SafetyRating.safe) {
      SettingsStore.instance.addSlimmerKeepPath(item.path);
    }
    // 如果用户重新勾选一个已标记保留的条目，移除保留标记
    if (newValue && item.userMarkedKeep) {
      SettingsStore.instance.removeSlimmerKeepPath(item.path);
    }
  }

  /// 全选当前筛选视图中的所有条目
  void _selectAll() {
    final filteredItems = _selectedCategory == null
        ? _items
        : _items.where((it) => it.category == _selectedCategory).toList();

    setState(() {
      for (final filtered in filteredItems) {
        final idx = _items.indexWhere((it) => it.id == filtered.id);
        if (idx != -1) {
          _items[idx] = _items[idx].copyWith(isSelected: true, userMarkedKeep: false);
        }
      }
    });
  }

  /// 取消全选当前筛选视图中的所有条目
  void _deselectAll() {
    final filteredItems = _selectedCategory == null
        ? _items
        : _items.where((it) => it.category == _selectedCategory).toList();

    setState(() {
      for (final filtered in filteredItems) {
        final idx = _items.indexWhere((it) => it.id == filtered.id);
        if (idx != -1) {
          _items[idx] = _items[idx].copyWith(isSelected: false);
        }
      }
    });

    // 批量持久化：将所有"安全清理"条目记录为保留（单次保存）
    final pathsToKeep = filteredItems
        .where((it) => it.safety == SafetyRating.safe)
        .map((it) => it.path)
        .toList();
    if (pathsToKeep.isNotEmpty) {
      SettingsStore.instance.addSlimmerKeepPaths(pathsToKeep);
    }
  }

  Future<void> _autoBatchDiagnoseIfNeeded() async {
    final ambiguous = _items
        .where((it) => !it.isAiAnalyzed && it.category == SlimmerCategory.orphanApp)
        .take(5)
        .toList();
    if (ambiguous.isEmpty) return;

    setState(() => _isBatchDiagnosing = true);

    List<AiDiagnosticResult> results;
    try {
      results = await AiDiskDiagnosticsService.instance.diagnoseBatch(ambiguous);
    } catch (e) {
      // AI 服务未配置或调用失败，静默结束，不阻塞 UI
      if (!mounted) return;
      setState(() => _isBatchDiagnosing = false);
      return;
    }

    if (!mounted) return;

    setState(() {
      _isBatchDiagnosing = false;
      for (final res in results) {
        final idx = _items.indexWhere((it) => it.id == res.itemId);
        if (idx != -1) {
          final old = _items[idx];
          _items[idx] = old.copyWith(
            aiAdvice: '【AI建议】${res.advice}',
            safety: res.safety,
            isSelected: res.canDelete,
            isAiAnalyzed: true,
          );
        }
      }
    });
  }

  bool _isAiConfigured() {
    return AiConfigStore.instance.providers.any((p) => p.enabled);
  }

  void _showUnconfiguredAiDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Row(
          children: [
            Icon(Icons.auto_awesome_rounded, color: AppTheme.accent),
            SizedBox(width: AppTheme.space8),
            Text('未配置 AI 模型', style: AppTheme.fontTitle),
          ],
        ),
        content: const Text(
          '使用 AI 智能研判功能需要先在「AI 配置」中启用一个模型供应商（如 DeepSeek、OpenAI、Claude、智谱 GLM 或本地 Ollama）。\n\n是否立即前往配置？',
          style: AppTheme.fontBodySecondary,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('稍后再说'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.settings_rounded, size: 16),
            label: const Text('前往 AI 配置'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accent,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              AppShell.of(context)?.openAiConfig();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _triggerManualBatchAi() async {
    if (!_isAiConfigured()) {
      _showUnconfiguredAiDialog();
      return;
    }

    // 优先分析用户显式勾选的条目；若无勾选，则分析未研判的条目
    final selected = _items.where((it) => it.isSelected).take(8).toList();
    final targets = selected.isNotEmpty
        ? selected
        : _items.where((it) => !it.isAiAnalyzed).take(8).toList();

    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先勾选需要 AI 研判的条目')),
      );
      return;
    }

    setState(() {
      _isBatchDiagnosing = true;
      _aiDiagnosingStatus = '准备开始分析 ${targets.length} 个条目...';
    });

    List<AiDiagnosticResult> results;
    try {
      results = await AiDiskDiagnosticsService.instance.diagnoseBatch(
        targets,
        onProgress: (current, total, itemName, completed) {
          if (mounted) {
            setState(() {
              _aiDiagnosingStatus = '正在分析 ($current/$total): $itemName';
            });
          }
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isBatchDiagnosing = false;
        _aiDiagnosingStatus = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('AI 研判失败：$e\n请在左侧「AI 配置」中检查供应商与模型设置。'),
          backgroundColor: AppTheme.error,
          duration: const Duration(seconds: 6),
        ),
      );
      return;
    }

    if (!mounted) return;

    setState(() {
      _isBatchDiagnosing = false;
      _aiDiagnosingStatus = '';
      for (final res in results) {
        final idx = _items.indexWhere((it) => it.id == res.itemId);
        if (idx != -1) {
          final old = _items[idx];
          _items[idx] = old.copyWith(
            aiAdvice: '【AI研判: ${res.inferredApp}】${res.advice}',
            safety: res.safety,
            isSelected: res.canDelete,
            isAiAnalyzed: true,
          );
        }
      }
    });

    if (results.isEmpty) {
      final err = AiDiskDiagnosticsService.instance.lastError;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(err != null ? 'AI 研判未成功: $err' : 'AI 研判返回 0 个有效结果，请检查模型响应或配置'),
          backgroundColor: AppTheme.warning,
          duration: const Duration(seconds: 6),
        ),
      );
    } else {
      final err = AiDiskDiagnosticsService.instance.lastError;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            results.length == targets.length
                ? '✓ AI 成功研判了 ${results.length} 个候选项目！'
                : '✓ AI 研判完成 ${results.length}/${targets.length} 个项目' + (err != null ? '（部分条目异常: $err）' : ''),
          ),
        ),
      );
    }
  }

  Future<void> _showSingleAiDialog(SlimCandidateItem item) async {
    if (!_isAiConfigured()) {
      _showUnconfiguredAiDialog();
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => FutureBuilder<String>(
        future: AiDiskDiagnosticsService.instance.diagnoseSingle(item),
        builder: (ctx, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return AlertDialog(
              backgroundColor: AppTheme.bgCard,
              title: Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent),
                  ),
                  const SizedBox(width: AppTheme.space12),
                  const Text('AI 正在深度研判中...', style: AppTheme.fontTitle),
                ],
              ),
              content: Text(
                '正在分析目录结构特征与安全风险，请稍候...\n${item.title}',
                style: AppTheme.fontBodySecondary,
              ),
            );
          }

          final report = snapshot.data ?? '无分析结果';
          return AlertDialog(
            backgroundColor: AppTheme.bgCard,
            title: Row(
              children: [
                const Icon(Icons.auto_awesome_rounded, color: AppTheme.accent),
                const SizedBox(width: AppTheme.space8),
                Expanded(child: Text('AI 智能研判：${item.title}', style: AppTheme.fontTitle)),
              ],
            ),
            content: SizedBox(
              width: 540,
              child: SingleChildScrollView(
                child: SelectableText(report, style: AppTheme.fontBody),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('了解并关闭'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _performCleanSelected() async {
    final selected = _items.where((it) => it.isSelected).toList();
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未勾选任何需要清理的项目')),
      );
      return;
    }

    final totalSize = selected.fold<int>(0, (sum, it) => sum + it.sizeBytes);
    final sizeStr = _formatSize(totalSize);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Row(
          children: [
            const Icon(Icons.delete_sweep_rounded, color: AppTheme.warning),
            const SizedBox(width: AppTheme.space8),
            const Text('移至系统废纸篓'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('即将把选中的 ${selected.length} 个项目移至 macOS 系统废纸篓：', style: AppTheme.fontBody),
            const SizedBox(height: AppTheme.space8),
            Text('预估释放空间: $sizeStr', style: AppTheme.fontTitle.copyWith(color: AppTheme.success)),
            const SizedBox(height: AppTheme.space12),
            Container(
              padding: const EdgeInsets.all(AppTheme.space12),
              decoration: BoxDecoration(
                color: AppTheme.bgInput,
                borderRadius: AppTheme.borderRadiusSmall,
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline_rounded, color: AppTheme.success, size: 20),
                  const SizedBox(width: AppTheme.space8),
                  Expanded(
                    child: Text(
                      '操作安全可逆：文件将进入系统废纸篓，可随时按 ⌘Z 或在废纸篓中右键“放回原处”。',
                      style: AppTheme.fontCaption.copyWith(color: AppTheme.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.warning),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('安全移入废纸篓', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final paths = selected.map((it) => it.path).toList();
    final ok = await SystemService.instance.recyclePaths(paths);

    if (ok) {
      setState(() {
        _items.removeWhere((it) => it.isSelected);
      });
      _loadDiskSpace();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已成功将 $sizeStr 文件移至废纸篓！'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              '清理失败：需要"完全磁盘访问权限"。\n'
              '请前往 系统设置 → 隐私与安全性 → 完全磁盘访问权限，添加 V8WorkToolbox。',
            ),
            backgroundColor: AppTheme.error,
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: '知道了',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    }
  }

  void _revealInFinder(String path) {
    try {
      Process.run('open', ['-R', path]);
    } catch (_) {}
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final filteredItems = _selectedCategory == null
        ? _items
        : _items.where((it) => it.category == _selectedCategory).toList();

    final selectedTotalBytes = _items
        .where((it) => it.isSelected)
        .fold<int>(0, (sum, it) => sum + it.sizeBytes);

    return Scaffold(
      backgroundColor: AppTheme.bgContent,
      body: Padding(
        padding: const EdgeInsets.all(AppTheme.space20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶部总览卡片
            _buildDiskOverviewCard(selectedTotalBytes),
            const SizedBox(height: AppTheme.space16),

            // 完全磁盘访问权限 (FDA) 受限警示横幅
            if (_scanProgress?.hasPermissionError == true)
              _buildFdaWarningBanner(),

            // 未扫描且不在扫描中时，展示就绪待扫引导面板
            if (!_hasScanned && !_scanner.isScanning)
              Expanded(child: _buildReadyToScanView())
            else ...[
              // 扫描进度条
              if (_scanProgress != null && !_scanProgress!.isCompleted)
                _buildScanProgressBar(),

              // AI 研判进度条
              if (_isBatchDiagnosing && _aiDiagnosingStatus.isNotEmpty)
                _buildAiProgressBar(),

              // 分类标签栏
              _buildCategoryTabs(),
              const SizedBox(height: AppTheme.space12),

              // 列表区域
              Expanded(
                child: filteredItems.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _scanner.isScanning ? Icons.sync : Icons.check_circle_outline_rounded,
                              size: 48,
                              color: AppTheme.textTertiary,
                            ),
                            const SizedBox(height: AppTheme.space12),
                            Text(
                              _scanner.isScanning ? '正在分级扫描磁盘中...' : '太棒了！当前分类下没有发现可清理垃圾',
                              style: AppTheme.fontBodySecondary,
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: filteredItems.length,
                        separatorBuilder: (_, __) => const SizedBox(height: AppTheme.space8),
                        itemBuilder: (ctx, idx) {
                          final item = filteredItems[idx];
                          return _buildItemTile(item);
                        },
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFdaWarningBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.space12),
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.space12, vertical: AppTheme.space8),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.12),
        borderRadius: AppTheme.borderRadiusSmall,
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.shield_outlined, color: AppTheme.warning, size: 20),
          const SizedBox(width: AppTheme.space10),
          Expanded(
            child: Text(
              '检测到部分目录受 macOS 权限限制无法读取完整信息。建议在系统设置中开启「完全磁盘访问权限」以获得最彻底的瘦身分析。',
              style: AppTheme.fontCaption.copyWith(color: AppTheme.textPrimary),
            ),
          ),
          const SizedBox(width: AppTheme.space10),
          TextButton.icon(
            icon: const Icon(Icons.open_in_new_rounded, size: 14),
            label: const Text('去开启'),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.warning,
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.space8),
            ),
            onPressed: () {
              Process.run('open', ['x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles']);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildReadyToScanView() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 580),
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.space32, vertical: AppTheme.space24),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: AppTheme.borderRadiusMedium,
          border: Border.all(color: AppTheme.borderSubtle),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.radar_rounded,
                size: 38,
                color: AppTheme.accent,
              ),
            ),
            const SizedBox(height: AppTheme.space16),
            const Text(
              '智能磁盘空间透视与系统瘦身',
              style: AppTheme.fontHeadline,
            ),
            const SizedBox(height: AppTheme.space8),
            const Text(
              '全面透视系统缓存、已卸载软件残留、IDE与运行环境多版本及大文件。\n按需分析并安全释放海量存储空间。',
              style: AppTheme.fontBodySecondary,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppTheme.space24),
            SizedBox(
              height: 44,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.rocket_launch_rounded, size: 20),
                label: const Text('开始全盘智能分析', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: AppTheme.space24),
                  shape: RoundedRectangleBorder(borderRadius: AppTheme.borderRadiusSmall),
                ),
                onPressed: _startScan,
              ),
            ),
            const SizedBox(height: AppTheme.space24),
            const Divider(color: AppTheme.borderSubtle),
            const SizedBox(height: AppTheme.space12),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _FeatureBadge(icon: Icons.restore_from_trash_rounded, title: '100% 废纸篓安全可逆'),
                _FeatureBadge(icon: Icons.layers_rounded, title: '三阶段渐进扫描'),
                _FeatureBadge(icon: Icons.auto_awesome_rounded, title: 'AI 存疑深度研判'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiskOverviewCard(int selectedBytes) {
    final usedGb = (_diskSpace.usedBytes / (1024 * 1024 * 1024)).toStringAsFixed(1);
    final totalGb = (_diskSpace.totalBytes / (1024 * 1024 * 1024)).toStringAsFixed(1);
    final freeGb = (_diskSpace.freeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.all(AppTheme.space16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: AppTheme.borderRadiusMedium,
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.pie_chart_rounded, color: AppTheme.accent),
              SizedBox(width: AppTheme.space8),
              Text('Macintosh HD 磁盘透视', style: AppTheme.fontTitle),
            ],
          ),
          const SizedBox(height: AppTheme.space12),
          Wrap(
            spacing: AppTheme.space8,
            runSpacing: AppTheme.space8,
            children: [
              OutlinedButton.icon(
                icon: _isBatchDiagnosing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent),
                      )
                    : const Icon(Icons.auto_awesome_rounded, size: 16),
                label: const Text('🤖 AI 批量诊断'),
                onPressed: _isBatchDiagnosing ? null : _triggerManualBatchAi,
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.select_all_rounded, size: 16),
                label: const Text('全选'),
                onPressed: _items.isEmpty ? null : _selectAll,
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.deselect_rounded, size: 16),
                label: const Text('取消全选'),
                onPressed: _items.isEmpty ? null : _deselectAll,
              ),
              OutlinedButton.icon(
                icon: Icon(_scanner.isScanning ? Icons.sync : Icons.refresh_rounded, size: 16),
                label: Text(_scanner.isScanning ? '扫描中...' : '重新扫描'),
                onPressed: _scanner.isScanning ? null : _startScan,
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                label: Text('安全移入废纸篓 (${_formatSize(selectedBytes)})'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                ),
                onPressed: selectedBytes > 0 ? _performCleanSelected : null,
              ),
            ],
          ),
          const SizedBox(height: AppTheme.space12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _diskSpace.usedPercentage,
              minHeight: 10,
              backgroundColor: AppTheme.bgInput,
              color: _diskSpace.usedPercentage > 0.9 ? AppTheme.error : AppTheme.accent,
            ),
          ),
          const SizedBox(height: AppTheme.space8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '已使用: $usedGb GB / $totalGb GB (${(_diskSpace.usedPercentage * 100).toStringAsFixed(1)}%)',
                style: AppTheme.fontBodySecondary,
              ),
              Text(
                '剩余可用: $freeGb GB',
                style: AppTheme.fontBodySecondary.copyWith(color: AppTheme.success),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScanProgressBar() {
    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.space12),
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.space12, vertical: AppTheme.space8),
      decoration: BoxDecoration(
        color: AppTheme.bgInput,
        borderRadius: AppTheme.borderRadiusSmall,
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent),
          ),
          const SizedBox(width: AppTheme.space12),
          Expanded(
            child: Text(
              '${_scanProgress!.stageName} (已发现 ${_scanProgress!.itemsFound} 项 / ${_formatSize(_scanProgress!.totalReclaimableBytes)})',
              style: AppTheme.fontCaption.copyWith(color: AppTheme.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAiProgressBar() {
    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.space12),
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.space12, vertical: AppTheme.space8),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.1),
        borderRadius: AppTheme.borderRadiusSmall,
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent),
          ),
          const SizedBox(width: AppTheme.space12),
          Expanded(
            child: Text(
              _aiDiagnosingStatus,
              style: AppTheme.fontCaption.copyWith(color: AppTheme.accent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTabs() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildFilterChip(null, '全部 (${_items.length})'),
          for (final cat in SlimmerCategory.values) ...[
            const SizedBox(width: AppTheme.space8),
            _buildFilterChip(
              cat,
              '${cat.label} (${_items.where((it) => it.category == cat).length})',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterChip(SlimmerCategory? cat, String label) {
    final isSelected = _selectedCategory == cat;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => setState(() => _selectedCategory = cat),
      selectedColor: AppTheme.accent.withValues(alpha: 0.2),
      labelStyle: TextStyle(
        color: isSelected ? AppTheme.accent : AppTheme.textSecondary,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      backgroundColor: AppTheme.bgCard,
      side: BorderSide(
        color: isSelected ? AppTheme.accent : AppTheme.borderSubtle,
      ),
    );
  }

  Widget _buildItemTile(SlimCandidateItem item) {
    Color safetyColor;
    switch (item.safety) {
      case SafetyRating.safe:
        safetyColor = AppTheme.success;
        break;
      case SafetyRating.caution:
        safetyColor = AppTheme.warning;
        break;
      case SafetyRating.danger:
        safetyColor = AppTheme.error;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.space12, vertical: AppTheme.space10),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: AppTheme.borderRadiusSmall,
        border: Border.all(
          color: item.isSelected ? AppTheme.accent.withValues(alpha: 0.4) : AppTheme.borderSubtle,
        ),
      ),
      child: Row(
        children: [
          Checkbox(
            value: item.isSelected,
            activeColor: AppTheme.accent,
            onChanged: (val) => _onItemSelectionChanged(item, val ?? false),
          ),
          const SizedBox(width: AppTheme.space8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(item.title, style: AppTheme.fontBody.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(width: AppTheme.space8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: safetyColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        item.safety.label,
                        style: TextStyle(color: safetyColor, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (item.version != null) ...[
                      const SizedBox(width: AppTheme.space6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.bgInput,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          item.version!,
                          style: AppTheme.fontCaption.copyWith(color: AppTheme.textSecondary),
                        ),
                      ),
                    ],
                    if (item.userMarkedKeep) ...[
                      const SizedBox(width: AppTheme.space6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          '用户标记保留',
                          style: TextStyle(color: AppTheme.accent, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  item.subtitle,
                  style: AppTheme.fontCaption.copyWith(color: AppTheme.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (item.aiAdvice != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome, size: 12, color: AppTheme.accent),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          item.aiAdvice!,
                          style: AppTheme.fontCaption.copyWith(color: AppTheme.accent),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppTheme.space12),
          Text(
            item.formattedSize,
            style: AppTheme.fontTitle.copyWith(
              color: item.sizeBytes > 1024 * 1024 * 1024 ? AppTheme.warning : AppTheme.textPrimary,
            ),
          ),
          const SizedBox(width: AppTheme.space12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: '让 AI 分析此文件/目录',
                icon: const Icon(Icons.auto_awesome_rounded, size: 18, color: AppTheme.accent),
                onPressed: () => _showSingleAiDialog(item),
              ),
              IconButton(
                tooltip: '在访达中显示',
                icon: const Icon(Icons.folder_open_rounded, size: 18, color: AppTheme.textSecondary),
                onPressed: () => _revealInFinder(item.path),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FeatureBadge extends StatelessWidget {
  final IconData icon;
  final String title;

  const _FeatureBadge({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppTheme.accent),
        const SizedBox(width: AppTheme.space6),
        Text(title, style: AppTheme.fontCaption.copyWith(color: AppTheme.textSecondary)),
      ],
    );
  }
}
