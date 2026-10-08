import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';

import '../app_shortcut_tool.dart';
import '../batch_rename_tool.dart';
import '../bc_config_shell.dart';
import '../bc_config_tool.dart';
import '../folder_compare_tool.dart';
import '../image_resize_tool.dart';
import 'ai_assistant/ui/ai_assistant_page.dart';
import 'ai_video_studio/ui/studio_shell.dart';
import 'notebook/ui/notebook_page.dart';
import 'ops_tool/ui/ops_tool_main_page.dart';
import 'password/ui/password_page.dart';
import 'private_browser/ui/private_browser_page.dart';
import 'private_browser/ui/video_library_view.dart';
import 'private_player/ui/private_media_player_page.dart';
import 'reader/ui/doc_audio_reader_page.dart';
import 'security_toolbox/ui/security_toolbox_main_page.dart';
import 'slimmer/smart_disk_slimmer_page.dart';
import 'tool_definition.dart';
import 'unattended/unattended_page.dart';
import 'vocab_book/ui/vocab_book_page.dart';

export 'tool_definition.dart';

/// ---------------------------------------------------------------------------
/// 工具定义薄适配器
/// ---------------------------------------------------------------------------

class BcConfigToolDefinition extends ToolDefinition {
  @override
  String get id => 'bc-config';
  @override
  String get title => 'BC配置工具';
  @override
  String get subtitle => '修改Beyond Compare配置';
  @override
  IconData get icon => Icons.tune;
  @override
  ToolCategory get category => ToolCategory.system;
  @override
  Widget buildPage(BuildContext context) => const BcConfigHomePage();
}

class BatchRenameToolDefinition extends ToolDefinition {
  @override
  String get id => 'batch-rename';
  @override
  String get title => '批量重命名';
  @override
  String get subtitle => '按规则批量重命名文件';
  @override
  IconData get icon => Icons.text_format;
  @override
  ToolCategory get category => ToolCategory.file;
  @override
  Widget buildPage(BuildContext context) => const BatchRenameHomePage();
}

class FolderCompareToolDefinition extends ToolDefinition {
  @override
  String get id => 'folder-compare';
  @override
  String get title => '文件夹对比';
  @override
  String get subtitle => '对比两个文件夹中的文件差异';
  @override
  IconData get icon => Icons.compare_arrows;
  @override
  ToolCategory get category => ToolCategory.file;
  @override
  Widget buildPage(BuildContext context) => const FolderCompareHomePage();
}

class BcConfigShellToolDefinition extends ToolDefinition {
  @override
  String get id => 'bc-shell';
  @override
  String get title => 'BC脚本管理';
  @override
  String get subtitle => '管理与执行BC配置脚本';
  @override
  IconData get icon => Icons.terminal;
  @override
  ToolCategory get category => ToolCategory.system;
  @override
  Widget buildPage(BuildContext context) => const BcConfigShellPage();
}

class ImageResizeToolDefinition extends ToolDefinition {
  @override
  String get id => 'image-resize';
  @override
  String get title => '图片尺寸修改';
  @override
  String get subtitle => '批量按比例或尺寸修改图片';
  @override
  IconData get icon => Icons.photo_size_select_large;
  @override
  ToolCategory get category => ToolCategory.file;
  @override
  Widget buildPage(BuildContext context) => const ImageResizeHomePage();
}

class AppShortcutToolDefinition extends ToolDefinition {
  @override
  String get id => 'app-shortcut';
  @override
  String get title => '应用快捷键获取';
  @override
  String get subtitle => '获取应用的快捷键信息并导出';
  @override
  IconData get icon => Icons.keyboard;
  @override
  ToolCategory get category => ToolCategory.system;
  @override
  Widget buildPage(BuildContext context) => const AppShortcutToolPage();
}

class SmartDiskSlimmerToolDefinition extends ToolDefinition {
  @override
  String get id => 'smart-disk-slimmer';
  @override
  String get title => '智能磁盘瘦身';
  @override
  String get subtitle => '全盘分级扫描、已卸载残留与开发多版本清理、AI 深度研判';
  @override
  IconData get icon => Icons.pie_chart_rounded;
  @override
  ToolCategory get category => ToolCategory.system;
  @override
  Widget buildPage(BuildContext context) => const SmartDiskSlimmerPage();
}

class UnattendedApproverToolDefinition extends ToolDefinition {
  @override
  String get id => 'unattended-approver';
  @override
  String get title => '无人值守助手';
  @override
  String get subtitle => '离开电脑时自动审批 AI 终端工具调用，机械安全硬地板兜底';
  @override
  IconData get icon => Icons.verified_user_rounded;
  @override
  ToolCategory get category => ToolCategory.ops;
  @override
  Widget buildPage(BuildContext context) => const UnattendedPage();
}

class DocAudioReaderToolDefinition extends ToolDefinition {
  @override
  String get id => kToolIdDocAudioReader;
  @override
  String get title => '文档语音朗读';
  @override
  String get subtitle => '多格式文档与网页正文提取，实时 AI 语音朗读与 MP3 导出';
  @override
  IconData get icon => Icons.record_voice_over_rounded;
  @override
  ToolCategory get category => ToolCategory.file;
  @override
  Widget buildPage(BuildContext context) => const DocAudioReaderPage();
}

