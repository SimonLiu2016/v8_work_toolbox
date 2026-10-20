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
const String kToolIdAiVideoStudio = 'ai-video-studio';
const String kToolIdAgnesPlayground = 'agnes-playground';
const String kToolIdInfiniteCanvas = 'infinite-canvas';
const String kToolIdNovelManager = 'novel-manager';

/// 工具分类枚举。
///
/// 分类的顺序即活动栏的展示顺序（`ActivityBar` 遍历 `values`，仅排除
/// [privacy]——隐私空间有单独入口）。`system` 曾塞进一半工具而名不副实，现已按语义
/// 拆出 `ai` / `note` / `ops` / `security`，`system` 只保留真正的系统与配置类。
/// 新增分类无需改 `ActivityBar`——它按枚举遍历。同理，分类下的最后一个工具
/// 被移除时该分类也一并删除，否则活动栏会多出一个点进去什么都没有的入口。
///
/// 归属按**工具目的**有序判定（first match wins），不按实现技术：
/// 隐私内容 → 安全对抗 → 运维 → 本机配置维护 → 获取或再加工外部/机器生产的内容
/// （[ai]）→ 组织用户自己产出的文字（[note]）→ 文件形态变换（[file]）兜底；
/// 皆不匹配则新增分类，MUST NOT 硬塞。完整规则见
/// `openspec/specs/tool-category-assignment/spec.md`。
///
/// [ai] 与 [note] 的分界是**内容来源与所有权**，不是是否调用 AI 模型：
/// 前者收外部获取或机器再加工的内容，后者收用户自己写下的文字。因此
/// **带 AI 能力不改变归属**——给笔记类工具加 AI 问答不会让它搬来 [ai]。
enum ToolCategory {
  file('文件处理', Icons.folder_outlined),
  ai('AI 与资讯', Icons.assistant_outlined),
  note('笔记与学习', Icons.menu_book_rounded),
  ops('运维与监控', Icons.cloud_sync_rounded),
  security('安全工具', Icons.security_outlined),
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
