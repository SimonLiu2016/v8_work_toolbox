# Proposal: 修复印象笔记空间笔记归属与导入去重

## Why

从印象笔记导入的笔记中，团队空间（ZENTEAMSPACE）里的笔记没有落在真实笔记本，而是全部涌入一个内部命名的"空间笔记本_34cfa..."杂烩（103 条，去重后 98 条）；同时多次导入产生了大量重复副本（全库 307 组同笔记本同名重复，本杂烩 4 份 × 98 条）。根因：导入脚本 `evernote_import.py` 未解析 `ZENTEAMSPACENOTE` 表，空间笔记的真实笔记本（`ZNOTEBOOK` 字段）与空间归属（`ZSPACEID`）信息丢失。

## What Changes

- **导入脚本解析空间归属**：`evernote_import.py` 新增 `ZENTEAMSPACENOTE` 表解析，空间笔记（`ZENNOTE.ZSPACENOTE` 非空且指向空间收容笔记本）按 `ZNOTEBOOK` 字段归到真实笔记本（含既有 stack），空间名（`ZENTEAMSPACE.ZNAME`）作为 stack 前缀并入（如 `专题分享 / 1-工程架构`）。
- **空间收容笔记本识别**：名称匹配 `空间笔记本_<uuid>` 模式的笔记本在导入时跳过，其下笔记按归属链分流；无法归属的笔记回退到 `默认笔记本`。
- **导入去重强化**：同名去重从"同笔记本下同名"扩展为"全局同标题 + 同笔记本"，并记录源笔记 GUID 防止重复导入。
- **修复模式**：导入脚本新增 `--repair` 模式——检测既有"空间笔记本"杂烩与重复副本，删除杂烩笔记本及其下全部重复笔记（保留每组最新 updated_at 一份），随后按新归属逻辑重新导入这批笔记。
- **一次数据修复**：在本机执行修复导入，消除 307 组重复与空间杂烩。

## Capabilities

### Modified Capabilities

- `evernote-import`: 空间笔记归属解析、空间收容笔记本识别、导入去重强化、修复模式。

## Impact

- 代码：`scripts/evernote_import.py`（ZENTEAMSPACENOTE 解析、repair 模式）、`lib/tools/notebook/evernote_import_service.dart`（透传 repair 参数与结果字段）
- 数据：本机执行一次修复导入；删除"空间笔记本_34cfa..."笔记本及重复副本
- 风险：修复模式删除笔记前需确认清单；GUID 映射表用于幂等，重复执行不产生副作用
