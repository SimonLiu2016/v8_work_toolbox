## Purpose

保证每个窗口进程（主窗口与 desktop_multi_window 子窗口）在渲染首帧前就具备其功能
所依赖的平台级单例状态，使「某功能在子窗口里静默失效」这类问题不再依赖用户在功能层
反推根因。

## ADDED Requirements

### Requirement: Window process initializes its required services before first frame

每个窗口进程 SHALL 在 `runApp` 之前完成该窗口功能所依赖的平台级单例初始化。
承载 AI 能力的窗口进程（主窗口、笔记本子窗口）MUST 至少完成 AI 配置存储与其加密
密钥存储、以及应用级代理通道配置的初始化。初始化不得因为「同一二进制已有其他进程
初始化过」而被跳过——单例状态是进程级的。

#### Scenario: Notebook sub-window can resolve AI slot candidates

- **WHEN** 用户从主工具注册表打开「笔记本」独立窗口，并在其中发起一次需要 AI 的请求
- **THEN** 该窗口进程内的 AI 配置存储已完成初始化，槽位绑定表与主窗口一致
- **AND** 请求按槽位路由找到候选供应商，而非报「槽位无可用候选供应商」。

#### Scenario: Notebook sub-window honors configured proxy

- **WHEN** 用户已在设置中配置 HTTP/HTTPS 代理，并在笔记本子窗口内发起联网请求
- **THEN** 该窗口进程使用已配置的代理通道，而非绕过代理直连。

#### Scenario: Required service initialization failure is surfaced

- **WHEN** 子窗口进程某项必需的单例初始化失败
- **THEN** 该失败被记录并可被诊断（明确的错误信号），而不是让下游功能表现为
  「配置为空」或「槽位无候选」这类无法归因的症状。

### Requirement: Per-window required-service list is explicit

系统 SHALL 为每种窗口类型维护一份显式的必需服务清单，作为启动路径的一部分。
新增平台级单例时，该清单 MUST 同步更新，使遗漏在代码审查与测试中可被发现，而非
只在用户报告功能失效后才暴露。

#### Scenario: Adding a platform singleton requires updating the list

- **WHEN** 新增一个被某窗口功能依赖的平台级单例服务
- **THEN** 该窗口类型的必需服务清单中新增对应条目
- **AND** 存在可验证的检查（测试或静态清单）确认清单覆盖了该窗口实际使用的服务。
