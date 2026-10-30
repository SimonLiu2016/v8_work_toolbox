## 1. CharacterTurnaroundPrompt 提示词工程重构

- [x] 1.1 重构 `CharacterTurnaroundPrompt` 的视角与排版声明，切换为 16:9 4 区块专业角色资产图规范（左侧大胸像正面特写，右侧横向正面、侧面、背面三身立绘，正交平视 `orthographic`）。
- [x] 1.2 在 `CharacterTurnaroundPrompt` 正向提示词中注入 Agnes 适配的 PBR 物理材质与漫射光影锁（`soft diffused studio lighting`、`matte surface, low specular`、`natural skin pores`、`flyaway hairs`、`subsurface scattering`、`very subtle film grain`）并在正向尾部注入 `not a toy, not figurine`。
- [x] 1.3 升级 `cleanTurnaroundStyleTokens` 风格词清洗逻辑，剔除 `unreal engine 5`、`ue5`、`octane`、`cg渲染`、`3d渲染` 等诱发高光塑料感的引擎词汇，并自动转译补充 PBR 物理漫射光影。
- [x] 1.4 扩充 `turnaroundNegativePrompt` 防塑料违禁词库，收录 `plastic skin, waxy wax skin, oily sheen, strong specular highlight, doll, blind box toy, 塑胶人偶, 蜡像, 过度磨皮, airbrushed, 美颜滤镜, 光滑无瑕皮肤, CGI渲染, 3d玩偶, 统一光滑塑料涂层` 等违禁词。

## 2. 界面交互与弹窗流程优化

- [x] 2.1 修改 `series_page.dart` 中的 `_WorldviewTab._generateTurnaround`，彻底删除生成完成后的 `_cropFaceAnchorFromTurnaroundFile` 自动弹窗与重新截取询问对话框。
- [x] 2.2 保持三视图生成完成后的非阻塞轻量 SnackBar 通知，确保左侧大胸像特写直接作为角色 Face Asset 正常索引。
- [x] 2.3 验证角色卡更多操作菜单中的手动「截取面部特写锚点」入口，确保其依然可正常独立唤起与使用。

## 3. 测试验证与本地发布

- [x] 3.1 运行并更新 `prop_card_and_category_test.dart`、`character_identity_and_attire_decoupling_test.dart` 等单元测试，断言 4 区块排版、正交平视约束与 PBR 材质词正确生成。
- [x] 3.2 运行全局回归测试套件，确保所有现有功能与约束无回归破损。
- [x] 3.3 执行 `./scripts/deploy_local.sh` 重新构建并替换本地 `/Applications/V8WorkToolbox.app`，验证 AOT md5 一致性。
