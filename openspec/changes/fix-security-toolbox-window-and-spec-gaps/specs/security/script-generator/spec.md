## ADDED Requirements

### Requirement: 脚本编辑器输入状态维护
系统 SHALL 在 State 生命周期中统一维护脚本代码控制器的生命周期，禁止在每帧 build 过程中动态创建控制器。

#### Scenario: 编写与修改脚本代码
- **WHEN** 用户在脚本编辑区输入、修改或光标定位
- **THEN** 输入法与光标保持正常，文本内容随按键稳定同步更新，不发生重置或焦点丢失
