## Why

真实会议导入的解析器把「会议记录系统」写死成了**钉钉那一种导出形态**：必须落在 `## 转文字` 段内、说话人行必须以「发言人」开头、时间必须是 `HH:MM:SS`。实测语料里这不是主流——`communications/` 与 `tech/` 下 30 份逐字稿分属**五种形态**，只有 3 份能被导入，豆包导出件、真实姓名槽位、人写的归档件全部报"没有解析出任何轮次"。

用户的实际产出是多平台的（钉钉、豆包、华为云、Teams），格式差异是既定事实，不该由用户在导入前手工改稿。

## What Changes

- **说话人行改为结构化判定**：不再要求「发言人」这个词，改为「可选的标记前缀 + 槽位名 + 可选序号 + 时间戳，且整行无其他内容」。覆盖 `发言人 1 00:00:01`、`说话人 1 00:01`、`@说话人 1  01:54`、`李嘉成 00:00:03`。
- **取消「必须在 `## 转文字` 段内」的前置条件**：改为全篇扫描说话人行。二级标题只用于定位「关键词」段（可有可无）。
- **跳过非发言内容**：代码块（``` 围栏）、引用块（`>` 开头）、表格行一律跳过——这些位置放的是导出件元信息、关键词与人工译文，混进正文会让 TTS 中英混读。
- **总时长支持两种来源**：`> 转写时长:` 与豆包的 `录音时间：A - B`（取差值）。
- **新增导入前的解析预览与确认**：解析完成 → 展示「N 轮 / M 个说话人 / 时长 / 前若干轮样例 / 是否为加工件」→ 用户确认后才开始合成。格式放宽后误判的代价从"报错"变成"白等十几分钟"，预览是这道保险。
- **新增说话人槽位合并**：允许把多个槽位合并成同一个人（同一显示名、同一音色），处理同一人在文稿里出现多种写法的情况。不自动合并。
- **识别并标注归档加工件**：说明表格 + 内嵌原文 + 附录这类人写文档仍然可导入，但预览 SHALL 明确告诉用户"解析的是其中的原文段"。

**BREAKING**：无。已导入会议的 `meetingId` 由路径派生，不受解析规则影响；重新导入同一文件会走既有的"内容变化 → 重建"分支。

### 不做的事（明确的非目标）

- 不做无时间戳的逐字稿（`张三：内容` 形态）——本批语料里不存在，且没有时间戳就没有按轮定位
- 不做 OCR / PDF / 图片输入的逐字稿
- 不做跨文件的多场会议合并
- 不自动合并说话人槽位（只在用户明确选择时合并）
- 不改合成、词汇表、回答层的既有契约

## Capabilities

### New Capabilities

无。

### Modified Capabilities

- `real-meeting-transcript`: 逐字稿导入与解析从"单一导出形态"改为"多种形态的结构化识别"（说话人行判定、段落定位、跳过非发言内容、时长来源）；新增导入前预览与确认；新增说话人槽位合并

## Impact

**改动文件**

- `lib/tools/it_meeting_listening/services/transcript_parser.dart` — 说话人行判定、跳过块、时长来源、加工件识别
- `lib/tools/it_meeting_listening/services/real_meeting_service.dart` — 拆出「解析」与「落盘+合成」两步，供预览确认后提交
- `lib/tools/it_meeting_listening/services/speaker_profile_resolver.dart` — 合并映射的解析
- `lib/tools/it_meeting_listening/models/real_meeting_models.dart` — 槽位合并设定、解析预览模型
- `lib/tools/it_meeting_listening/ui/real_meeting_panel.dart` — 预览对话框入口与合并操作
- `lib/tools/it_meeting_listening/ui/it_meeting_listening_page.dart` — 导入流程改为「预览 → 确认 → 合成」

**归档顺序（重要）**

本 change 用 `MODIFIED` 修改 `real-meeting-transcript` 的两条需求，而该能力的主 spec 由 `add-real-meeting-import` 归档时创建。**必须先归档 `add-real-meeting-import`，再归档本 change**——否则 capability 会只落下被修改的那部分，其余需求丢失。
