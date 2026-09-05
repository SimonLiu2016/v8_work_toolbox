## Purpose

孤立残留精准检测通过多信号源交叉验证（Bundle ID、别名映射、子串匹配、修改时间）替代当前的精确名称匹配，系统性地防止正在使用的应用被误判为可清理残留，确保破坏性操作默认保守。

## ADDED Requirements

### Requirement: Bundle ID 精确匹配

检测器 SHALL 读取 `/Applications` 和 `~/Applications` 下所有 `.app` 包的 `Info.plist`，提取 `CFBundleIdentifier`，与 `~/Library/Application Support`、`~/Library/Caches`、`~/Library/Containers` 下的目录名进行精确匹配。匹配成功的目录 MUST 被判定为已安装应用的数据目录，MUST NOT 被标记为孤立残留。

#### Scenario: Bundle ID 格式目录匹配

- **WHEN** Application Support 下存在一个以反向域名格式命名的目录（如 `com.microsoft.VSCode`）
- **THEN** 检测器将其与已安装应用的 Bundle ID 列表比对，匹配成功则跳过，不进入孤立残留候选

### Requirement: 已知别名映射与子串双向匹配

检测器 SHALL 维护一个常见应用别名映射表（如 `Code` → `visual studio code`，`bilibili` → `哔哩哔哩`），并在映射未命中时执行子串双向匹配：检查目录名是否为任何已安装应用名的子串，或应用名是否为目录名的子串。

#### Scenario: 别名映射命中

- **WHEN** Application Support 下存在 `Code` 目录，别名映射表中 `code` → `visual studio code`
- **THEN** 检测器将其与 `Visual Studio Code.app` 关联，判定为已安装应用，不标记为孤立残留

#### Scenario: 子串匹配命中

- **WHEN** Application Support 下存在 `BraveSoftware` 目录，已安装应用中有 `Brave Browser.app`
- **THEN** 子串匹配发现 `brave` ⊂ `brave browser`，判定为关联应用，标记为谨慎确认而非安全清理

### Requirement: 最近修改时间安全降级

未通过 Bundle ID 和名称匹配的目录，检测器 SHALL 根据其最近修改时间降级安全等级。MUST NOT 将近期有修改活动的目录标记为"安全清理"。

#### Scenario: 7 天内有修改

- **WHEN** 一个未匹配目录的最近修改时间在 7 天内
- **THEN** 安全等级降级为"高风险"（danger），默认不勾选，提示用户"该目录近期有活动，强烈建议保留"

#### Scenario: 30 天内有修改

- **WHEN** 一个未匹配目录的最近修改时间在 8-30 天内
- **THEN** 安全等级降级为"谨慎确认"（caution），默认不勾选，提示用户核实

#### Scenario: 90 天以上无修改

- **WHEN** 一个未匹配目录的最近修改时间在 90 天以前
- **THEN** 安全等级保持"安全清理"（safe），默认勾选

### Requirement: 用户反馈闭环

当用户手动取消勾选一个被系统标记为"安全清理"的条目时，系统 SHALL 记录该决策到持久化配置。下次扫描时，已标记的目录 MUST 自动应用用户的保留决策，MUST NOT 再次默认勾选。

#### Scenario: 用户取消勾选后持久化

- **WHEN** 用户手动取消勾选一个"安全清理"条目
- **THEN** 该条目的路径与决策被写入配置文件，UI 显示"已标记为保留"标识

#### Scenario: 再次扫描自动应用

- **WHEN** 用户重新执行全盘扫描，遇到已标记为保留的目录
- **THEN** 该目录自动显示为未勾选状态，安全标签旁显示"用户标记保留"标识

### Requirement: 默认保守策略

所有未通过任何验证层的目录，检测器 MUST 默认标记为"谨慎确认"（caution），MUST NOT 默认标记为"安全清理"。

#### Scenario: 完全未知目录

- **WHEN** 一个目录未命中 Bundle ID、别名映射、子串匹配，且修改时间超过 90 天
- **THEN** 标记为"谨慎确认"，默认不勾选，提示用户"未找到关联应用，请确认后手动勾选"
