## 1. 显示名与迷你窗关闭（独立可验证的小改）

- [x] 1.1 把 `lib/tools/registry.dart` 中该工具的 `title` 改为「听力练习」；`id`、`lib/tools/it_meeting_listening/` 目录名、`AppPaths.itMeetingListeningDir` **一律不动**
- [x] 1.2 把页面标题与 `lib/tools/it_meeting_listening/ui/it_meeting_listening_page.dart` 里的文案同步为「听力练习」
- [x] 1.3 在迷你播放窗内加入关闭控件（×），点击后调用 `windowManager.hide()` 隐藏窗口，**不终止播放**
- [x] 1.4 确认关闭后可通过主窗口「迷你播放器」按钮与菜单栏「会议音频播放器」重新唤出，且回到关闭前的播放位置（`ListeningHost` 已有 `closeMiniWindow()` 的 hide 实现，需补上"已存在则前置而非新建"的分支）
- [x] 1.5 为迷你窗关闭与重新唤出补 widget 测试

## 2. 来源抽象层

- [x] 2.1 定义 `ListeningSource` 抽象接口（`id`、`displayName`、`license`、`discoverColumns()`、`fetchDialogues(column)`、`siteChangeToken()`），以及 `SourceColumn`（站点栏目 slug + 展示名 + 映射到的 `MeetingScene`）
- [x] 2.2 建立来源注册表，支持注册多个来源并按 id 查找
- [x] 2.3 把 `CoderSlingoSource` 改造为 `ListeningSource` 的实现：站点特有的 URL 拼接、HTML 解析、失败诊断全部封装在实现内部
- [x] 2.4 把「站点栏目 → `MeetingScene`」的映射表从 `CoderSlingoSource` 的静态常量移入实现内部，**场景枚举本身不随站点变**
- [x] 2.5 让 `ClipBaker`、素材库、播放控制器、界面改为依赖 `ListeningSource` 接口，不再直接引用 `CoderSlingoSource`
- [x] 2.6 补测试：用一个假来源实现验证"新增来源不触碰上层代码"（上层不引用任何具体来源类）

## 3. 多来源下的标识与归属

- [x] 3.1 `ClipSource` 增加 `sourceId` 字段（稳定标识，与展示名 `site` 并存），文稿清单与术语收藏条目一并记录
- [x] 3.2 `Clip.id` 规则改为 `{sourceId}_{sceneId}_{columnSlug}_{block}`；音频与文稿文件名同步采用该 id
- [x] 3.3 迁移旧素材：清空素材目录与索引，按新规则重烘焙（顺带清掉 18 条 0 秒占位记录）
- [x] 3.4 术语本回跳：`vocab_book_page.dart` 解析 `sourceContext` 时兼容缺少 `sourceId` 的旧条目（缺省为 `coderslingo`）
- [x] 3.5 素材浏览界面支持按来源分组；场景筛选行为不受分组影响
- [x] 3.6 补测试：两个来源存在同名场景时，素材 id 不冲突

## 4. 同步状态与增量更新

- [x] 4.1 定义 `SourceSyncState` 模型：`{sourceId, columnSlug, lastSyncedAt, siteChangeToken, contentHash, lastFailure, failureCount}`
- [x] 4.2 同步状态独立持久化到 `AppPaths` 登记的新文件（与素材目录分开），并保证原子写
- [x] 4.3 实现站点级变更检测：拉取源站 `sitemap.xml`，取该站点的变更标识（全站 `lastmod` 的最大值或构建标识），与上次记录比对
- [x] 4.4 实现内容级变更检测：解析后的对话内容哈希（轮次文本 + 说话人 + 角色），与上次记录比对
- [x] 4.5 实现更新编排：站点级未变 → 全部跳过；站点级变更 → 重抓栏目并算内容哈希；内容哈希未变 → 跳过烘焙保留旧产物；变了 → 重烘
- [x] 4.6 更新过程逐栏目隔离，单栏目失败不影响其它栏目
- [x] 4.7 呈现更新结果：每个栏目的「未变更已跳过 / 已更新 / 失败」与失败原因
- [x] 4.8 对不支持增量更新的来源（全量退化）显式标注
- [x] 4.9 补测试：站点级未变时不产生任何抓取调用；内容未变时不产生 TTS 调用；单栏目失败不影响其它栏目

## 5. 扩大导入范围

- [x] 5.1 `MeetingScene` 新增 5 个场景：`jobInterview`（面试）、`onboarding`（新人入职）、`productDemo`（产品演示）、`techTalk`（技术演讲）、`technicalInterview`（技术面试）；既有 id 不变
- [x] 5.2 把 CoderSlingo 映射表扩到全部 10 个 transcript 形态栏目（新增 `job-interviews`、`onboarding-calls`、`product-demos`、`tech-talks`、`technical-interviews`）
- [x] 5.3 抓取每个栏目的**全部**对话块（实测共 34 块），不再只取前 4 块
- [x] 5.4 为新场景补角色→音色映射（`Interviewer`/`Candidate`/`Sales Engineer`/`Speaker` 等新角色）
- [x] 5.5 一次性全量烘焙 34 块素材（约 34 轮 TTS/条），更新索引
- [x] 5.6 补测试：新增 5 个场景的对话能被正确解析出说话人轮次

## 6. 验收

- [ ] 6.1 界面显示名已改为「听力练习」，且既有术语收藏的回跳仍然有效（由 `redesign-listening-practice-layout` 任务 12.10 验收覆盖）
- [ ] 6.2 迷你窗可关闭、可重新唤出；关闭期间播放不中断（由 `redesign-listening-practice-layout` 任务 12.6 验收覆盖）
- [x] 6.3 素材库覆盖 10 个场景、34 条素材，来源归属可分辨
- [ ] 6.4 连续两次「更新素材」：第二次不产生任何 TTS 调用（由 `redesign-listening-practice-layout` 任务 12.10 验收覆盖）
- [ ] 6.5 断网时触发更新，报具体失败原因，既有素材仍可播放（由 `redesign-listening-practice-layout` 任务 12.10 验收覆盖）
- [x] 6.6 全量测试回归（注意仓库既有环境依赖型失败：`evernote_import_test` / `disk_slimmer_hardening_verify_test` / notebook 编辑器与表格类测试；既有基线另有 8 个文件的既有失败与本 change 无关）
