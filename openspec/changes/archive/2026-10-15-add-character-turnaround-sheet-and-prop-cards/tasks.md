## 1. 模型层：道具与资产分类

- [ ] 1.1 `studio_models.dart`：新增 `PropCard`（id / name / descriptionZh / promptEn / referenceImages / isKeyProp / updatedAt），含 `toJson` / `fromJson` / `copyWith`
- [ ] 1.2 同文件：`StudioSeries` 新增 `props` 字段（`List<PropCard>`，默认空列表），`toJson` 写入 `props` 键，`fromJson` 缺省按空列表
- [ ] 1.3 同文件：`StudioAsset` 新增 `category`（`AssetCategory` 枚举：character / scene / prop / frame / clip / other）与 `tags`（`List<String>`），序列化含两字段，`fromJson` 缺省回落 `other` 与空列表
- [ ] 1.4 同文件：`StudioAsset.copyWith` 支持改 `category` 与 `tags`（现有 copyWith 只支持 note）

## 2. 数据层：道具 CRUD 与目录

- [ ] 2.1 `studio_project_manager.dart`：新增 `propDir(seriesId, propId)`，目录 `series_library/<series-id>/props/<prop-id>/`，与 characters / common_scenes 平级
- [ ] 2.2 同文件：`readProps(seriesId)` / `readProp(seriesId, propId)` / `saveProp(seriesId, PropCard)` / `deleteProp(seriesId, propId)`，读写走与角色一致的 `series_profile.json` 原子写路径
- [ ] 2.3 同文件：`addPropReference(seriesId, propId, sourceFilePath)` —— 复制外部图片进道具目录并返回文件名，与 `addCharacterReference` 同构
- [ ] 2.4 同文件：新建剧集时 `props` 空列表正常落盘，不因缺字段报错

## 3. 资产层：分类筛选与检索

- [ ] 3.1 `asset_library.dart`：`assetsOf` 增加可选 `category` 参数，按分类过滤
- [ ] 3.2 同文件：新增 `search(String keyword)` —— 对 `prompt` 与 `tags` 做大小写不敏感的 `contains` 匹配，空关键词返回全部
- [ ] 3.3 同文件：`addAsset` 支持传入 `category` 与 `tags`，缺省 `other` 与空列表
- [ ] 3.4 同文件：新增 `setCategory` / `setTags`，供用户在资产库页调整

## 4. UI 层：道具页签与三视图入口

- [x] 4.1 `series_page.dart`：页签 labels 由四项扩为五项（角色卡 / 场景库 / 道具 / 世界观 / 集数与前情），新增道具页签内容
- [x] 4.2 同文件：道具页签含新建、编辑（名称/中文描述/英文 prompt/重要性）、删除、参考图上传与预览
- [x] 4.3 同文件：道具支持「生成图片」——按 prompt 或参考图走 `SystemAiImageAdapter`，结果存道具目录
- [x] 4.4 同文件：道具图片支持「收进资产库」——调 `AssetLibrary.addAsset` 并传 `category: AssetCategory.prop` 与本次生成来源调用 id
- [x] 4.5 同文件：角色卡新增「生成三视图」入口，生成结果存 `characters/<id>/turnaround.png`，卡片展示缩略图
- [x] 4.6 同文件：三视图生成失败时给出原因且不改动角色既有参考图，不写空文件
- [x] 4.7 `asset_library_page.dart`：新增分类筛选控件与关键词搜索框，接入 3.1 / 3.2

## 5. 生图接线：三视图请求组装

- [x] 5.1 三视图提示词模板：以角色 `descriptionZh` + `basePromptPositive` + 参考图为依据，组装含正/侧/背三视角要求的生成请求，单次生成
- [x] 5.2 生成走 `MediaCapabilityResolver` 解析当前图像模型能力，按能力规整尺寸与画幅（9:16 优先，模型不支持时按比例吸附）
- [x] 5.3 生成成功后将图片写入角色目录并更新角色卡（不污染既有 referenceImages）

## 6. 验证

- [x] 6.1 单元测试：`PropCard` 序列化往返；`StudioSeries` 无 `props` 字段的旧 JSON 加载不报错
- [x] 6.2 单元测试：道具 CRUD 后 `series_profile.json` 可正确读回；`addPropReference` 后文件在道具目录内
- [x] 6.3 单元测试：`StudioAsset` 无 `category` / `tags` 的旧 JSON 加载回落 `other` 与空列表
- [x] 6.4 单元测试：资产按分类筛选结果正确；`search` 大小写不敏感（搜 "agnes" 命中 "Agnes"）
- [ ] 6.5 实机：新建道具、生成图、收进资产库、在资产库按道具分类筛出
- [ ] 6.6 实机：为角色生成三视图，卡片显示缩略图，该三视图可作为分镜生成的参考图传入
- [x] 6.7 运行 `flutter test` 与 `flutter analyze`，确认无回归
- [ ] 6.8 部署：`scripts/deploy_local.sh`
