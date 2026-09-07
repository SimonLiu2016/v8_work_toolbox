import 'package:flutter/material.dart';

import '../app_shortcut_tool.dart';
import '../batch_rename_tool.dart';
import '../bc_config_shell.dart';
import '../bc_config_tool.dart';
import '../clean_builds_tool.dart';
import '../folder_compare_tool.dart';
import '../image_resize_tool.dart';
import '../kma_package_tool.dart';
import 'reader/ui/doc_audio_reader_page.dart';
import 'slimmer/smart_disk_slimmer_page.dart';
import 'tool_definition.dart';
import 'unattended/unattended_page.dart';

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

class KmaPackageToolDefinition extends ToolDefinition {
  @override
  String get id => 'kma-package';
  @override
  String get title => 'KMA 包生成';
  @override
  String get subtitle => '生成加密的 KMA 资源包';
  @override
  IconData get icon => Icons.archive;
  @override
  ToolCategory get category => ToolCategory.build;
  @override
  Widget buildPage(BuildContext context) => const KmaPackageToolPage();
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

class CleanBuildsToolDefinition extends ToolDefinition {
  @override
  String get id => 'clean-builds';
  @override
  String get title => '清理构建产物';
  @override
  String get subtitle => '扫描并删除 build/ target 等缓存';
  @override
  IconData get icon => Icons.cleaning_services;
  @override
  ToolCategory get category => ToolCategory.build;
  @override
  Widget buildPage(BuildContext context) => const CleanBuildsHomePage();
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
  ToolCategory get category => ToolCategory.system;
  @override
  Widget buildPage(BuildContext context) => const UnattendedPage();
}

class DocAudioReaderToolDefinition extends ToolDefinition {
  @override
  String get id => 'doc-audio-reader';
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

/// ---------------------------------------------------------------------------
/// 工具注册表 (唯一的编译期注册点)
/// ---------------------------------------------------------------------------

class ToolRegistry {
  ToolRegistry._();

  static final List<ToolDefinition> tools = <ToolDefinition>[
    // 文件处理
    DocAudioReaderToolDefinition(),
    BatchRenameToolDefinition(),
    FolderCompareToolDefinition(),
    ImageResizeToolDefinition(),
    // 包与构建
    KmaPackageToolDefinition(),
    CleanBuildsToolDefinition(),
    // 系统与配置
    SmartDiskSlimmerToolDefinition(),
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

  static List<ToolDefinition> getByCategory(ToolCategory category) {
    return tools.where((t) => t.category == category).toList();
  }

  static List<ToolDefinition> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return tools;
    return tools.where((t) {
      return t.title.toLowerCase().contains(q) ||
          t.subtitle.toLowerCase().contains(q);
    }).toList();
  }
}
