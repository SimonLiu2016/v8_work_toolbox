## 1. 存储

- [x] 1.1 `ListeningProgressStore` 升级为 v2 结构（items / scenes / lastPlayed，item 含 offsetMs、durationMs、updatedAt、可选 completedAt），原子写入
- [x] 1.2 v1 → v2 读取迁移（scenes 与 items 转换、lastPlayed 取最新）；损坏文件按空表处理
- [x] 1.3 存储单测：读写往返、v1 迁移、损坏文件容错、并发写串行化

## 2. 记录器

- [x] 2.1 新建 `ResumeRecorder`：内存表 + 串行防抖落盘，提供 `offsetFor` / `sceneLastClip` / `lastPlayed` / `progressFor`
- [x] 2.2 已听完判定（剩余 < 5 秒或 ≥ 98%）：offset 置 0 并写 completedAt；重新播放后清除
- [x] 2.3 记录器单测：周期节流、事件立即落盘、已听完判定、偏移超出新时长时归零

## 3. 接入播放层

- [x] 3.1 `ListeningPlayerController` 注入 `ResumeRecorder`：播放中每 5 秒记录；pause / stop / seek / 切换 clip 前立即记录；完成时记为已听完
- [x] 3.2 `play(clip)` 未指定位置时载入后 seek 到记录偏移；场景连续播放从 `sceneLastClip` 继续
- [x] 3.3 `ListeningHost`：迷你窗关闭与应用退出/窗口关闭时立即落盘；确认迷你窗命令与热键路径都经过 controller 被记录
- [x] 3.4 删除页面中 `_progressStore.save(clip.scene.id, clip.id, 0)`，启动时用 `lastPlayed` 选中场景与片段并以暂停态载入到记录位置

## 4. 测试与验收

- [x] 4.1 controller 级测试：热键路径暂停后记录正确；切换内容时旧内容位置被保存；多场排练进度互不覆盖
- [x] 4.2 全量测试回归（排除仓库既有的环境依赖型失败）
- [x] 4.3 执行 `./scripts/deploy_local.sh` 构建并替换本机应用
- [ ] 4.4 实机：真实会议听到中途暂停 → 退出 → 重开 → 从该位置继续
- [ ] 4.5 实机：播放中强制结束应用 → 重开 → 位置误差不超过约 5 秒
- [ ] 4.6 实机：只用热键/迷你窗控制播放与暂停，重开后位置正确
- [ ] 4.7 实机：片段播到结尾 → 再次播放从头开始
