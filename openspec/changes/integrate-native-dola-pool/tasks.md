## 1. 签名引擎资产与轻量托管

- [x] 1.1 导入 `bdms_sign_url.js` 与 `bdms-sdk.js` 至 `assets/dola/` 并在 `pubspec.yaml` 中配置资源路径
- [x] 1.2 实现 `DolaSignerService`，支持以后台 Node 子进程（`--daemon`）形式常驻，通过 stdin/stdout JSON-RPC 提供异步 URL 签名方法
- [x] 1.3 编写 `DolaSignerService` 单元测试，验证单条及并发 URL 签名的正确性与超时保护

## 2. 账号池模型、凭证存储与调度器

- [x] 2.1 定义 `DolaAccount` 数据模型（含别名、额度、分组状态、冷却时间、代理配置等）与 JSON 序列化
- [x] 2.2 实现 `DolaAccountStore`，结合应用支持目录与 Keychain 安全存取 Cookie 凭据与元数据
- [x] 2.3 实现 `DolaPoolScheduler` 七状态调度状态机（满额、半额、冷却、生成中、风控、异常）及东九区 0 点额度重置逻辑
- [x] 2.4 实现 Dola 账号探针服务，支持一键发送问候/探针校验 Cookie 有效性并实时回写真实剩余点数
- [x] 2.5 编写账号存储与调度器单元测试，验证满额/半额扣点、并发锁定与故障冷却逻辑

## 3. 视频生成引擎适配器

- [x] 3.1 实现 Dola 上游协议客户端（`DolaClient`），支持通过签名 URL 提交多参考图/文本任务并轮询状态
- [x] 3.2 实现 `DolaPoolVideoAdapter`，实现 `VideoGenAdapter` 与 `CancellableVideoGenAdapter` 接口
- [x] 3.3 实现去水印直链提取与 30 秒片段自适应处理（遇分段自动调用 `FfmpegComposer` 进行本地拼合）
- [x] 3.4 在 `VideoGenAdapterFactory` 中注册 `DolaPoolVideoAdapter`，并在系统配置中提供发现与绑定

## 4. UI 界面与管理面板集成

- [x] 4.1 在「系统设置 -> AI 基础设施」新增「Dola 免费号池」配置面板
- [x] 4.2 实现 Cookie 批量粘贴导入、格式校验与弹窗交互
- [x] 4.3 实现账号列表视图（卡片展示状态标签、剩余点数、最后使用时间、操作按钮：探活、改名、删除、设代理）
- [x] 4.4 在 AI 视频工坊设置对话框中支持一键选择 Dola 号池模型（Seedance 2.0 / 2.5）

## 5. 验收与系统测试

- [x] 5.1 编写 `dola_pool_video_adapter_test.dart` 自动化测试，验证适配器生命周期与取消控制
- [x] 5.2 执行全量测试套件 `flutter test`
- [x] 5.3 按照工程规则执行 `./scripts/deploy_local.sh` 重新构建并部署替换本机应用
