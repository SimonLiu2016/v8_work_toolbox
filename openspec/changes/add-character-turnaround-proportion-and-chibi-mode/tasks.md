## 1. 数据模型与提示词装配

- [x] 1.1 在 `lib/tools/ai_video_studio/models/studio_models.dart` 中增加 `CharacterTurnaroundProportion` 枚举，定义 `standard`（标准全身 7~8 头身，默认）与 `chibi`（Q版萌系 2.5 头身）的中文名称、正向体态锚点与排他负向避雷词。
- [x] 1.2 升级 `lib/tools/ai_video_studio/services/prompt_assembler.dart` 中的 `CharacterTurnaroundPrompt.build` 和 `CharacterTurnaroundPrompt.buildNegative`，支持接收 `proportion` 参数，实现标准模式严禁 Q 版、Q 版模式严禁成人写实比例的互斥拼装。

## 2. 角色卡 UI 交互与双轨三视图闭环

- [x] 2.1 在 `lib/tools/ai_video_studio/ui/series_page.dart` 中，将角色卡「生成三视图」升级为下拉操作按钮（`PopupMenuButton`），直接提供「生成标准比例三视图（默认）」和「生成 Q版萌系三视图」两个选项。
- [x] 2.2 产物独立落盘与角标渲染：标准比例落盘为 `turnaround.png`，Q 版萌系落盘为 `turnaround_chibi.png`，参考图缩略图上分别显示主色「三视图」与粉色「Q版三视图」徽标，双轨共存互不覆盖。
- [x] 2.3 角色形态一键联动：在生成 Q 版三视图后，提供一键快捷操作将该三视图注册为角色卡专属的「Q版形态（CharacterVariation）」，便于分镜剧本无缝切换。
- [x] 2.4 资产库精准入库：更新「三视图入库」逻辑，根据当前三视图文件类型自动附带「标准比例」或「Q版萌系」标签。

## 3. 测试验证与本地部署

- [x] 3.1 编写单元测试，覆盖 `CharacterTurnaroundProportion` 预设、正向体态锚点组装、负向互斥排他、产物命名与形态绑定的正确性。
- [x] 3.2 运行 `flutter analyze lib/tools/ai_video_studio` 与 `flutter test test/tools/ai_video_studio/` 确保零错误零失败。
- [x] 3.3 按照工程规范执行 `./scripts/deploy_local.sh` 编译并热替换本机应用。

