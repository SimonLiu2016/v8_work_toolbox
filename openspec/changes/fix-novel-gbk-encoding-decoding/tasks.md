## 1. 依赖项配置与安装

- [x] 1.1 在 `pubspec.yaml` 中添加 `fast_gbk: ^1.0.0` 依赖并运行 `flutter pub get`

## 2. 爬虫与导入服务纯 Dart GBK 解码重构

- [x] 2.1 在 `lib/tools/novel_manager/services/http_rule_scraper.dart` 中引入 `package:fast_gbk/fast_gbk.dart`，重构 `_fetchHtml`，遇到 GBK 特征及 UTF-8 异常时使用 `gbk.decode(bytes, allowMalformed: true)`
- [x] 2.2 在 `lib/tools/novel_manager/services/txt_parser.dart` 中引入 `package:fast_gbk/fast_gbk.dart`，替换 `CharsetConverter.decode` 为 `gbk.decode`

## 3. 测试验证与打包部署

- [x] 3.1 编写单元测试验证 GBK 字节流准确解码为标准中文（验证书名、最新章节、作者不乱码）
- [x] 3.2 运行现场爬虫测试 `test/novel_scraper_integration_test.dart`，验证飘天文学现场抓取的作品标题与最新章节为真实简体中文
- [x] 3.3 执行 `./scripts/deploy_local.sh` 编译并热替换本机应用，彻底解决 macOS 界面乱码
