## 1. 物理裁剪与安全边界约束

- [x] 1.1 在 `KnowledgeGraphView._graphBody` 中使用 `ClipRect` 包裹 CustomPaint，建立视口物理硬边界
- [x] 1.2 优化 `_drawNodeLabel` 文字胶囊标签的水平定位与边距安全钳制（`clamp`），防止靠近左右边缘时越界或被切断
- [x] 1.3 适度微调 `_layoutFibonacciSphere` 球体分布自适应基准半径，优化 420px 视口下的星盘聚集度

## 2. 自动化测试与验证

- [x] 2.1 在 `test/notebook_3d_star_map_test.dart` 中增加文字胶囊边界钳制计算与安全距离测试用例
- [x] 2.2 运行全套相关测试验证无回归

## 3. 编译发布与部署验证

- [x] 3.1 编译打包 macOS Release 应用 (`flutter build macos --release`)
- [x] 3.2 覆盖替换部署至 `/Applications/V8WorkToolbox.app` 并重启验证


