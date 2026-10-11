## 1. 数据模型与景别枚举增强

- [x] 1.1 在 `StudioShotSize` 枚举中增加 `full('full', '全景')`，更新 `fromId` 兼容解析与展示映射
- [x] 1.2 更新 `StudioShot` 校验逻辑，将单镜时长建议区间规范至 3.0~5.0 秒，并支持台词预估秒数解析

## 2. 中转站 Agnes 视觉模型适配器实现

- [x] 2.1 增强 `SystemAiImageAdapter`：针对 `agnes-image-2.5-flash` 输出 `size: "2K"`、`ratio: "9:16"`、`extra_body.response_format: "url"`，并在存在角色定妆照时注入 `extra_body.image`
- [x] 2.2 实现 `AgnesVideoAdapter`（实现 `VideoGenAdapter` 与 `CancellableVideoGenAdapter`），按 OpenAI Videos 标准向中转站 `POST /v1/videos` 提交 720P 9:16 5秒视频生成任务
- [x] 2.3 实现 Agnes 视频异步状态轮询逻辑（支持 `/agnesapi?video_id=...` 与 `/v1/videos/{id}` 自动回退），任务完成后下载 MP4 成片并持久化
- [x] 2.4 在 `VideoGenAdapterFactory` 中优先路由配置了 Agnes 视频模型的全局系统槽位

## 3. AI 约束引擎升级（分镜规范与小说解析）

- [x] 3.1 升级 `AiConstraintEngine.scriptBreakdown` 的 System Prompt 与 Schema 校验：严格限定 3~5 秒时长、五大景别（含全景）、30~50 字具象微动作画面描述、含预估秒数与情绪语气的台词
- [x] 3.2 在 `AiConstraintEngine` 中实现长篇小说两阶段解构管线：Pass 1 提取世界观设定、角色卡库（含中英文 Prompt）、场景库；Pass 2 基于剧情高潮点检测自动推荐分集并生成 synopsis、summary 与 hook


## 4. 创意孵化：小说导入与 IP 主库自动入库

- [x] 4.1 在 `IdeaIncubatorPanel` 中增加本地小说文本文件（`.txt` / `.md`）导入交互与异步解构进度指示
- [x] 4.2 在 `StudioProjectManager` 中串联自动入库逻辑：原子化写入 `series_profile.json`、`characters/`、`common_scenes/` 与 `episodes/` 剧集大纲

## 5. 分镜看板：双模式逐步拆解与 UI 呈现

- [x] 5.1 在 `StoryboardBoard` 景别下拉菜单与编辑抽屉中完整支持“远景 / 全景 / 中景 / 近景 / 特写”
- [x] 5.2 在 `StoryboardBoard` 中实现“单集即时拆解”功能，支持将单集大纲与前情链一键转化为结构化分镜
- [x] 5.3 在 `StoryboardBoard` 中实现“全剧一键批量流水线拆解”控制器，带有进度指示与串行剧情记忆无缝注入

## 6. 自动化测试与工程级部署验证

- [x] 6.2 遵循工程级规范执行 `./scripts/deploy_local.sh` 重新构建并替换本机应用，确保最新二进制生效


