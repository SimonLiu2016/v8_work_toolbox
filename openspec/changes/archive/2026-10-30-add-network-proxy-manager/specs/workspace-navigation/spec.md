## ADDED Requirements

### Requirement: Activity Bar 网络代理系统页入口

Activity Bar 底部 SHALL 在现有「AI 配置」入口旁新增「网络代理」图标入口，点击后打开「网络代理」系统页（非工具网格中的工具）。该入口 SHALL 始终可见，不受当前工具分类选择影响。

#### Scenario: 点击网络代理入口

- **WHEN** 用户点击 Activity Bar 底部的「网络代理」图标
- **THEN** 主内容区切换到「网络代理」系统页，工具面板不显示任何工具列表

#### Scenario: 代理运行状态指示

- **WHEN** mihomo 进程正在运行（有选中节点且全局代理启用）
- **THEN** Activity Bar 的「网络代理」图标显示绿色活跃指示点；进程停止时无指示点
