import 'package:flutter/material.dart';

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
}
