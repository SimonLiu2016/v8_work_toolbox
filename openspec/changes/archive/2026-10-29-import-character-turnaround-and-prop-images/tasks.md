## 1. 角色三视图外部导入能力

- [x] 1.1 在 `series_page.dart` 中实现 `_importTurnaround({CharacterVariation? variation})` 方法，支持本地文件选取与全局资产库选取
- [x] 1.2 在基准角色操作栏中集成「导入三视图」菜单按钮（支持从本地导入与从资产库选择）
- [x] 1.3 导入基准三视图后检测面相锚点，未配置时自动呼出 `_cropFaceAnchorFromTurnaroundFile` 打开 `FaceCropDialog` 引导截取
- [x] 1.4 在角色形态卡片（`_VariationEditor`）中集成「导入形态三视图」按钮并绑定持久化更新

## 2. 道具图片列表直达外部导入

- [x] 2.1 在 `_PropListView` 列表项左侧缩略图区域增加点击导入入口，右侧操作栏增加「导入图片」快捷菜单按钮
- [x] 2.2 实现 `_importPropImage(PropCard prop)` 方法，支持本地文件选择与资产库选取，并将新图插入 `referenceImages` 首位保存
- [x] 2.3 在 `_PropEditorSheet` 中优化道具图片管理文案，突出首张为主图/封面展示，并支持追加导入与删除

## 3. 自动化测试与部署验证

- [x] 3.1 编写或更新单元与组件测试，验证三视图外部导入落盘与道具首选主图排序逻辑
- [x] 3.2 运行相关自动化测试套件确保无回归
- [x] 3.3 遵循工程级规范执行 `./scripts/deploy_local.sh` 完成 Release 构建、签名与本机部署验证
