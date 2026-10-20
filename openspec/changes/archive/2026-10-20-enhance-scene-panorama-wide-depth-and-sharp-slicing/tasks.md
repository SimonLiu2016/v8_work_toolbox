## 1. 全景母图生成提示词空间纵深强化

- [x] 1.1 在 `ScenePromptBuilder.buildPanoramaPrompt` 中注入机位后撤、挑高大殿与深远大景深约束词，彻底杜绝 AI 面壁贴脸生成
- [x] 1.2 净化可能引发狭隘室内感的描述，确保 360° 母图生成在开阔大空间的后方中央，留足物理回旋景深

## 2. 虚拟相机切片投影引擎升级（105° 电影超广角与边缘锐化）

- [x] 2.1 将 `BatchSliceRequest` 与相机参数默认视场角升级为 105.0°（垂直视野扩展至 73.5°），横向物理采样提升至 1830 像素
- [x] 2.2 在 `SphericalPerspectiveSlicer` 批量切片中引入 `pitchOffset` 俯仰偏置支持，兼顾大殿挑高构图
- [x] 2.3 在透视切片投影后处理中实现轻量级自适应边缘锐化滤波（Unsharp Masking），消除双线性插值高频衰减

## 3. 数据模型与 3D 漫游视口参数全链路联动

- [x] 3.1 在 `SceneCard` 模型中添加 `panoramaFov` 与 `panoramaPitchOffset` 字段及 JSON 序列化
- [x] 3.2 改造 `Panorama3dViewerDialog`，支持在“设为正面基准（重切）”时将当前视口的实时 Yaw、Pitch、FOV 参数完整回传
- [x] 3.3 在 `series_page.dart` 中接收视口参数并持久化至 `SceneCard`，联动调用 `sliceBatchAsync` 重新切片并刷新方位预览

## 4. 验证与工程构建部署

- [x] 4.1 编写单元测试验证大景深提示词规范、105° 视场角像素计算、锐化后处理与新增字段序列化
- [x] 4.2 执行 `./scripts/deploy_local.sh` 编译并替换本机应用，验证超广角完整画幅与清脆质感
