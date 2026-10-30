## ADDED Requirements

### Requirement: 独立子窗口生命周期分发
系统 SHALL 在桌面子窗口启动参数为 `security-toolbox` 时，独立初始化其必需的平台级服务（`AppPaths`、`SettingsStore`、`ProxySettings`、`AiConfigStore`），并加载渲染安全工具箱专用窗体，禁止回退为主窗体。

#### Scenario: 打开安全工具箱独立窗口
- **WHEN** 用户在主界面触发打开安全工具箱（`openNewWindow`）
- **THEN** 系统 SHALL 创建并显示独立的安全工具箱窗口，尺寸适配桌面工作台（宽 ≥ 1200，高 ≥ 800），其内部具备完整的数据持久化与 AI 服务能力，主窗体保持正常状态

### Requirement: 资产手动标注交互
系统 SHALL 在资产清单中提供手动标注交互界面，允许用户查看并修改任意资产的自定义备注（`userNote`），并持久化到本地数据库。

#### Scenario: 用户编辑资产备注
- **WHEN** 用户在资产清单项中点击编辑备注并输入自定义文本
- **THEN** 系统 SHALL 保存该备注至数据库并在界面刷新展示，后续扫描或重新探测该资产时 SHALL 保留用户标注不予覆盖
