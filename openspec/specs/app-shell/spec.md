## Purpose

应用外壳提供整个工具箱的统一桌面形态：深色 Raycast 风格的侧边栏导航、插件化工具注册、搜索与最近使用，使工具可以低成本持续增加而无需修改外壳代码。

## Requirements

### Requirement: 深色主题桌面外壳

应用 SHALL 以"侧边栏 + 内容区"的桌面布局呈现，整体采用深色主题（Raycast 风格：深色背景、紧凑排版、弱边框分隔、强调色点缀），并遵循统一的设计 token（色板、字体层级、间距阶梯、圆角）。应用 MUST NOT 保留旧的 2 列卡片墙首页与蓝色 AppBar 样式。

#### Scenario: 启动后的主界面

- **WHEN** 用户启动应用
- **THEN** 显示左侧侧边栏与右侧内容区的布局，界面为深色主题，默认选中一个工具或显示欢迎页

#### Scenario: 视觉一致性

- **WHEN** 用户在任意两个工具页之间切换
- **THEN** 两个页面使用相同的背景色、字体层级、控件样式与间距规范，无样式漂移

### Requirement: 工具注册表

应用 SHALL 提供工具注册表机制，每个工具以声明方式注册元数据（标识、名称、描述、图标、分类、页面构建器）。新增或移除一个工具 MUST NOT 需要修改外壳导航代码。

#### Scenario: 注册即出现

- **WHEN** 开发者向注册表注册一个新工具
- **THEN** 该工具自动出现在侧边栏对应分类下，可被导航打开，无需改动外壳代码

### Requirement: 侧边栏导航与分类分组

侧边栏 SHALL 按分类分组展示全部已注册工具，显示工具名称与图标，并在选中时于内容区展示对应工具页面。侧边栏 MUST NOT 硬编码工具数量或工具清单；工具集的唯一来源为工具注册表，任何新增或移除工具 MUST NOT 需要修改侧边栏或本规格中的工具枚举。

#### Scenario: 切换工具

- **WHEN** 用户点击侧边栏中的某个工具
- **THEN** 内容区切换为该工具的页面，侧边栏高亮该项

#### Scenario: 工具按分类分组

- **WHEN** 用户查看侧边栏
- **THEN** 工具按分类（如 文件、包与构建、系统）分组展示，组标题可辨识

#### Scenario: 工具集自洽不依赖硬编码枚举

- **WHEN** 注册表新增或移除一个工具
- **THEN** 侧边栏按注册表当前内容正确呈现分组，无需同步修改任何工具计数或工具清单的硬编码文本

### Requirement: 工具搜索过滤

应用 SHALL 提供搜索入口，按工具名称与描述实时过滤侧边栏工具列表，并支持键盘操作定位与打开工具。

#### Scenario: 搜索过滤

- **WHEN** 用户在搜索框输入"重命名"
- **THEN** 列表仅保留匹配的工具（如"批量重命名"），清空搜索后恢复完整列表

#### Scenario: 键盘打开工具

- **WHEN** 用户通过键盘在搜索结果中移动选中并按回车
- **THEN** 内容区打开选中的工具页面

### Requirement: 最近使用

应用 SHALL 记录工具使用顺序，并在侧边栏或搜索默认态中优先展示最近使用的工具。最近使用记录 MUST 持久化，重启后保留。最近使用中引用已不再注册的工具标识时，系统 MUST NOT 显示一个无法打开的条目，MUST NOT 崩溃，且 MUST 将其重定向到功能承接的工具而非静默丢弃用户的使用记录。

#### Scenario: 最近使用排序

- **WHEN** 用户打开过某个工具后返回列表默认态
- **THEN** 该工具出现在最近使用区域的靠前位置，且重启应用后仍保留

#### Scenario: 已移除工具的历史记录被重定向

- **WHEN** 最近使用记录中保存了"清理构建产物"的历史条目，而该工具已并入智能磁盘瘦身
- **THEN** 最近使用区域呈现"智能磁盘瘦身"，点击后打开智能磁盘瘦身工具，且不出现空条目或报错

### Requirement: Uncaught async failures leave a diagnostic trace
Every window entry point SHALL install a global error handler so that an uncaught exception from an asynchronous operation (for example one started from a button handler) is recorded with a diagnostic message, rather than being silently swallowed.

#### Scenario: Button-initiated async failure is recorded
- **WHEN** an async operation started by a control's callback throws and no code in the call chain catches it
- **THEN** the global handler records the error and its stack
- **AND** the failure appears in the diagnostic log rather than disappearing.

#### Scenario: All window entry points are covered
- **WHEN** the set of window entry points is inspected
- **THEN** each one that calls `runApp` installs the global error handling
- **AND** a window that lacks it is a defect.
