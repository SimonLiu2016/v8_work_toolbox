## Why

听力练习工具当前只能播放"别人的会议"（CoderSlingo 导入的素材），用户真正要听的会是**自己 upcoming 的周会/临时会议**。用户会导入会议材料（MD/HTML），需要软件分析这些材料，生成两类可用于预听的内容：一份 Simon 主讲的英文汇报人文稿 + 对应语音，以及一场 3-5 个固定角色（Simon、xiaofeng、songyang、deepan、Josh）、时长 30 分钟到一个小时的模拟会议对话 + 对应语音。

这与既有能力的差异是**双向的**：既有素材是"听别人的短会"（1-3 分钟、随机说话人、内容来自站点），新需求是"演练自己的长会"（30-60 分钟、固定人物关系、内容来自用户材料）。两者只共享播放器外壳与烘焙管线的后半段。

## What Changes

- **新增材料导入**：支持导入 MD 与 HTML 文件（复用既有 `DocumentParser._parseMarkdown` 与 `htmlToMarkdown`），解析为结构化文本供后续分析。
- **新增汇报人文稿生成**：基于材料生成 Simon 第一人称的英文讲稿，按议题分节，产出文稿文本。
- **新增汇报人语音合成**：讲稿按节合成语音，Simon 使用固定音色；文稿与语音小节一一对应。
- **新增模拟会议剧本生成**：基于材料与讲稿，由 LLM 生成 5 角色会议剧本（Simon 主讲，xiaofeng/deepan/Josh 为客户方，songyang 为 Huawei 合作方），含开场、议题推进、Q&A、收尾四段结构，时长目标 30-60 分钟。
- **新增会议语音合成**：剧本逐轮按角色音色合成，按**会议回合**（turn）切分为一一对应的音频小节，落盘为连续可播放的整场会议。
- **新增排练播放**：会议音频进入既有播放体系（悬浮窗、热键、断点、变速），支持按回合定位与精听。
- **新增固定角色音色表**：5 个角色各绑定一个固定音色（全部为男声音色），跨材料一致。

**BREAKING** 无。

### 不做的事（明确的非目标）

- 不做 PDF/Word 导入（材料格式约定为 MD/HTML；其它格式走既有「文档语音朗读」工具）
- 不做实时流式合成（预生成 + 缓存，播放在本地）
- 不做影子跟读打分、录音对比
- 不做会议内容的云端同步或分享（纯本地）
- 不改 `EdgeTtsEngine`（其 400 故障属另一议题）
- 不改既有素材库（CoderSlingo 导入）的导入链路与数据结构

## Capabilities

### New Capabilities

- `meeting-material-rehearsal`: 会议材料排练的完整契约——材料导入与解析、汇报人文稿生成、模拟会议剧本生成（固定 5 角色 + 会议结构）、逐回合语音合成与落盘、固定角色音色表、排练播放与定位

### Modified Capabilities

- `it-meeting-listening-tool`: 播放体系需支持"排练会议"这一类素材（30-60 分钟、按回合定位）；素材列表需能区分「导入的听力素材」与「排练会议」

## Impact

**新增文件**

- `lib/tools/it_meeting_listening/models/rehearsal_models.dart` — 材料、讲稿、剧本、排练会议的数据模型
- `lib/tools/it_meeting_listening/services/material_importer.dart` — MD/HTML 导入与解析
- `lib/tools/it_meeting_listening/services/speech_draft_generator.dart` — 汇报人文稿生成（text 槽位）
- `lib/tools/it_meeting_listening/services/meeting_script_generator.dart` — 模拟会议剧本生成（text 槽位）
- `lib/tools/it_meeting_listening/services/rehearsal_baker.dart` — 剧本逐回合合成与整场落盘
- `lib/tools/it_meeting_listening/services/rehearsal_voices.dart` — 固定角色音色表
- `lib/tools/it_meeting_listening/ui/material_import_panel.dart` — 材料导入与生成入口
- `lib/tools/it_meeting_listening/ui/rehearsal_panel.dart` — 排练会议列表与精听

**改动文件**

- `lib/tools/it_meeting_listening/models/listening_models.dart` — 素材来源类型扩展（区分导入素材 / 排练会议）
- `lib/tools/it_meeting_listening/ui/it_meeting_listening_page.dart` — 新增排练入口与列表
- `lib/tools/it_meeting_listening/services/listening_player_controller.dart` — 支持按回合定位
- `lib/services/app_paths.dart` — 排练会议目录与材料缓存目录登记

**复用既有能力**

- `DocumentParser._parseMarkdown`（MD 解析）、`htmlToMarkdown`（HTML 转 MD）
- `ClipBaker` 的逐轮合成 + 重试 + 内容审查降级 + 配额 fast-fail（新写 `RehearsalBaker` 时复用同套逻辑）
- `OpenAiTtsEngine`（经应用 `tts` 槽位）
- 既有播放器外壳（悬浮窗 / 热键 / 断点 / 变速）

**外部依赖**

- 应用「AI 能力配置」的 `text` 槽位（生成讲稿与剧本）与 `tts` 槽位（合成语音）
- 无新增 pub 包

**规模实测依据**（2026-10-22，30 分钟会议 ≈ 140 轮）：

```
轮次        140          280
烘焙耗时    6 分钟       11 分钟
音频大小    1.9 MB       3.8 MB
TTS 请求    140 次       280 次
```

合成按**回合**切分（每轮一个音频小节），与文本一一对应；整场为一条连续音频。
