## 1. 坐骑实体归属与高低落差隔离

- [x] 1.1 在 `PromptAssembler` 中实现实体级骑乘者判定算法（文本动作识别、结合垂直高低落差排除高层窗台角色）
- [x] 1.2 重构 `_buildMultiCharacterStaging`，仅为判定为真实骑乘者的实体附加坐骑指令，彻底消除三楼窗口骑黑驴等荒谬描述
- [x] 1.3 编写坐骑归属判定与多角色站位防污染的单元测试

## 2. 机位俯仰与视线朝向优先级修复

- [x] 2.1 重构 `PromptAssembler.compileGazeAndEyeline`，建立显式机位 > 显式视线 > 静态场景高度的分层仲裁机制
- [x] 2.2 修复地面仰拍镜头因场景带有 `elevation_level: balcony` 被强行反向编译为高角度向下俯拍的错误
- [x] 2.3 编写视角与视线分层仲裁测试，验证地面仰拍与高位俯拍在各类场景标签下的稳定性

## 3. 视频生成模式确定性与提示词克隆防护

- [x] 3.1 改造 `StudioShot.resolveEffectiveVideoMode`，显式指定的 `reference` 模式在生成本地关键帧后保持不变，不被强制篡改为 `keyframe`
- [x] 3.2 优化 `PromptAssembler.sanitizeForVideoMode`，在 `keyframe` 模式下收敛次要角色细节描述，防止视频大模型在首帧已有画面上额外绘制克隆人脸
- [x] 3.3 编写视频生成模式确定性与图生视频提示词克隆防护测试

## 4. 任务队列抽屉作用域隔离与批次追溯

- [x] 4.1 在 `QueueDrawer` 中传入并绑定当前 `seriesId` 与 `episodeId`，云端台账列表严格按当前集上下文隔离
- [x] 4.2 增强 `_CloudTaskTile` 布局，显式展示任务创建的准确时间戳（`yyyy-MM-dd HH:mm:ss`）与该分镜的动作摘要
- [x] 4.3 编写任务抽屉剧集作用域过滤与卡片摘要展示的 Widget 测试

## 5. 综合验证与本地打包部署

- [x] 5.1 运行所有相关单元测试与 Widget 测试确保无回归
- [x] 5.2 按照工程规范执行 `./scripts/deploy_local.sh` 编译 Release、保留 mihomo、重新签名并替换本机应用
- [x] 5.3 启动更新后的应用，实测验证分镜生成、坐骑绑定、视角正确性与队列隔离
