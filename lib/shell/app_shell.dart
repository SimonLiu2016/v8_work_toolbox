import 'package:flutter/material.dart';

import '../services/privacy_security_service.dart';
import '../theme/app_theme.dart';
import '../tools/network_proxy/ui/network_proxy_page.dart';
import '../tools/registry.dart';
import 'activity_bar.dart';
import 'ai_config_page.dart';
import 'privacy_lock_view.dart';
import 'tool_panel.dart';

/// 「常用软件」入口展示的工具数量上限。纵使 `recentTools` 持久化了更多条目，
/// 该入口只取最常用的几个，避免把快捷入口变成第二个「全部工具」。
const int kFrequentToolLimit = 5;

/// 现代化三栏工作区外壳 (ActivityBar + ToolPanel + Content)
class AppShell extends StatefulWidget {
  final List<String> initialRecentToolIds;
  final ValueChanged<String>? onToolUsed;
  final VoidCallback? onOpenSettings;

  const AppShell({
    super.key,
    this.initialRecentToolIds = const [],
    this.onToolUsed,
    this.onOpenSettings,
  });

  static AppShellState? of(BuildContext context) {
    return context.findAncestorStateOfType<AppShellState>();
  }

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> {
  ActivityViewType _currentView = ActivityViewType.all;
  ToolCategory? _currentCategory;
  late String _selectedToolId;
  bool _isPanelCollapsed = false;

  void openAiConfig() {
    setState(() {
      _currentView = ActivityViewType.ai;
    });
  }
  late List<String> _recentToolIds;
  final Set<int> _activatedToolIndices = <int>{};

  @override
  void initState() {
    super.initState();
    PrivacySecurityService.instance.isUnlockedNotifier.addListener(_onUnlockStateChanged);
    _recentToolIds = List<String>.from(widget.initialRecentToolIds);

    // Find the first recent tool that doesn't open in a new window
    String? initialToolId;
    for (final id in _recentToolIds) {
      final tool = ToolRegistry.findById(id);
      if (tool != null && !tool.openInNewWindow) {
        initialToolId = id;
        break;
      }
    }

    if (initialToolId != null) {
      _selectedToolId = initialToolId;
    } else {
      _selectedToolId = ToolRegistry.publicTools.first.id;
    }

    final initialIdx = ToolRegistry.tools.indexWhere((t) => t.id == _selectedToolId);
    _activatedToolIndices.add(initialIdx >= 0 ? initialIdx : 0);
  }

  @override
  void dispose() {
    PrivacySecurityService.instance.isUnlockedNotifier.removeListener(_onUnlockStateChanged);
    super.dispose();
  }

  void _onUnlockStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void updateRecentTools(List<String> recentIds) {
    setState(() {
      _recentToolIds = List<String>.from(recentIds);
    });
  }

  void selectTool(String toolId) {
    final tool = ToolRegistry.findById(toolId);
    if (tool == null) return;

    // If tool opens in a new window, do that instead of embedding.
    // 使用频率仍要记录：笔记本 / 密码工具 / 磐石运维都走独立窗口，漏记意味着它们
    // 永远进不了「常用软件」——而那恰是最常用的几个工具。隐私分类不记录：该入口
    // 无需解锁即可见，排隐私工具进去等于在解锁前泄露它们的存在。
    if (tool.openInNewWindow) {
      if (tool.category != ToolCategory.privacy) {
        _recordUsage(toolId);
      }
      tool.openNewWindow();
      return;
    }

    final idx = ToolRegistry.tools.indexWhere((t) => t.id == toolId);
    setState(() {
      _selectedToolId = toolId;
      if (tool.category == ToolCategory.privacy) {
        _currentView = ActivityViewType.privacy;
      } else {
        _currentView = ActivityViewType.all;
      }
      if (idx >= 0) _activatedToolIndices.add(idx);
      if (tool.category != ToolCategory.privacy) {
        _recordUsage(toolId);
      }
    });
  }

  void _recordUsage(String toolId) {
    setState(() {
      _recentToolIds.remove(toolId);
      _recentToolIds.insert(0, toolId);
      if (_recentToolIds.length > 8) {
        _recentToolIds = _recentToolIds.sublist(0, 8);
      }
    });
    widget.onToolUsed?.call(toolId);
  }

  List<ToolDefinition> _frequentTools() {
    // 频率数据 = recentTools 的 move-to-front 序，取前 5。过滤掉已不存在的
    // id（工具下线/改名）与隐私分类工具——常用软件入口无需解锁隐私空间即可
    // 见，把隐私工具排进去等于在解锁前泄露它们的存在。
    final out = <ToolDefinition>[];
    for (final id in _recentToolIds) {
      final tool = ToolRegistry.findById(id);
      if (tool == null) continue;
      if (tool.category == ToolCategory.privacy) continue;
      out.add(tool);
      if (out.length >= kFrequentToolLimit) break;
    }
    return out;
  }

  List<ToolDefinition> _getToolsForCurrentView() {
    if (_currentView == ActivityViewType.privacy) {
      return ToolRegistry.getByCategory(ToolCategory.privacy);
    }
    if (_currentView == ActivityViewType.frequent) {
      return _frequentTools();
    }
    if (_currentView == ActivityViewType.category && _currentCategory != null) {
      return ToolRegistry.getByCategory(_currentCategory!);
    }
    return ToolRegistry.publicTools;
  }

  String _getPanelTitle() {
    if (_currentView == ActivityViewType.privacy) {
      return '隐私空间';
    }
    if (_currentView == ActivityViewType.frequent) {
      return '常用软件';
    }
    if (_currentView == ActivityViewType.category && _currentCategory != null) {
      return _currentCategory!.label;
    }
    return '全部工具';
  }

  @override
  Widget build(BuildContext context) {
    final allTools = ToolRegistry.tools;
    final selectedIndex = allTools.indexWhere((t) => t.id == _selectedToolId);
    final activeToolIndex = selectedIndex >= 0 ? selectedIndex : 0;
    final isPrivacyLocked = _currentView == ActivityViewType.privacy &&
        !PrivacySecurityService.instance.isUnlocked;

    return Scaffold(
      backgroundColor: context.bgWindow,
      body: Row(
        children: [
          // 1. 左侧活动栏 (Activity Bar, 56px)
          ActivityBar(
            currentView: _currentView,
            currentCategory: _currentCategory,
            hasFrequentTools: _frequentTools().isNotEmpty,
            onViewSelected: (view) {
              setState(() {
                _currentView = view;
                if (view == ActivityViewType.privacy) {
                  final privacyTools = ToolRegistry.getByCategory(ToolCategory.privacy);
                  if (privacyTools.isNotEmpty && !privacyTools.any((t) => t.id == _selectedToolId)) {
                    _selectedToolId = privacyTools.first.id;
                    final idx = ToolRegistry.tools.indexWhere((t) => t.id == _selectedToolId);
                    if (idx >= 0) _activatedToolIndices.add(idx);
                  }
                } else {
                  final currentTool = ToolRegistry.findById(_selectedToolId);
                  if (currentTool?.category == ToolCategory.privacy) {
                    _selectedToolId = ToolRegistry.publicTools.first.id;
                    final idx = ToolRegistry.tools.indexWhere((t) => t.id == _selectedToolId);
                    if (idx >= 0) _activatedToolIndices.add(idx);
                  } else if (view == ActivityViewType.frequent) {
                    // 进入常用软件时，若当前选中的工具不在频率列表里，选中最常用的那个，
                    // 避免内容区停在「当前视图里看不到」的工具上。
                    final frequentIds = _frequentTools().map((t) => t.id).toSet();
                    if (!frequentIds.contains(_selectedToolId) &&
                        _frequentTools().isNotEmpty) {
                      _selectedToolId = _frequentTools().first.id;
                      final idx = ToolRegistry.tools.indexWhere((t) => t.id == _selectedToolId);
                      if (idx >= 0) _activatedToolIndices.add(idx);
                    }
                  }
                }
              });
            },
            onCategorySelected: (cat) {
              setState(() {
                _currentCategory = cat;
                _currentView = ActivityViewType.category;
                // 默认选中该分类下的首个工具
                final categoryTools = ToolRegistry.getByCategory(cat);
                if (categoryTools.isNotEmpty && !categoryTools.any((t) => t.id == _selectedToolId)) {
                  _selectedToolId = categoryTools.first.id;
                  final idx = ToolRegistry.tools.indexWhere((t) => t.id == _selectedToolId);
                  if (idx >= 0) _activatedToolIndices.add(idx);
                  _recordUsage(_selectedToolId);
                }
              });
            },
            onOpenSettings: () => widget.onOpenSettings?.call(),
          ),

          // 分割线
          VerticalDivider(width: 1, thickness: 1, color: context.borderSubtle),

          // 若隐私空间处于锁定状态，主视区直接被 PIN 安全锁界面接管拦截
          if (isPrivacyLocked)
            Expanded(
              child: PrivacyLockView(
                onUnlocked: () {
                  setState(() {});
                },
              ),
            )
          else ...[
            // 2. 中间工具分类面板 (在非全屏配置页时展示)
            if (_currentView != ActivityViewType.ai &&
                _currentView != ActivityViewType.proxy) ...[
              ToolPanel(
                title: _getPanelTitle(),
                tools: _getToolsForCurrentView(),
                selectedToolId: _selectedToolId,
                isCollapsed: _isPanelCollapsed,
                trailingAction: _currentView == ActivityViewType.privacy
                    ? Tooltip(
                        message: '立即锁定隐私空间',
                        child: IconButton(
                          icon: const Icon(Icons.lock_rounded, size: 16),
                          color: context.accentText,
                          onPressed: () {
                            PrivacySecurityService.instance.lock();
                          },
                        ),
                      )
                    : null,
                onToggleCollapse: () {
                  setState(() {
                    _isPanelCollapsed = !_isPanelCollapsed;
                  });
                },
                onSelectTool: (id) {
                  final tool = ToolRegistry.findById(id);
                  // If tool opens in a new window, do that instead of embedding
                  if (tool?.openInNewWindow == true) {
                    tool!.openNewWindow();
                    return;
                  }
                  final idx = ToolRegistry.tools.indexWhere((t) => t.id == id);
                  setState(() {
                    _selectedToolId = id;
                    if (idx >= 0) _activatedToolIndices.add(idx);
                    if (tool?.category != ToolCategory.privacy) {
                      _recordUsage(id);
                    }
                  });
                },
              ),
              VerticalDivider(width: 1, thickness: 1, color: context.borderSubtle),
            ],

            // 3. 右侧主工作区
            Expanded(
              child: _currentView == ActivityViewType.ai
                  ? const AiConfigPage()
                  : _currentView == ActivityViewType.proxy
                      ? const NetworkProxyPage()
                      : Container(
                      color: context.bgContent,
                      child: IndexedStack(
                        index: activeToolIndex,
                        children: allTools.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final tool = entry.value;
                          // Skip tools that open in their own window
                          if (tool.openInNewWindow) {
                            return const SizedBox.shrink();
                          }
                          if (_activatedToolIndices.contains(idx)) {
                            return tool.buildPage(context);
                          }
                          return const SizedBox.shrink();
                        }).toList(),
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}
