## Context

`studio_shell.dart` 的 `_buildStage` 用 `switch` 直接返回新 Widget，每次切换导航都会 dispose 旧 Widget。`IdeaIncubatorPanel` 有局部状态 `_activeImportId`（记录本面板发起的导入任务 ID）；Widget dispose 后该状态归零，切回来时进度卡片消失——尽管 `NovelImportTaskService` 单例中任务仍在运行（顶栏徽标仍显示），面板内进度卡片无法绑定回任务。

IP 主库三个子库图片能力不对称：场景库无 AI 生成图入口；角色卡参考图列表与三视图无点击全屏预览；道具库缩略图无点击全屏；三处均缺少单张删除。

此外，短视频工坊现有制作类型（`drama`、`anime`、`narration`）缺乏系统性的风格提示词与负向词闭环，仅仅是个分类标签；新增的 `anime3d`（3D国漫）以及现有其他类型都需要深度的风格锁与反向抑制机制，否则 AI 生成的图片与视频无法呈现预期质感。

## Goals / Non-Goals

**Goals**
- 通过 `IndexedStack` 保活所有 stage Widget，并让面板在切回时自动嗅探当前剧集的活动导入任务，彻底修复切标签状态丢失
- 三个子库图片能力拉齐：场景库 AI 生成图、三处全屏预览、单张删除、三视图明晰展示
- 新增 `anime3d` 制作类型枚举与 UI 支持
- **四大制作类型全矩阵风格闭环**：为 `drama`、`anime`、`narration`、`anime3d` 全部配置正向风格锁、专属负向抑制词与动态镜头偏向，贯穿小说提取、IP资产生成、分镜关键帧生图与视频生成
- 修正顶栏「本地免费演示模式」误导文案并修复设置窗口布局溢出

**Non-Goals**
- 分镜看板参考图自动关联 IP 库（属于独立变更）
- Agnes 视频适配器多参考图模式实现（属于独立变更）

## Decisions

### D1：IndexedStack 保活 + 任务主动恢复

`IndexedStack` 将所有 stage Widget 保活。同时在 `IdeaIncubatorPanel` 的 `initState` 与 `build` 中增加保底逻辑：若 `_activeImportId == null`，主动查询 `NovelImportTaskService.instance.taskForSeries(series.id)`，若存在进行中或最新任务则自动接管。双重保证切页签、关窗重开都能看到进度。

### D2：制作类型风格全矩阵设计 (Style Matrix)

在 `StudioProductionType` 枚举及 `PromptAssembler` 中落地四大类型的风格矩阵：
1. **`anime3d`** (3D国漫)：
   - 正向：`3D CGI animation, modern Chinese fantasy donghua, exquisite 3D render, Unreal Engine 5 render, Octane render, subsurface scattering skin, delicate hair strands, glowing elemental VFX, cinematic lighting`
   - 负向：`2D, flat anime, cartoon, sketch, live-action photo, plastic clay, low-poly, stiff puppet, glossy plastic skin`
2. **`drama`** (真人短剧)：
   - 正向：`cinematic film still, photorealistic 8k, live-action cinematography, natural skin texture, realistic micro-expressions, 35mm lens`
   - 负向：`anime, cartoon, 3D render, CGI, doll, plastic skin, illustration, painting, drawing, unreal engine`
3. **`anime`** (二次元/动态漫)：
   - 正向：`high quality anime aesthetic, Japanese anime art style, crisp cel-shaded lines, vibrant anime coloring, Makoto Shinkai lighting, Ufotable visual flair`
   - 负向：`photorealistic, live-action, 3D CGI, realism, real human photo`
4. **`narration`** (图文解说)：
   - 正向：`high-end documentary illustration, editorial conceptual art, atmospheric digital painting, storybook realism, textured brushwork, elegant lighting`
   - 负向：`messy, anime, cartoonish, low-brow, chaotic composition`

新建剧集时，自动将对应类型的默认风格词写入 `series.styleTokens`。在 `PromptAssembler` 中拼接分镜与片段生图时，自动应用对应类型的负向词与画质基线。

### D3：全屏预览与图片管理

使用 Flutter 官方原生的 `InteractiveViewer` 支持手势缩放，提供单张删除二次确认，删除时同时处理文件系统及卡片元数据（`referenceImages`）。

### D4：三视图专属标签

参考图展示若遇到 `turnaround.png`，渲染为「三视图」高亮 Chip，让用户一目了然。

## Risks / Trade-offs

- 强风格词可能导致模型轻微过拟合 → 负向词精准剔除互斥风格（如真人绝对剔除动漫，3D绝对剔除2D与真人），正向词聚焦材质与光影，给予内容本身（角色面部、动作）足够的语义空间。
- `IndexedStack` 会常驻内存 → 短视频工坊 7 个 Stage 主要是配置面板与列表，不持有超大媒体纹理缓存，占用通常在几十 MB 级，对桌面平台极其安全。

## Migration Plan

1. 更新模型：`studio_models.dart` 新增 `anime3d` 及各类默认风格字段
2. 更新提示词系统：`prompt_assembler.dart` 接入全矩阵风格与负向约束
3. 更新 Shell 与导航：`studio_shell.dart` 采用 `IndexedStack`
4. 更新 IP 主库：`series_page.dart` 补充大图预览、删除、场景 AI 生图与三视图管理
5. 更新 UI 修复：顶栏文案更正、配置窗口溢出修复
6. 验证：编译、单元测试与 local 部署
