# dola-video-engine Specification

## Purpose
提供基于纯 HTTP 逆向协议与本地 BDMS 签名常驻守护进程的 Dola 视频生成引擎，支持文生视频、图生视频与无水印成片交付。
## Requirements
### Requirement: Embedded URL Signer Daemon
系统 SHALL 在本地以低开销子进程方式托管轻量 BDMS URL 签名守护脚本，通过标准输入输出提供非阻塞的异步 URL 签名计算。

#### Scenario: Generate signed request URL
- **WHEN** 视频生成引擎需要向上游 Dola 提交对话或查询任务
- **THEN** 系统向本地签名守护进程发送签名请求，在 500 毫秒内获得附加合规签名的最终目标 URL

### Requirement: Standard VideoGenAdapter Contract Compliance
系统 SHALL 将 Dola 号池包装为标准 `VideoGenAdapter` 接口，提供统一的异步任务轮询、取消支持和进度报告。

#### Scenario: Generate video with keyframe and prompt
- **WHEN** AI 视频工坊向适配器传入首帧图片、分镜提示词与生成时长（如 10 秒）
- **THEN** 适配器自动调度可用账号提交请求，以 3~5 秒周期轮询上游状态，并在成功后下载成片至指定目标路径并返回 File 对象

#### Scenario: Task cancellation during polling
- **WHEN** 用户在工坊队列中主动取消正在轮询的 Dola 视频任务
- **THEN** 适配器立刻中断轮询循环，释放当前任务占用的账号资源并向调用方抛出取消异常

### Requirement: Watermark Removal and Segment Stitching
系统 SHALL 自动解析无水印视频下载流，并在请求 30 秒片段时协调两段 15 秒子片段并利用本地 FFmpeg 自动拼接成单条视频。

#### Scenario: Thirty seconds video assembly
- **WHEN** 上游对 30 秒请求仅返回两段独立视频流或短视频切片
- **THEN** 引擎自动下载分段视频并调用本机内置 FFmpeg 完成无缝画面拼合，交付完整的 30 秒视频成片

### Requirement: Studio Engine Selection Persistence
系统 SHALL 持久化存储用户在工坊设置对话框中选择的图像生成与视频生成引擎偏好。

#### Scenario: Reopening studio settings dialog
- **WHEN** 用户在工坊设置中将视频引擎从跟随系统切换为 Dola 免费号池并关闭弹窗
- **THEN** 再次打开该设置弹窗或重新进入分镜看板时，选中的引擎依然为 Dola 免费号池

### Requirement: Storyboard Keyframe Prerequisite Validation
系统 SHALL 在分镜看板触发视频生成前校验是否已存在关键帧首图，无首图时弹出友好提示而非静默崩溃。

#### Scenario: Click video on shot without keyframe
- **WHEN** 用户在尚未生成关键帧的分镜卡片上点击「视频」按钮
- **THEN** 系统阻止任务排队并弹出指引提示“请先点击关键帧生成首帧画面”

### Requirement: Selectable and Copyable Error Dialog
系统 SHALL 以可选中文字、自动限制最大高度、并提供一键复制按钮的方式展示失败任务的详细报错。

#### Scenario: Viewing task error details
- **WHEN** 视频任务失败并展示错误信息
- **THEN** 错误文本支持完整滚动、选中文本与一键复制全部报错日志，不发生溢出异常