class PrivateMediaPlayerToolDefinition extends ToolDefinition {
  @override
  String get id => 'private-media-player';
  @override
  String get title => '私密影音播放器';
  @override
  String get subtitle => '支持多格式播放、主流在线解析下载、AI 实时与按需字幕生成';
  @override
  IconData get icon => Icons.play_circle_filled_rounded;
  @override
  ToolCategory get category => ToolCategory.privacy;
  @override
  Widget buildPage(BuildContext context) => const PrivateMediaPlayerPage();
}

class PrivateBrowserToolDefinition extends ToolDefinition {
  @override
  String get id => 'private-browser';
  @override
  String get title => '私密浏览器';
  @override
  String get subtitle => '内置隐私浏览器，无痕浏览、视频探测、一键下载、实时字幕';
  @override
  IconData get icon => Icons.public_rounded;
  @override
  ToolCategory get category => ToolCategory.privacy;
  @override
  Widget buildPage(BuildContext context) => const PrivateBrowserPage();
}

class VideoLibraryToolDefinition extends ToolDefinition {
  @override
  String get id => 'video-library';
  @override
  String get title => '私密视频库';
  @override
  String get subtitle => '多级分类与标签管理，AI 智能打标与语义搜索';
  @override
  IconData get icon => Icons.video_library_rounded;
  @override
  ToolCategory get category => ToolCategory.privacy;
  @override
  Widget buildPage(BuildContext context) => const VideoLibraryView();
}

class AiAssistantToolDefinition extends ToolDefinition {
  @override
  String get id => kToolIdAiAssistant;
  @override
  String get title => 'AI资讯与检索';
  @override
  String get subtitle => '全网实时爬虫检索与对话，定时追踪最新资讯';
  @override
  IconData get icon => Icons.assistant_outlined;
  @override
  ToolCategory get category => ToolCategory.ai;
  @override
  Widget buildPage(BuildContext context) => const AiAssistantPage();
}

class AiVideoStudioToolDefinition extends ToolDefinition {
  AiVideoStudioToolDefinition();

  @override
  String get id => kToolIdAiVideoStudio;
  @override
  String get title => 'AI 短视频工坊';
  @override
  String get subtitle => '从创意到成片：剧本分镜、角色资产、配音字幕与双轨交付';
  @override
  IconData get icon => Icons.movie_creation_outlined;
  @override
  ToolCategory get category => ToolCategory.ai;

  // 独立窗口：FFmpeg 合成与云端图生视频都是分钟级任务，主窗口被其他工具挤占
  // 时不该中断；合成进度条也需要一个不会被切走的可见区域。
  @override
  bool get openInNewWindow => true;

  @override
  Future<void> openNewWindow() async {
    try {
      final windows = await WindowController.getAll();
      for (final window in windows) {
        if (window.arguments == kToolIdAiVideoStudio) {
          await window.show();
          return;
        }
      }
      final controller = await WindowController.create(
        WindowConfiguration(
          arguments: kToolIdAiVideoStudio,
          hiddenAtLaunch: false,
        ),
      );
      await controller.show();
    } catch (e) {
      debugPrint('Failed to open AI video studio window: $e');
    }
  }

  @override
  Widget buildPage(BuildContext context) => const StudioShellPage();
}

class NotebookToolDefinition extends ToolDefinition {
  @override
  String get id => 'notebook';
  @override
  String get title => '笔记本';
  @override
  String get subtitle => '富文本笔记管理与印象笔记导入';
  @override
  IconData get icon => Icons.note_alt_outlined;
  @override
  ToolCategory get category => ToolCategory.note;

  @override
  bool get openInNewWindow => true;

  @override
  Future<void> openNewWindow() async {
    try {
      final windows = await WindowController.getAll();
      for (final window in windows) {
        if (window.arguments == 'notebook') {
          await window.show();
          return;
        }
      }
      final configuration = WindowConfiguration(
        arguments: 'notebook',
        hiddenAtLaunch: false,
      );
      final controller = await WindowController.create(configuration);
      await controller.show();
    } catch (e) {
      debugPrint('Failed to open notebook window: $e');
    }
  }

  @override
  Widget buildPage(BuildContext context) => const NotebookPage();
}

class VocabBookToolDefinition extends ToolDefinition {
  @override
  String get id => 'vocab-book';
  @override
  String get title => '生词本';
  @override
  String get subtitle => '划词查询积累与掌握程度复习';
  @override
  IconData get icon => Icons.menu_book_rounded;
  @override
  ToolCategory get category => ToolCategory.note;
  @override
  Widget buildPage(BuildContext context) => const VocabBookPage();
}

