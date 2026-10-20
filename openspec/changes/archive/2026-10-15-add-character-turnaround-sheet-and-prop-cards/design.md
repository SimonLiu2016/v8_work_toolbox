## Context

动机见 proposal.md — Why；行为契约见 specs/。此处只记影响实现方式的现状。

**模型与数据现状**：
- `StudioSeries` 有 `characters` / `commonScenes`，无 `props`。序列化走 `series_profile.json`（`StudioProjectManager._readSeries` / `_writeSeries`）。
- `CharacterCard` 有 `referenceImages`（文件名列表，从 `characterDir` 读）；`SceneCard` 同理。
- `StudioAsset` 有 `kind`（image/clip）/ `source` / `providerId` / `model` / `prompt` / `sourceCallId` / `originPath` / `sizeBytes` / `durationSec` / `note`，无 `category` / `tags`。索引单文件 `asset_index.json`。
- 图像生成走 `SystemAiImageAdapter`（`image_gen_adapter.dart`），经 `MediaCapabilityResolver` 查能力声明后发 `/v1/images/generations`。

**用户已实测确认**：Agnes `agnes-image-2.5-flash` 可用单次生成产出质量合格的角色三视图（正/侧/背同帧）。因此三视图路线为单次生成，不做 img2img 派生。

**约束**：
- 道具归属单剧，不做跨剧共享。
- 旧数据零迁移：`props` 缺失按空列表；`category`/`tags` 缺失按 `other`/空列表。

## Goals / Non-Goals

**Goals:**
- 道具成为 IP 主库的一等资产：可定义、可出图、可入资产库。
- 角色三视图单次生成、入角色目录、可作参考图。
- 资产库可按分类筛选、按关键词检索。

**Non-Goals:**
- 不在「新建剧集」处新增导入入口（沿用创意孵化的既有入口）。
- 不做场景 720° 全景图（图像模型无原生宽幅比例，需另探路线）。
- 不做道具跨剧共享。
- 不做标签体词表/自动打标——标签是用户手填的自由文本。

## Decisions

### 决策 1：`PropCard` 仿 `CharacterCard` 而不复用

道具与角色的差异足以独立建模：角色有 TTS 音色、形态版本、跨集记忆关联；道具只有描述、prompt、参考图、重要性。复用 `CharacterCard` 会带入一堆空字段，且 `variations` 对道具无意义。

`PropCard` 字段：`id` / `name` / `descriptionZh` / `promptEn` / `referenceImages` / `isKeyProp`（重要性）。

备选：给 `CharacterCard` 加 `kind` 字段区分角色/道具。否——UI 侧两套表单差异明显，共用一个类会让 series_page 里到处 `if (card.kind == prop)`。

### 决策 2：道具目录平铺在 series 下，不放 episode 下

`series_library/<series-id>/props/<prop-id>/`，与 `characters/`、`common_scenes/` 平级。道具是 IP 级资产（跨集复用），不是单集制作资产。

### 决策 3：三视图存单文件 `turnaround.png`，不拆三张

用户实测确认单帧三视角质量合格。拆三张会：① 失去同帧一致性；② 三次调用任一失败留残图；③ 参考图链路要判断"该传哪一张"。

单文件的代价：后续若要把单独视角裁出来用，需要裁剪。当前无此需求，留到有时再做。

备选：生成后按等分裁成三张单独存。否——裁剪位置靠猜（模型不保证三等分），裁错比不裁更糟。

### 决策 4：`category` 用枚举而非自由文本

分类集合固定六种（character/scene/prop/frame/clip/other），因为要按它做筛选器 UI；标签才用自由文本。若分类也可自由填写，筛选器就退化成一个搜索框，失去"一眼看到我有多少类资产"的价值。

枚举新增值需要改代码——这是刻意成本：分类是给 UI 用的结构化维度，不该由用户随意扩张。

### 决策 5：旧资产缺 `category` 回落 `other`，不写回

加载时回落，但不主动持久化。理由：① 零迁移；② 用户没碰过的旧资产不该被悄悄改写索引文件；③ 下次该资产被 `addAsset`/`setNote` 等操作触达时会自然带上新字段。

### 决策 6：检索在内存中进行，不建索引

资产量级几百条，`prompt`/`tags` 的 `contains` 足够。建倒排索引是过度设计；真到几千条时再考虑。

注意大小写：检索 SHALL 忽略大小写（`toLowerCase()` 两侧），否则搜 "Agnes" 搜不到 "agnes"。

## Risks / Trade-offs

- **[三视图单帧质量随模型退化]** → 生成失败不污染角色卡（spec 已要求）；用户可重试。Agnes 之外的其他图像模型未必支持三视角同帧，届时质量下降——但能力声明不拦这种事（图像模型没有"支持三视图"这个维度），接受。
- **[道具页签让 IP 主库从四项变五项，窄屏拥挤]** → 页签是 `TabBar`，超宽可滚动；若实测拥挤再改为下拉切换。不在本次预先优化。
- **[category 枚举不够用时要改代码]** → 接受，见决策 4。真不够用时 `other` 先兜着。
- **[检索大小写敏感导致搜不到]** → 决策 6 已定两侧 `toLowerCase()`，测试会覆盖。

## Migration Plan

无数据迁移。实施顺序：

1. 模型层：`PropCard`、`StudioSeries.props`、`StudioAsset.category` / `tags`（含序列化与旧数据回落）。
2. 数据层：`StudioProjectManager` 道具 CRUD 与目录。
3. 资产层：`AssetLibrary` 分类筛选与检索。
4. UI 层：道具页签、三视图入口、资产库筛选/检索。
5. 生图接线：道具生图与三视图生成的请求组装。

回滚：模型层改动向后兼容（缺字段回落），单独回滚任一层不会让旧数据不可读。

验证要点：旧 `series_profile.json`（无 props）与旧 `asset_index.json`（无 category/tags）加载不报错；道具 CRUD 后序列化可往返；资产检索大小写不敏感。
