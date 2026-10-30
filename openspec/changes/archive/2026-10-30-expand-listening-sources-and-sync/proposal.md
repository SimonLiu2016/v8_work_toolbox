## Why

IT 会议听力工具首版把内容来源写死成 CoderSlingo 一个站点、只导入了 10 个 transcript 形态栏目中的 5 个，导致素材覆盖远低于站点的实际内容（站点听力区 18 个栏目 / 95 个页面，全站 exercises 下有 176 个分类含会议场景对话）；同时因为索引不记录每个栏目的同步状态，「更新素材」只能全量重抓 + 全量重烘焙（111 轮 TTS），无法增量。工具本身也还有两处体验缺口：显示名「IT 会议听力」过窄（内容已含客户支持等非会议场景），迷你播放窗因标题栏整体隐藏而**没有关闭入口**（窗口常驻置顶、失焦不自动关，用户只能重启应用才能关掉）。

## What Changes

- **工具显示名改为「听力练习」**：覆盖从"IT 会议"到"职场听力"的实际内容范围。**工具 id、目录名、素材目录保持不变**（id 是持久化键，术语本已有词条指向它）。
- **迷你播放窗增加关闭入口**：窗内提供关闭按钮，关闭**仅隐藏窗口、不终止播放**（播放状态在主进程）；关闭后可从主窗口按钮与菜单栏「会议音频播放器」重新唤出。
- **抽出 `ListeningSource` 内容来源抽象层**：`CoderSlingoSource` 降级为该接口的一个实现，站点特有的抓取/解析逻辑留在实现内部，素材库、烘焙器、播放器对来源无感知。
- **来源标识进入数据模型**：`ClipSource` 增加稳定的 `sourceId`（如 `coderslingo`），`Clip.id` 改为含源前缀的 `{sourceId}_{sceneId}_{columnSlug}_{block}`，避免多源下 id 撞车。旧素材一次性重烘焙迁移（顺带清掉 0 秒占位记录）。
- **引入每个来源的同步状态表**：记录每个栏目最后一次同步时间、源站 `lastmod`、失败原因与重试状态。
- **增量更新**：基于源站 `sitemap.xml` 的 `lastmod` 做变更检测，只重新抓取与烘焙发生变化的栏目；未变更的素材保留原有音频与文稿。
- **扩大导入范围**：把 10 个 transcript 形态栏目全部纳入（新增 `job-interviews`、`onboarding-calls`、`product-demos`、`tech-talks`、`technical-interviews` 五个场景），并按站点自身的分类体系补充场景映射。

**BREAKING**：`Clip.id` 格式变更（旧的 `{scene}_{column}_{block}` 失效）。迁移方式为一次性重烘焙，不保留旧 id。

### 不做的事（明确的非目标）

- 不做"从 quiz 题干抽取碎片对话"形态的内容（详见 design.md D5 的取舍分析）
- 不改 `EdgeTtsEngine`（其 400 故障属另一议题）
- 不做浏览器插件形态
- 不做打卡、学习时长统计、社交排名
- 不改现有场景枚举的 id（只增不减）

## Capabilities

### New Capabilities

- `listening-source-sync`: 内容来源的抽象契约与增量同步机制——来源注册与发现、每个来源的同步状态记录、基于源站变更标识的增量更新、失败诊断与重试；以及多来源下素材标识的唯一性保证

### Modified Capabilities

- `it-meeting-listening-tool`: 工具显示名改为「听力练习」；迷你播放窗提供关闭入口且关闭不终止播放；素材标识规则改为含来源前缀；素材库需展示来源归属
- `coderslingo-content-source`: 从"唯一来源"改为"CoderSlingo 这一个来源实现"；栏目发现与抓取需支持全量栏目枚举与基于 `sitemap.xml` 的变更检测；场景映射需覆盖全部 transcript 形态栏目

## Impact

**新增文件**

- `lib/tools/it_meeting_listening/services/listening_source.dart` — 来源抽象接口与注册表
- `lib/tools/it_meeting_listening/services/source_sync_state.dart` — 同步状态模型与持久化
- `lib/tools/it_meeting_listening/services/source_sync_service.dart` — 增量更新编排

**改动文件**

- `lib/tools/registry.dart` — 工具显示名
- `lib/tools/it_meeting_listening/models/listening_models.dart` — `ClipSource` 增 `sourceId`；`Clip.id` 规则；`MeetingScene` 增 5 个场景
- `lib/tools/it_meeting_listening/services/coderslingo_source.dart` — 实现 `ListeningSource`；全量栏目枚举；`sitemap.xml` 变更检测
- `lib/tools/it_meeting_listening/services/clip_baker.dart` — 接受来源抽象
- `lib/tools/it_meeting_listening/services/listening_host.dart` — 迷你窗关闭入口
- `lib/tools/it_meeting_listening/ui/it_meeting_listening_page.dart` — 显示名、来源分组、关闭按钮
- `lib/tools/it_meeting_listening/ui/it_listening_mini_player.dart` — 关闭按钮
- `lib/services/app_paths.dart` — 同步状态文件登记
- `lib/tools/vocab_book/ui/vocab_book_page.dart` — 来源显示适配新 `sourceId`

**数据迁移**

- 旧素材（33 条索引记录，其中 15 条已烘焙、18 条为 0 秒占位）**一次性重烘焙**，新 id 格式生效
- 术语本中 `sourceContext.tool` 仍为 `it-meeting-listening`（工具 id 不变），无需迁移

**外部依赖**

- 源站 `sitemap.xml`（2.4MB，14212 条目，全部带 `lastmod`）作为变更检测依据
- 无新增 pub 包
