/// 听力练习工作区顶部标题栏：标题、统一「＋ 新建」菜单、词汇表与迷你播放器入口。
library;

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

/// 新建菜单动作。
enum WorkspaceNewAction {
  importRealMeeting,
  createRehearsal,
  syncPublicSources,
}

/// 工作区顶部栏。
class WorkspaceHeader extends StatelessWidget {
  final ValueChanged<WorkspaceNewAction> onNewAction;
  final VoidCallback onOpenVocabulary;
  final VoidCallback onOpenMiniPlayer;

  const WorkspaceHeader({
    super.key,
    required this.onNewAction,
    required this.onOpenVocabulary,
    required this.onOpenMiniPlayer,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final textPrimary =
        isDark ? context.textPrimary : AppTheme.lightTextPrimary;
    final border = isDark ? context.borderSubtle : AppTheme.lightBorderSubtle;
    final accent = context.accentText;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: border)),
      ),
      child: Row(
        children: [
          Icon(Icons.headphones_rounded, size: 18, color: accent),
          const SizedBox(width: 8),
          Text(
            '听力练习',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: textPrimary,
            ),
          ),
          const Spacer(),
          PopupMenuButton<WorkspaceNewAction>(
            key: const ValueKey('workspace-new-menu-btn'),
            tooltip: '新建或同步内容',
            color: context.bgCardHover,
            onSelected: onNewAction,
            itemBuilder: (context) => const [
              PopupMenuItem(
                key: ValueKey('new-action-real-meeting'),
                value: WorkspaceNewAction.importRealMeeting,
                child: Row(
                  children: [
                    Icon(Icons.record_voice_over_outlined, size: 16),
                    SizedBox(width: 8),
                    Text('导入真实会议逐字稿…', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              PopupMenuItem(
                key: ValueKey('new-action-rehearsal'),
                value: WorkspaceNewAction.createRehearsal,
                child: Row(
                  children: [
                    Icon(Icons.campaign_outlined, size: 16),
                    SizedBox(width: 8),
                    Text('新建排练（导入会议材料）…', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                key: ValueKey('new-action-sync-public'),
                value: WorkspaceNewAction.syncPublicSources,
                child: Row(
                  children: [
                    Icon(Icons.cloud_download_outlined, size: 16),
                    SizedBox(width: 8),
                    Text('同步公开素材', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded, size: 16, color: Colors.white),
                  SizedBox(width: 4),
                  Text(
                    '新建',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 2),
                  Icon(
                    Icons.arrow_drop_down_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            key: const ValueKey('header-vocab-btn'),
            onPressed: onOpenVocabulary,
            icon: const Icon(Icons.menu_book_outlined, size: 16),
            label: const Text('词汇表'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            key: const ValueKey('header-mini-player-btn'),
            onPressed: onOpenMiniPlayer,
            icon: const Icon(Icons.picture_in_picture_alt_rounded, size: 16),
            label: const Text('迷你播放器'),
          ),
        ],
      ),
    );
  }
}
