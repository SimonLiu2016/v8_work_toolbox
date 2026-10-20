## 1. 世界观标签与全局会话状态同步修复

- [x] 1.1 修复 `StudioSession.select`：当 `series?.id == next?.id` 时更新内存中的 `series = next` 并触发 `notifyListeners()`，保留激活的 `episode`；新增显式 `updateSeries(StudioSeries next)` 方法
- [x] 1.2 在 `SeriesPage` 中添加对 `widget.session` 的监听，确保 Tab 切换时从最新的 `series` 中读取 `eraGenre` 与其他世界观字段，杜绝切 Tab 丢失选中状态
- [x] 1.3 编写 `StudioSession` 与 `SeriesPage` 状态同步单元测试，验证就地更新与 Tab 切换数据保持一致

## 2. 小说解构场景纯净空间约束与多角度组图生成

- [x] 2.1 升级 `AiConstraintEngine._promptNovelMasterExtraction`，在 `scenes` 提炼硬约束中增加纯净空镜空间排他性要求，严禁包含具体人物、走动与情节动态
- [x] 2.2 在 `_SceneEditorSheetState._generateImage` 中自动注入正向纯空间词（`empty scene, no humans`）与负向人类排除锁（`human, people, person, crowd, man, woman, face, character`）
- [x] 2.3 在 `_SceneEditorSheet` 中增加「一键生成多角度场景包」功能（全景建立镜头、主视平视全景、侧逆视角、空间局部特写），自动生成多视角图片并追加至场景参考图库
- [x] 2.4 编写场景纯净约束与生图提示词组装单元测试，验证人物排除词与视角提示词组装正确

## 3. 视频模型多参考图上限提升与 Agnes Reference 模式打通

- [x] 3.1 在 `lib/services/media_capability.dart` 中，将 `MediaCapabilityDefaults.agnes` 与 `MediaCapabilityPresets.agnesVideo25` / `agnesVideo25Flash` 的 `maxReferenceImages` 调整为 `8`
- [x] 3.2 优化 `MediaCapabilityResolver.resolve` 与 `VideoGenAdapterFactory._wrap`，当本地配置声明的 `maxReferenceImages` 小于官方内置预设时，自动自愈升格为预设上限值（8 张），规避历史配置残留拦截
- [x] 3.3 在 `SegmentVideoGenTask` 中显式指定 `mode: AgnesVideoMode.reference`；在 `AgnesVideoAdapter` 中支持以 `reference` 模式打包 `images: [...]` 请求云端
- [x] 3.4 编写能力矩阵自愈解析与多参考图（4~8 张）大段规整测试，确保不再抛出 `MediaCapabilityException`

## 4. 全流程验证与本地应用部署

- [x] 4.1 运行相关模块单元测试（`flutter test`）确保全部断言通过且无回归问题
- [x] 4.2 运行 `openspec validate fix-studio-worldview-scene-purity-and-segment-references` 验证规划完备性
- [x] 4.3 按照工程核心执行规则，执行 `./scripts/deploy_local.sh` 重新构建并替换本地 `/Applications/V8WorkToolbox.app`
