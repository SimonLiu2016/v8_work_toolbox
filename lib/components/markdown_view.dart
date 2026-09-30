import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../theme/app_theme.dart';

// =============================================================================
// AppMarkdownView - 共享 Markdown 渲染组件
//
// 统一渲染 AI 输出的 markdown 内容（标题 / 强调 / 列表 / 代码块 / 引用）。
// 默认不持有滚动容器，高度交由调用方决定；传入 maxHeight 后可自行滚动。
//
// 注意：用户输入类文本不应使用本组件，应使用 SelectableText 原样呈现，
// 避免用户输入的字面语法（如 ** 或 `）被错误解析。
// =============================================================================

class AppMarkdownView extends StatelessWidget {
  final String data;

  /// 基础正文字体。各元素样式均由其派生；标题字号锚定绝对值，
  /// 不随 baseStyle 放大，避免调用方传入大字号时标题失控。
  final TextStyle baseStyle;

  /// 代码块与内联 code 的背景色。
  ///
  /// 默认 `null` 表示**按当前主题亮度推导**：深色主题取 [context.bgCardHover]
  /// （暗色容器上的既有外观），浅色主题取 [_lightCodeSurface]。本组件被暗色与浅色
  /// 容器共用，写死任一主题的字面量都会让另一种容器串色——曾因默认写死深灰，
  /// 浅色面板里的代码文字看不清。
  ///
  /// 传非 null 时以调用方为准，忽略主题。
  final Color? codeBlockColor;

  /// 浅色主题下代码块/内联 code 的底色。
  ///
  /// 比纯白深一档，保证代码在浅色容器上有可见边界（而非与背景同色）；
  /// 与 [context.bgCardHover] 在深色主题中承担同一职责。
  static const Color _lightCodeSurface = Color(0xFFF1F5F9);

  /// 是否允许选中并复制文本。`MarkdownBody` 的 `selectable` 默认为 false，
  /// 需显式开启，否则既有气泡/快报的选择复制能力会静默丢失。
  final bool selectable;

  /// 最大高度。为 null 时高度由调用方容器控制；设置后超长内容在组件内部滚动，
  /// 避免超长 AI 回答把聊天气泡无限撑高、淹没输入栏。
  final double? maxHeight;

  /// 链接点击回调。为 null 时链接渲染为不可点文本（默认，行为与改造前一致）。
  ///
  /// 快报与 AI 回答里出现的 URL 需要能点开——原先 [MarkdownBody] 没有接入这个
  /// 回调，链接只是看起来像链接的纯文本。
  final void Function(String url)? onTapLink;

  const AppMarkdownView({
    super.key,
    required this.data,
    this.baseStyle = AppTheme.fontBody,
    this.codeBlockColor,
    this.selectable = true,
    this.maxHeight,
    this.onTapLink,
  });

  @override
  Widget build(BuildContext context) {
    final body = MarkdownBody(
      data: data,
      selectable: selectable,
      styleSheet: _buildStyleSheet(context, _resolveCodeBackground(context)),
      onTapLink: onTapLink == null
          ? null
          : (text, href, title) => onTapLink!(href ?? text),
    );

    if (maxHeight == null) return body;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight!),
      child: SingleChildScrollView(child: body),
    );
  }

  /// 解析代码底色：显式传参优先，否则按主题亮度推导。
  ///
  /// 深色分支的取值与改造前完全一致（[context.bgCardHover]），故三个暗色
  /// 调用点不传参时外观零变化。
  Color _resolveCodeBackground(BuildContext context) {
    final explicit = codeBlockColor;
    if (explicit != null) return explicit;
    return Theme.of(context).brightness == Brightness.dark
        ? context.bgCardHover
        : _lightCodeSurface;
  }

  MarkdownStyleSheet _buildStyleSheet(
    BuildContext context,
    Color codeBackground,
  ) {
    final codeStyle = baseStyle.copyWith(
      fontFamily: 'monospace',
      fontSize: 13,
      backgroundColor: codeBackground,
    );

    return MarkdownStyleSheet(
      // 标题：字号锚定绝对值，仅字重与颜色从主题派生
      h1: baseStyle.copyWith(fontSize: 20, fontWeight: FontWeight.w700),
      h2: baseStyle.copyWith(fontSize: 17, fontWeight: FontWeight.w700),
      h3: baseStyle.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
      h1Padding: const EdgeInsets.only(
        top: AppTheme.space12,
        bottom: AppTheme.space4,
      ),
      h2Padding: const EdgeInsets.only(
        top: AppTheme.space12,
        bottom: AppTheme.space4,
      ),
      h3Padding: const EdgeInsets.only(
        top: AppTheme.space8,
        bottom: AppTheme.space4,
      ),

      // 正文与行内强调
      p: baseStyle,
      pPadding: const EdgeInsets.only(bottom: AppTheme.space8),
      strong: baseStyle.copyWith(fontWeight: FontWeight.w700),
      em: baseStyle.copyWith(fontStyle: FontStyle.italic),

      // 代码：本版本 MarkdownStyleSheet 未区分 codeblock，fence 代码块同样套用 code 样式
      code: codeStyle,
      codeblockDecoration: BoxDecoration(
        color: codeBackground,
        borderRadius: AppTheme.borderRadiusSmall,
        border: Border.all(color: context.borderSubtle),
      ),
      codeblockPadding: const EdgeInsets.all(AppTheme.space8),

      // 列表
      listBullet: baseStyle.copyWith(color: context.accentText),
      listBulletPadding: const EdgeInsets.only(right: AppTheme.space8),
      listIndent: AppTheme.space16,

      // 引用
      blockquote: AppTheme.fontBodySecondary,
      blockquoteDecoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: context.accentText.withValues(alpha: 0.5),
            width: 3,
          ),
        ),
      ),
      blockquotePadding: const EdgeInsets.only(left: AppTheme.space12),
    );
  }
}
