## Why

AI 视频生成的商用模型（如 Kling、Runway）API 调用成本高昂。而第三方平台（如字节跳动国际版 Dola / 豆包）提供每日免费生成额度（Seedance 2.0 / 2.5 视频模型）。通过在 V8WorkToolbox 中原生内置 Dola 账号池管理与智能请求调度，用户可以配置多个免费账号，桌面端各工具（如 AI 视频工坊）及上层服务即可透明、无感地并发调用高品质视频生成能力，大幅降低视频制作成本并提升出片吞吐量。

## What Changes

- **内置 BDMS URL 签名守护引擎**：复用轻量零外部依赖的 `bdms-sdk.js` 与 `bdms_sign_url.js`，通过宿主管理的 Node.js 标准子进程提供高速、低开销的请求签名服务，免去启动完整 Chromium 浏览器的资源开销与风控风险。
- **原生多账号状态机与调度中心**：
  - 维护 `满额`（4点）、`半额`（2点）、`冷却`（0~1点）、`生成中`、`风控/异常` 等账号生命周期状态。
  - 按东京时间 0 点（北京时间 23:00）自动重置额度，并根据上游回执实时校正账号余额。
  - 支持单账号与内置代理（Mihomo/出海代理）自动绑定，防关联风控。
- **Dola 原生视频生成适配器 (`DolaPoolVideoAdapter`)**：
  - 实现 `VideoGenAdapter` 与 `CancellableVideoGenAdapter` 接口，无缝接入 `VideoGenAdapterFactory`。
  - 支持 `seedance-2.0`（5/10/15s）与 `seedance-2.5`（5/10/30s）模型及多参考图生视频。
  - 支持 30 秒片段原生生成或利用内置 `FfmpegComposer` 进行两段 15 秒拼合与无水印提取。
- **账号池管理与监控界面**：
  - 在「系统设置 -> AI 基础设施」或专用工具抽屉中提供 Dola 账号管理面板。
  - 支持多行 Cookie 批量导入、导出、一键可用性探测与额度刷新。

## Capabilities

### New Capabilities
- `dola-account-pool`: 负责 Dola 免费账号的凭据安全存储、状态机生命周期流转、出海代理绑定与多账号并发负载均衡。
- `dola-video-engine`: 负责集成 BDMS 签名子进程通信、Dola 纯 HTTP 协议对接、任务轮询、无水印解析与成片转存，作为标准 `VideoGenAdapter` 暴露给视频工坊。

### Modified Capabilities
- `ai-configuration`: 扩展 AI 基础设施与供应商配置，支持检测并绑定内置的 Dola 号池引擎作为系统视频槽位的候选提供者。

## Impact

- **Affected Code**:
  - `lib/services/ai_config_store.dart`: 扩展内置视频提供者探测。
  - `lib/tools/ai_video_studio/services/video_gen_adapter.dart`: 注册 `DolaPoolVideoAdapter`。
  - `lib/tools/dola_pool/`: 新建 Dola 号池的核心逻辑、状态存储与 UI 界面。
  - `packages/dola_signer/` (或 `assets/dola/`): 引入微型 BDMS 签名 Node 脚本资产。
- **Dependencies**: 本机依赖 Node.js（用于签名，系统已就绪）与已内置的 FFmpeg。
