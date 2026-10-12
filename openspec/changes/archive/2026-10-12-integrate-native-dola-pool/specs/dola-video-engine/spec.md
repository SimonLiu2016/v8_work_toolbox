## Purpose

提供基于纯 HTTP 逆向协议与本地 BDMS 签名常驻守护进程的 Dola 视频生成引擎，支持文生视频、图生视频与无水印成片交付。

## ADDED Requirements

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
