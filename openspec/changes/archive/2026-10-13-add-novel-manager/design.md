## Context

V8WorkToolbox 是一个基于 Flutter 桌面端（macOS 优先）的一体化生产力与 AI 创作工具箱。现已有 `ai_video_studio`、`reader`、`notebook` 等模块，并具备成熟的 `AIService`（多模型统一调度）、`AppPaths`（统一用户支持目录）、`AppHttpClient` 与原生通道桥接基础设施。
本设计旨在引入独立的「小说管理器」模块（`lib/tools/novel_manager/`），解决小说从采集/导入到存储、AI 编辑改写，再到下游短视频工坊引用的全生命周期流转。

## Goals / Non-Goals

**Goals:**
- 提供标准化的小说与章节元数据存储架构（SQLite 快速索引 + 本地文件系统原子读写）。
- 实现双模采集架构：轻量规则 HTTP 抓取 + 反爬穿透抓取（支持集成 Firecrawl MCP 与 原生 WebView 会话复用应对 Cloudflare Turnstile）。
- 实现章节级事务与严格幂等性控制，支持断点续采与定时自动化任务。
- 建立两阶段导入清洗管道：优先正则/EPUB 结构解析，遇混乱文本或缺失属性时平滑降级至 AI 智能断章与元数据提炼。
- 提供内置章节编辑器与 AI 创作助手（改写、润色、续写生成）。
- 联动 `ai_video_studio`，提供小说与章节选择弹窗并注入短剧 IP 大纲流程。

**Non-Goals:**
- 第一期不实现 MOBI/AZW3/PDF 格式小说的导入（仅优先支持 `.txt` 和 `.epub`）。
- 不自建公共书源社区或在线书源市场，仅支持本地导入与用户自定义站点规则配置。
- 不替换已有的 `ai_video_studio` 剧本工作坊，而是作为其上游结构化数据源。

## Decisions

### 1. 数据存储与持久化架构：SQLite 元数据 + 本地文件系统原子存储
- **决策**：
  - 小说基本信息（`NovelMetadata`）、站点源配置（`SiteScraperRule`）、章节目录与索引（`NovelChapterIndex`）存储在本地 SQLite（`novel_manager.db`）。
  - 章节正文（长文本）不直接以单行超大字符串塞在数据库中，而是以自然章节组织存放在 `AppPaths.novelLibraryDir/<novel_id>/chapters/<chapter_index>.txt`，写操作严格走 `.tmp` 写入后 rename 的原子写入机制。
- **替代方案考虑**：
  - *方案 B：全部存 SQLite 单表*：长篇小说成百上千章（数百万字）会导致 SQLite 数据库文件急剧膨胀，备份与检索效率降低。
  - *方案 C：纯文件目录（JSON）存储*：缺乏强大的 SQL 过滤检索能力，标签多维筛选与分页性能较弱。

### 2. 双模采集引擎与反爬穿透设计 (Two-Tier Scraping Architecture)
- **决策**：
  - **Mode A (轻量级规则 HTTP)**：基于 `AppHttpClient`，解析 HTML（`package:html`），通过 CSS 选择器或正则提取目录与正文，速度快、资源少，适用于 90% 普通站点。
  - **Mode B (反爬穿透 / Bypass)**：对于返回 403 / Cloudflare Turnstile 挑战的站点（如 `www.szlajc.com`），支持两种穿透手段：
    1. 优先调用内建/本地 Firecrawl 服务（通过 `McpService` 调用 `firecrawl_scrape`），其底层包含指纹对抗与动态渲染能力；
    2. 或调用原生嵌入式 Webview 浏览器组件加载目标站点，提取经 CF 验证通过后的 Cookie 与 Header 并复用于后续采集。
- **替代方案考虑**：
  - *仅使用静态 HTTP*：面对反爬盾直接瘫痪，无法满足实际网络小说站点的采集诉求。

### 3. 采集调度与幂等/断点续采控制 (Idempotent Chapter Pipeline)
- **决策**：
  - 每条章节持久化均记录来源指纹：`origin_chapter_url` 或唯一章节 Hash。
  - 采集前拉取目录列表，过滤剔除本地已存在且正文字数完整的章节，仅针对差集创建采集任务队列。
  - 事务边界定义在「单章节」：单章抓取成功 -> 本地落盘 -> 写入/更新章节数据库记录 -> 提交事务。单章失败不影响其余章节，重试时自动从中断章节继续。

### 4. 导入管道：规则优先 + AI 智能兜底 (Rule-First & AI Fallback)
- **决策**：
  - **EPUB 解析**：使用 Dart 原生 archive 与 xml 解析器提取 `content.opf`、Spine 及 HTML 章节，转换为 Markdown。
  - **TXT 规则解析**：先进行字符编码探测（UTF-8 / GBK / GB2312），利用多层正则模板提取 `第X[章回节卷]`。
  - **AI 智能兜底**：当规则切分章节数 <= 1 或正文严重缺失目录特征时，触发 AI 分析管道：采样小说开头、中间、结尾长文本，由大模型输出小说书名、作者、标签、世界观背景及章节切分建议。

### 5. 短视频工坊集成方式：松耦合资产桥接 (Loose Coupling via Novel Selector)
- **决策**：
  - 在 `ai_video_studio` 创建剧集时新增 `NovelSelectorDialog`。用户选择整本或勾选多章后，读取章节内容与背景，以标准文本结构传递给 `StudioProjectManager` 的长文提取管线，与现有的 txt 文件上传流程保持底层处理一致。

### 6. 源站分类书库自动探索与两阶段智能去重清洗 (Category Exploration & Two-Stage AI Deduplication)
- **决策**：
  - **分类字典与自动分页**：支持站级分类规则模板（如 `{baseUrl}/class/{category}_{page}/`），首次扫描第 1 页自动正则匹配总记录数（如“共有相关作品 334025 部”）并精确折算总页数，允许用户选择扫描页码范围（如前 20 页）。
  - **第一级·本地预聚类分桶**：针对采集回来的数千条原始候选数据，利用前缀主干书名提取与作者特征进行本地快速分桶，剔除完全重复 ID 并归类同名变体组，将候选数据体积大幅缩减 80% 以上。
  - **第二级·AI 仲裁与书名净化**：将分桶结果传入 AI（`AIService`），大模型执行核心仲裁：
    1. 从变体组中挑选最优版本（优先规则：“无删减” > “全集” > “完整版” > 其他）；
    2. 自动净化规范书名（去除 SEO 后缀，还原作品真实核心名）；
    3. 纠正作者字段。若无网络或 AI 异常，自动降级为本地启发式规则兜底。
  - **触发时机**：扫描列表完成后自动触发 AI 去重，同时在 UI 提供手动重新去重按钮。


## Risks / Trade-offs

- **[Risk] 目标小说网站改版或动态反爬机制升级**  
  → *Mitigation*: 站点规则支持导出/导入与可视化修改字段；双模采集提供 Firecrawl 与原生 Webview 手工介入兜底。
- **[Risk] 超长篇小说（千万字）全量 AI 整理导致 Token 消耗巨大**  
  → *Mitigation*: AI 仅参与元数据提取与结构有问题的切分，绝大部分长文依赖本地规则高速解析；大文件切分采用滑窗分块，避免单次超大 Prompt。
- **[Risk] EPUB 解析中特殊排版或加密格式损坏**  
  → *Mitigation*: 严格捕获解析异常并提示用户，降级为纯文本容错提取。
