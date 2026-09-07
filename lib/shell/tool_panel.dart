import 'package:flutter/material.dart';
import '../components/app_components.dart';
import '../theme/app_theme.dart';
import '../tools/registry.dart';

class ToolPanel extends StatefulWidget {
  final String title;
  final List<ToolDefinition> tools;
  final String selectedToolId;
  final ValueChanged<String> onSelectTool;
  final bool isCollapsed;
  final VoidCallback onToggleCollapse;
  final Widget? trailingAction;

  const ToolPanel({
    super.key,
    required this.title,
    required this.tools,
    required this.selectedToolId,
    required this.onSelectTool,
    required this.isCollapsed,
    required this.onToggleCollapse,
    this.trailingAction,
  });

  @override
  State<ToolPanel> createState() => _ToolPanelState();
}

class _ToolPanelState extends State<ToolPanel> {
  final TextEditingController _searchController = TextEditingController();
  String _filterQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ToolDefinition> get _filteredTools {
    final q = _filterQuery.trim().toLowerCase();
    if (q.isEmpty) return widget.tools;
    return widget.tools.where((t) {
      return t.title.toLowerCase().contains(q) ||
          t.subtitle.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final width = widget.isCollapsed ? 52.0 : 220.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeInOut,
      width: width,
      color: AppTheme.bgSidebar,
      child: widget.isCollapsed ? _buildCollapsedPanel() : _buildExpandedPanel(),
    );
  }

  Widget _buildCollapsedPanel() {
    return Column(
      children: [
        const SizedBox(height: 38), // 顶部安全高度
        IconButton(
          icon: const Icon(Icons.chevron_right, size: 18),
          color: AppTheme.textSecondary,
          tooltip: '展开面板',
          onPressed: widget.onToggleCollapse,
        ),
        const Divider(height: 1, color: AppTheme.borderSubtle),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: AppTheme.space8),
            itemCount: widget.tools.length,
            itemBuilder: (context, index) {
              final tool = widget.tools[index];
              final isSelected = tool.id == widget.selectedToolId;
              return Tooltip(
                message: '${tool.title} - ${tool.subtitle}',
                preferBelow: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.space6,
                    vertical: AppTheme.space4,
                  ),
                  child: InkWell(
                    onTap: () => widget.onSelectTool(tool.id),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      height: 38,
                      decoration: BoxDecoration(
                        color: isSelected ? AppTheme.bgSelected : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: isSelected
                            ? Border.all(color: AppTheme.accent.withValues(alpha: 0.4))
                            : null,
                      ),
                      child: Center(
                        child: Icon(
                          tool.icon,
                          size: 18,
                          color: isSelected ? AppTheme.accentLight : AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildExpandedPanel() {
    final list = _filteredTools;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 顶部预留安全边距 + 分类标题栏
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.space12,
            38 + AppTheme.space6,
            AppTheme.space8,
            AppTheme.space8,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: AppTheme.fontTitle.copyWith(fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              AppBadge(label: '${widget.tools.length}'),
              if (widget.trailingAction != null) ...[
                const SizedBox(width: AppTheme.space6),
                widget.trailingAction!,
              ],
              const SizedBox(width: AppTheme.space6),
              IconButton(
                icon: const Icon(Icons.chevron_left, size: 18),
                color: AppTheme.textSecondary,
                tooltip: '折叠面板',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                onPressed: widget.onToggleCollapse,
              ),
            ],
          ),
        ),

        // 搜索过滤框
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.space12,
            0,
            AppTheme.space12,
            AppTheme.space8,
          ),
          child: AppTextField(
            controller: _searchController,
            hintText: '过滤工具...',
            prefixIcon: const Icon(
              Icons.search,
              size: 14,
              color: AppTheme.textTertiary,
            ),
            suffixIcon: _filterQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 12),
                    color: AppTheme.textTertiary,
                    onPressed: () {
                      setState(() {
                        _searchController.clear();
                        _filterQuery = '';
                      });
                    },
                  )
                : null,
            onChanged: (val) {
              setState(() {
                _filterQuery = val;
              });
            },
          ),
        ),

        const Divider(height: 1, color: AppTheme.borderSubtle),

        // 工具条目列表
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Text(
                    '无匹配项',
                    style: AppTheme.fontCaption.copyWith(color: AppTheme.textTertiary),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.space8,
                    vertical: AppTheme.space8,
                  ),
                  itemCount: list.length,
                  itemBuilder: (context, index) {
                    final tool = list[index];
                    final isSelected = tool.id == widget.selectedToolId;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppTheme.space4),
                      child: AppListItem(
                        title: tool.title,
                        subtitle: tool.subtitle,
                        leading: Icon(
                          tool.icon,
                          size: 16,
                          color: isSelected ? AppTheme.accentLight : AppTheme.textSecondary,
                        ),
                        isSelected: isSelected,
                        onTap: () => widget.onSelectTool(tool.id),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
