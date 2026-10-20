## 1. 4K 超高清全景生成与清晰度提升

- [x] 1.1 在 `series_page.dart` 中将全景母图生图分辨率升级至 4K 档位（6272x2688），提供充沛原始像素
- [x] 1.2 在 `SphericalPerspectiveSlicer` 中优化双线性插值采样精度并增加反差增强，消除切片软糊

## 2. 偏航基准校准（Yaw Calibration）与数据持久化

- [x] 2.1 在 `SceneCard` 模型中添加 `panoramaYawOffset`（正面偏航基准角偏移量），支持序列化与反序列化
- [x] 2.2 改造 `SphericalPerspectiveSlicer.sliceBatchAsync`，引入 `yawOffset` 参数实现四向机位相对于主景的精准对齐切片

## 3. 交互式 3D 沉浸全景漫游视口（Panorama3dViewerDialog）

- [x] 3.1 创建 `Panorama3dViewerDialog` 组件，支持鼠标拖拽 360° 环视（Yaw / Pitch）与滚轮缩放视场角（FOV 50°~100°）
- [x] 3.2 在 3D 漫游视口中提供“设为正面基准”功能，一键持久化当前偏航角并支持触发重新对齐切片
- [x] 3.3 在 3D 漫游视口中提供“截取当前视角”功能，支持将任意独特角度导出为场景参考图
- [x] 3.4 在场景编辑弹窗中，点击全景缩略图直接呼出 `Panorama3dViewerDialog` 替换原静态图片弹窗

## 4. 验证与工程构建部署

- [x] 4.1 编写单元测试验证偏航角基准校准（Yaw Calibration）切片的对齐准确性与 4K 参数解析
- [x] 4.2 执行 `./scripts/deploy_local.sh` 编译并替换本机应用，验证 3D 交互漫游与 4K 切片清晰度
