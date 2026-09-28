/// 工具标识常量。
///
/// 工具 id 同时是代理通道（[ProxySettings.perToolEnabled]）与持久化配置的
/// 键名，散落的字面量一旦漂移会让某个工具的代理静默失效且不报错。所有引用
/// 统一走这里的常量；常量值与既有 `config/proxy.json` 中已持久化的键逐字
/// 相同，因此无需数据迁移。
library;

import 'package:flutter/material.dart';

const String kToolIdAiAssistant = 'ai-assistant';
const String kToolIdDocAudioReader = 'doc-audio-reader';

/// 工具分类枚举
enum ToolCategory {
  file('文件处理', Icons.folder_outlined),
  build('包与构建', Icons.inventory_2_outlined),
  system('系统与配置', Icons.tune_outlined),
  privacy('隐私空间', Icons.shield_outlined);

  final String label;
  final IconData icon;

  const ToolCategory(this.label, this.icon);
}

/// 工具定义抽象基类
abstract class ToolDefinition {
  /// 唯一且稳定的工具标识符（用于持久化最近使用、设置等）
  String get id;

  /// 工具显示名称
  String get title;

  /// 工具简要描述
  String get subtitle;

  /// 工具图标
  IconData get icon;

  /// 所属分类
  ToolCategory get category;

  /// 构建工具页面 Widget
  Widget buildPage(BuildContext context);

  /// 是否在独立窗口中打开（默认 false）
  bool get openInNewWindow => false;

  /// 打开独立窗口（仅当 openInNewWindow 为 true 时调用）
  Future<void> openNewWindow() async {}
}
