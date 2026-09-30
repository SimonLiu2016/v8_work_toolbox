import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../tools/tool_definition.dart';

/// 活动栏选中的视图类型
enum ActivityViewType {
  all,      // 全部/搜索
  category, // 按特定分类过滤
  frequent, // 常用软件（按使用频率）
  ai,       // AI 能力配置
  privacy,  // 隐私空间
  proxy,    // 网络代理
}

class ActivityBar extends StatelessWidget {
  final ActivityViewType currentView;
  final ToolCategory? currentCategory;

  /// 是否存在可使用频率数据。为 false 时「常用软件」入口不渲染——新装机或
  /// 清空历史后，摆一个空入口比不摆更难解释。
  final bool hasFrequentTools;

  final ValueChanged<ActivityViewType> onViewSelected;
  final ValueChanged<ToolCategory> onCategorySelected;
  final VoidCallback onOpenSettings;

  const ActivityBar({
    super.key,
    required this.currentView,
    this.currentCategory,
    this.hasFrequentTools = false,
    required this.onViewSelected,
    required this.onCategorySelected,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      color: context.bgActivityBar,
      child: Column(
        children: [
          // 顶部预留 macOS 原生交通灯安全高度
          const SizedBox(height: 38),

          // 品牌 Logo 按钮 (点击可回到全部首页或呼出关于)
          Padding(
            padding: const EdgeInsets.only(bottom: AppTheme.space12),
            child: Tooltip(
              message: 'V8 工作工具箱',
              preferBelow: false,
              waitDuration: const Duration(milliseconds: 300),
              child: InkWell(
                onTap: () => onViewSelected(ActivityViewType.all),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 36,
                  height: 36,
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: context.borderSubtle, width: 0.5),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.asset(
                      'assets/images/app_logo.png',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Icon(
                        Icons.construction_rounded,
                        size: 20,
                        color: context.accentText,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 全部工具 (网格/搜索首页)
          _buildActivityItem(
            context,
            icon: Icons.grid_view_rounded,
            label: '全部工具',
            isSelected: currentView == ActivityViewType.all,
            onTap: () => onViewSelected(ActivityViewType.all),
          ),
          const SizedBox(height: AppTheme.space8),

          // 常用软件（按使用频率，无使用记录时不显示）。
          // 它是频率数据的投影而非语义分类，因此不作为 ToolCategory 的取值，
          // 而是一个独立入口：工具同时保留在原分类中。
          if (hasFrequentTools)
            _buildActivityItem(
              context,
              icon: Icons.history_rounded,
              label: '常用软件',
              isSelected: currentView == ActivityViewType.frequent,
              onTap: () => onViewSelected(ActivityViewType.frequent),
            ),
          if (hasFrequentTools) const SizedBox(height: AppTheme.space8),

          // 工具分类项目 (排除隐私空间)
          ...ToolCategory.values
              .where((cat) => cat != ToolCategory.privacy)
              .map((cat) {
            final isSelected = currentView == ActivityViewType.category && currentCategory == cat;
            return Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.space6),
              child: _buildActivityItem(
                context,
                icon: cat.icon,
                label: cat.label,
                isSelected: isSelected,
                onTap: () {
                  onCategorySelected(cat);
                  onViewSelected(ActivityViewType.category);
                },
              ),
            );
          }),

          // 分隔线
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Divider(color: context.borderSubtle, height: 1),
          ),

          // 隐私空间专属栏目入口
          _buildActivityItem(
            context,
            icon: Icons.shield_outlined,
            label: '隐私空间 (PIN 安全锁)',
            isSelected: currentView == ActivityViewType.privacy,
            onTap: () => onViewSelected(ActivityViewType.privacy),
          ),

          const Spacer(),

          // 网络代理入口 (系统级代理管理)
          _buildActivityItem(
            context,
            icon: Icons.vpn_lock_outlined,
            label: '网络代理',
            isSelected: currentView == ActivityViewType.proxy,
            onTap: () => onViewSelected(ActivityViewType.proxy),
          ),
          const SizedBox(height: AppTheme.space6),

          // AI 配置入口 (置于底部设置之上)
          _buildActivityItem(
            context,
            icon: Icons.smart_toy_outlined,
            label: 'AI 能力配置',
            isSelected: currentView == ActivityViewType.ai,
            onTap: () => onViewSelected(ActivityViewType.ai),
          ),
          const SizedBox(height: AppTheme.space6),

          // 全局设置
          _buildActivityItem(
            context,
            icon: Icons.settings_outlined,
            label: '系统偏好设置',
            isSelected: false,
            onTap: onOpenSettings,
          ),
          const SizedBox(height: AppTheme.space12),
        ],
      ),
    );
  }

  Widget _buildActivityItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: label,
      preferBelow: false,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 56,
          height: 42,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 选中时的左侧高亮指示条
              if (isSelected)
                Positioned(
                  left: 0,
                  top: 8,
                  bottom: 8,
                  child: Container(
                    width: 3,
                    decoration: BoxDecoration(
                      color: context.accentText,
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(2),
                        bottomRight: Radius.circular(2),
                      ),
                    ),
                  ),
                ),
              // 图标本体
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: isSelected ? context.bgSidebar : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: isSelected ? context.accentText : context.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
