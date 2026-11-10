## Context

见 `proposal.md`。原 `charset_converter` 插件缺少 macOS 平台实现，调用时抛出 `MissingPluginException`，使得爬虫 `HttpRuleScraper` 和本地导入 `TxtParser` 在遇到 GBK 编码（如飘天文学等中文小说站点）时捕获异常并降级为 `latin1.decode`，导致中文高位字节变成 Latin-1 乱码。

## Goals / Non-Goals

**Goals:**
- 采用纯 Dart 跨平台方案 `fast_gbk`，无缝支持全平台（macOS、Windows、Linux、iOS、Android、Web、Unit Test）。
- 在 `HttpRuleScraper._fetchHtml` 中，一旦响应头或 HTML 头部探测到 `gbk` / `gb2312`，或常规 UTF-8 校验失败时，直接使用 `gbk.decode(bytes, allowMalformed: true)` 进行安全解码。
- 在 `TxtParser.parse` 中，对 GBK 文件的解码逻辑同步切换为 `fast_gbk`。
- 保证飘天文学检索出来的“最新章节”、“源站原始标题”、书名及作者 100% 正确呈现为正常中文。

**Non-Goals:**
- 不变更网络抓取的 CSS 选择器与去重算法。
- 不影响原本已是 UTF-8 编码的站点。

## Decisions

### 1. 选用 `fast_gbk: ^1.0.0`
- **决定**：使用纯 Dart 实现的 GBK 编解码器 `fast_gbk`。
- **原因**：无任何 C++/平台 MethodChannel 依赖，在 Flutter 单元测试、macOS 桌面端和后台隔离进程中均能即时同步调用，不存在 `MissingPluginException`。
- **替代方案对比**：
  - 手写 macOS 原生 Objective-C/Swift 插件补丁：开发维护成本高，破坏跨平台整洁性。
  - iconv 命令行子进程：效率低、IO 开销大、沙盒权限易受阻。
  - `fast_gbk`：成熟稳定、零配置、无原生胶水层。

### 2. 双重智能编码嗅探与降级策略
- **决定**：
  1. 第一阶段（显式/头部嗅探）：检查响应头 `content-type` 以及 HTML 前 2048 字节中是否存在 `charset=gbk` 或 `charset=gb2312`。若存在，直接使用 `gbk.decode(bytes, allowMalformed: true)`；
  2. 第二阶段（UTF-8 校验）：若未声明 GBK，尝试 `utf8.decode(bytes)`；
  3. 第三阶段（缺省智能回退）：若 UTF-8 解码抛出 `FormatException`，说明字节序列并非合法 UTF-8，自动尝试 `gbk.decode(bytes, allowMalformed: true)`，最后再兜底 `latin1`。

## Risks / Trade-offs

- [Risk] 依赖包解析冲突 → `fast_gbk` 依赖标准 Dart SDK，无外部嵌套依赖，兼容 Dart 3.x。
- [Trade-off] 纯 Dart 解码大文本（如上百兆 TXT）的 CPU 占用略高于原生 C 库 → 小说单章或单网页大小仅几十 KB，内存消耗在毫秒级微秒级，性能开销几乎为 0。
