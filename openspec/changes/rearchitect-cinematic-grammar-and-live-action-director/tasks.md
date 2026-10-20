## 1. AI 导演级视听语法与 Prompt 引擎重构

- [x] 1.1 在 `ai_constraint_engine.dart` 的小说改编与剧本拆解 Prompt 中注入完整的影视导演视听规范导则（涵盖景别体系、机位俯仰视角、运镜动态、站位构图与视线正反打）。
- [x] 1.2 在 Prompt 导则中明确空间高低物理交互（如楼上向下抛物与地面迎击动作）的视听推理规则，指导 AI 生成俯拍与仰角视点。
- [x] 1.3 升级剧本节拍与拆解的 JSON Schema，强制规范 `shot_size`、`camera_staging`、`camera_move`、`screen_position`、`gaze_direction` 与 `voice_type` 字段输出。

## 2. 分镜转换管道无损透传（Pass-through Pipeline）

- [x] 2.1 彻底清理 `convertScenesToShots` 中写死的 `cameraMove: 'static'`、`cameraStaging: '平视定机位'`、`screenPosition: '主体居中'`、`gazeDirection: '平视正前'` 降级覆写。
- [x] 2.2 完整提取并透传 AI 剧本节拍推导出的机位视角、运镜轨迹、构图站位与视线方向到生成的 `StudioShot` 中。
- [x] 2.3 规范 `voice_type` 识别流：若为 `inner_voice`，分镜台词统一格式化为 `角色（内心 OS）：内容`，并保留 `voiceType` 属性。

## 3. 内心独白（OS）声画物理隔离与提示词装配

- [x] 3.1 在 `prompt_assembler.dart` 的生图提示词装配中，对 `inner_voice` 或包含 `（内心 OS）` 的分镜注入闭口微表情与心理沉思描述，杜绝张嘴描述。
- [x] 3.2 在生视频提示词装配中，对内心独白分镜强制注入闭口微表情与禁开口指令（`画面主体保持自然闭口与从容微表情，严禁开口嘴型与画内文字`）。

## 4. 真人实拍世界观风格预设与制作形态解禁

- [x] 4.1 在 `studio_preset_store.dart` 中新增【真人古装·仙侠影视大片】（`costume_drama_realism`）与【真人爆款·实拍短剧】（`live_action_short_drama`）两款预设。
- [x] 4.2 在 `series_page.dart` 的世界观设置面板中增加“制作形态（实拍/3D/2D）”切换选择器，并支持持久化保存。
- [x] 4.3 在 `prompt_assembler.dart` 中增加负向词安全守卫：当制作形态为 `live_action` 或当前风格为实拍电影质感时，过滤清除 `live-action photo` 等真实感负向词。

## 5. 校验与工程部署

- [x] 5.1 运行单元测试验证剧本拆解视听参数解析、分镜转换透传与提示词组装逻辑。
- [x] 5.2 按照工程规范执行 `./scripts/deploy_local.sh` 完成 Release 构建、重签名与本地应用替换部署。