class PasswordVaultToolDefinition extends ToolDefinition {
  @override
  String get id => 'password-vault';
  @override
  String get title => '密码工具';
  @override
  String get subtitle => '本地加密密码库：密码生成、TOTP 两步验证、体检报告';
  @override
  IconData get icon => Icons.lock_rounded;
  // 归属仍是 system：改为 privacy 会让它从「全部工具」掉到「只在隐私空间可见」，
  // 那是用户未要求的可见性变更（password_vault_registry_test 明确断言它公开可见）。
  // 「系统与配置里躺一个密码库」的名实不符是遗留问题，记在 change 的遗留项里。
  @override
  ToolCategory get category => ToolCategory.system;

  @override
  bool get openInNewWindow => true;

  @override
  Future<void> openNewWindow() async {
    try {
      final windows = await WindowController.getAll();
      for (final window in windows) {
        if (window.arguments == 'password-vault') {
          await window.show();
          return;
        }
      }
      final configuration = WindowConfiguration(
        arguments: 'password-vault',
        hiddenAtLaunch: false,
      );
      final controller = await WindowController.create(configuration);
      await controller.show();
    } catch (e) {
      debugPrint('Failed to open password vault window: $e');
    }
  }

  @override
  Widget buildPage(BuildContext context) => const PasswordPage();
}

class OpsToolDefinition extends ToolDefinition {
  @override
  String get id => 'ops-tool';
  @override
  String get title => '磐石运维工具';
  @override
  String get subtitle => 'DevOps 流水线、多源运营报告与自动化监控调度';
  @override
  IconData get icon => Icons.cloud_sync_rounded;
  @override
  ToolCategory get category => ToolCategory.ops;

  @override
  bool get openInNewWindow => true;

  @override
  Future<void> openNewWindow() async {
    try {
      final windows = await WindowController.getAll();
      for (final window in windows) {
        if (window.arguments == 'ops-tool') {
          await window.show();
          return;
        }
      }
      final configuration = WindowConfiguration(
        arguments: 'ops-tool',
        hiddenAtLaunch: false,
      );
      final controller = await WindowController.create(configuration);
      await controller.show();
    } catch (e) {
      debugPrint('Failed to open ops tool window: $e');
    }
  }

  @override
  Widget buildPage(BuildContext context) => const OpsToolMainPage();
}

/// ---------------------------------------------------------------------------
/// 工具注册表 (唯一的编译期注册点)
/// ---------------------------------------------------------------------------

class SecurityToolboxDefinition extends ToolDefinition {
  @override
  String get id => 'security-toolbox';
  @override
  String get title => '安全工具箱';
  @override
  String get subtitle => '渗透测试工作台：侦察、漏洞扫描、利用、情报与报告';
  @override
  IconData get icon => Icons.security_outlined;
  @override
  ToolCategory get category => ToolCategory.security;

  // 独立窗口：工具链执行是长进程，主窗口被其他工具挤占时不该中断扫描。
  @override
  bool get openInNewWindow => true;

  @override
  Future<void> openNewWindow() async {
    try {
      final windows = await WindowController.getAll();
      for (final window in windows) {
        if (window.arguments == 'security-toolbox') {
          await window.show();
          return;
        }
      }
      final controller = await WindowController.create(
        WindowConfiguration(
          arguments: 'security-toolbox',
          hiddenAtLaunch: false,
        ),
      );
      await controller.show();
    } catch (e) {
      debugPrint('Failed to open security toolbox window: $e');
    }
  }

  @override
  Widget buildPage(BuildContext context) => const SecurityToolboxMainPage();
}

class ToolRegistry {
  ToolRegistry._();

  static final List<ToolDefinition> tools = <ToolDefinition>[
    // 隐私空间
    PrivateMediaPlayerToolDefinition(),
    PrivateBrowserToolDefinition(),
    VideoLibraryToolDefinition(),
    PasswordVaultToolDefinition(),
    // 安全工具
    SecurityToolboxDefinition(),
    // 文件处理
    DocAudioReaderToolDefinition(),
    BatchRenameToolDefinition(),
    FolderCompareToolDefinition(),
    ImageResizeToolDefinition(),
    // 系统与配置
    OpsToolDefinition(),
    AiAssistantToolDefinition(),
    AiVideoStudioToolDefinition(),
    SmartDiskSlimmerToolDefinition(),
    NotebookToolDefinition(),
    VocabBookToolDefinition(),
    UnattendedApproverToolDefinition(),
    BcConfigToolDefinition(),
    BcConfigShellToolDefinition(),
    AppShortcutToolDefinition(),
  ];

  static ToolDefinition? findById(String id) {
    try {
      return tools.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  static List<ToolDefinition> get publicTools =>
      tools.where((t) => t.category != ToolCategory.privacy).toList();

  static List<ToolDefinition> getByCategory(ToolCategory category) {
    return tools.where((t) => t.category == category).toList();
  }

  static List<ToolDefinition> search(String query, {bool includePrivate = false}) {
    final base = includePrivate ? tools : publicTools;
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return base;
    return base.where((t) {
      return t.title.toLowerCase().contains(q) ||
          t.subtitle.toLowerCase().contains(q);
    }).toList();
  }
}
