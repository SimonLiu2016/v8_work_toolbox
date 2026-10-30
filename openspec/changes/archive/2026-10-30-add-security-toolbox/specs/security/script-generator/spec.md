## Purpose

通过 AI 根据目标信息和场景描述生成定制化渗透测试脚本，维护可复用脚本模板库，并提供在沙箱环境中安全执行脚本的能力。

## ADDED Requirements

### Requirement: AI 脚本生成

系统 SHALL 接受用户的自然语言描述（目标 IP/URL、期望达成的效果、约束条件），由 AI 生成对应的可执行脚本，支持语言：Python（优先）、Bash、Ruby（Metasploit 模块格式）。

#### Scenario: 自然语言生成脚本

- **WHEN** 用户输入"对 192.168.1.105 的 445 端口测试 SMB 用户名枚举，输出有效用户列表"
- **THEN** AI SHALL 生成完整的 Python 脚本（使用 impacket 库），包含参数化输入和格式化输出

#### Scenario: 基于 Finding 生成 PoC

- **WHEN** 用户在某个 CVE Finding 上点击"AI 生成利用脚本"
- **THEN** AI SHALL 参考该 CVE 的公开技术细节，生成概念验证脚本骨架，标注需要用户自定义的参数

### Requirement: 脚本模板库

系统 SHALL 内置覆盖常用场景的脚本模板，分类包含：端口扫描自定义脚本、服务爆破脚本、反弹 Shell 生成、Payload 免杀框架、网络流量分析、自动化报告脚本。用户可将 AI 生成的脚本保存为新模板。

#### Scenario: 模板浏览与使用

- **WHEN** 用户打开脚本模板库并选择"反弹 Shell - Python"模板
- **THEN** 系统 SHALL 在编辑器中打开模板，高亮标注需要填写的参数（IP、PORT 等）

### Requirement: 脚本编辑器

系统 SHALL 提供内置代码编辑器（语法高亮支持 Python/Bash/Ruby），支持脚本保存、版本历史（最近 10 次修改）、代码格式化。

#### Scenario: 语法高亮

- **WHEN** 编辑器中加载 Python 脚本
- **THEN** 系统 SHALL 展示 Python 语法高亮，关键字、字符串、注释以不同颜色区分

### Requirement: 沙箱执行

系统 SHALL 支持在 App 内直接执行脚本（通过 `Process.run`），实时展示标准输出和标准错误，支持在执行中传入参数，执行完成后将输出保存至会话时间线。

#### Scenario: 脚本执行与输出捕获

- **WHEN** 用户点击"运行"执行一个 Python 脚本
- **THEN** 系统 SHALL 以流式方式展示 stdout/stderr，执行完成后提供"保存输出到会话"选项

#### Scenario: 执行中断

- **WHEN** 用户点击"停止"
- **THEN** 系统 SHALL 立即终止脚本进程（SIGTERM），展示已捕获的部分输出
