import 'package:flutter/material.dart';

import '../services/privacy_security_service.dart';
import '../theme/app_theme.dart';
import '../tools/registry.dart';
import 'activity_bar.dart';
import 'ai_config_page.dart';
import 'privacy_lock_view.dart';
import 'tool_panel.dart';

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
    if (_recentToolIds.isNotEmpty && ToolRegistry.findById(_recentToolIds.first) != null) {
      _selectedToolId = _recentToolIds.first;
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

  List<ToolDefinition> _getToolsForCurrentView() {
    if (_currentView == ActivityViewType.privacy) {
      return ToolRegistry.getByCategory(ToolCategory.privacy);
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
      backgroundColor: AppTheme.bgWindow,
      body: Row(
        children: [
          // 1. 左侧活动栏 (Activity Bar, 56px)
          ActivityBar(
            currentView: _currentView,
            currentCategory: _currentCategory,
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
          const VerticalDivider(width: 1, thickness: 1, color: AppTheme.borderSubtle),

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
            if (_currentView != ActivityViewType.ai) ...[
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
                          color: AppTheme.accent,
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
                  final idx = ToolRegistry.tools.indexWhere((t) => t.id == id);
                  setState(() {
                    _selectedToolId = id;
                    if (idx >= 0) _activatedToolIndices.add(idx);
                    final tool = ToolRegistry.findById(id);
                    if (tool?.category != ToolCategory.privacy) {
                      _recordUsage(id);
                    }
                  });
                },
              ),
              const VerticalDivider(width: 1, thickness: 1, color: AppTheme.borderSubtle),
            ],

            // 3. 右侧主工作区
            Expanded(
              child: _currentView == ActivityViewType.ai
                  ? const AiConfigPage()
                  : Container(
                      color: AppTheme.bgContent,
                      child: IndexedStack(
                        index: activeToolIndex,
                        children: allTools.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final tool = entry.value;
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
