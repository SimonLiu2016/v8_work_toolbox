## Why

在小说管理器中，使用“飘天文学”等采用 GBK/GB2312 编码的书源站点进行多页检索或抓取时，界面呈现的“最新章节”、“源站原始标题”、作品名称及作者全部显示为 Latin-1 乱码（如“一剑霸天”被解析为“Ò»½£°ÔÌì”）。排查发现原有的 `charset_converter` 依赖项缺少 macOS 桌面平台的原生插件支持，导致调用时始终抛出 `MissingPluginException` 并退化为 `latin1.decode`。本变更通过引入纯 Dart 跨平台 GBK 解码方案（`fast_gbk`），彻底解决 macOS 桌面端及跨平台环境下的中文 GBK/GB2312 网页与本地文本解码乱码问题。

## What Changes

- **引入纯 Dart GBK 解码器**：在 `pubspec.yaml` 中引入 `fast_gbk: ^1.0.0`，实现无需原生平台支持的纯 Dart Unicode 映射解码。
- **爬虫 HTML 响应解码重构**：改造 `HttpRuleScraper._fetchHtml`，在检测到响应头或 HTML 头部声明 `charset=gbk` / `charset=gb2312` 时，直接使用 `gbk.decode(bytes, allowMalformed: true)` 进行安全解码，彻底杜绝 Latin-1 乱码退化。
- **本地 TXT 导入解码重构**：改造 `TxtParser`，在使用 GBK 模式解析本地 `.txt` 小说文件时，同步切换为 `fast_gbk` 纯 Dart 解码，确保本地导入在 macOS 端同样无乱码。
- **移除非跨平台脆弱依赖**：移除对 `charset_converter` 的直接依赖，消除平台兼容性隐患。

## Capabilities

### Modified Capabilities

- `novel-manager`: 升级书源站点网页抓取与本地文本导入的中文字符集解码能力，支持在包括 macOS 在内的全平台稳定解析 GBK/GB2312 编码的网页内容与文件，消除乱码现象。

## Impact

- 受影响文件：`pubspec.yaml`、`lib/tools/novel_manager/services/http_rule_scraper.dart`、`lib/tools/novel_manager/services/txt_parser.dart`。
- 依赖项变更：增加 `fast_gbk: ^1.0.0`，移除 `charset_converter`。
- 界面体验：飘天文学及所有 GBK 站点的书名、作者、最新章节和原始标题均恢复为清晰正常的简体中文。
