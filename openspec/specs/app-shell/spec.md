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

注册表 SHALL 同时暴露工具的唯一标识作为持久化配置键与代理通道键；新增工具时其标识 SHALL 在 `tool_definition.dart` 中以常量声明，而不是在使用处散落字面量。

新工具的分类 SHALL 依据分类归属判定规则（capability: `tool-category-assignment`）按工具目的推出，而不是由接入者自行判断。当工具的分类与其名称给人的第一印象不符时，注册处 SHALL 注明判定依据，说明为何属于该分类、为何不属于看起来更接近的分类。

#### Scenario: 注册即出现

- **WHEN** 开发者向注册表注册一个新工具
- **THEN** 该工具自动出现在侧边栏对应分类下，可被导航打开，无需改动外壳代码

#### Scenario: 新增工具标识有单一来源

- **WHEN** 新增一个需要持久化配置或代理开关的工具
- **THEN** 该工具的标识以常量形式集中声明，配置读取、代理判断与注册表条目引用同一常量

#### Scenario: 新工具的分类有判定依据

- **WHEN** 开发者注册一个新工具并声明其分类
- **THEN** 该分类 SHALL 是分类归属判定规则的首个匹配结果
- **AND** 当名称暗示的分类与判定结果不符时，注册处 SHALL 注明判定依据

### Requirement: 侧边栏导航与分类分组

侧边栏 SHALL 按分类分组展示全部已注册工具，显示工具名称与图标，并在选中时于内容区展示对应工具页面。侧边栏 MUST NOT 硬编码工具数量或工具清单；工具集的唯一来源为工具注册表，任何新增或移除工具 MUST NOT 需要修改侧边栏或本规格中的工具枚举。

#### Scenario: 切换工具

- **WHEN** 用户点击侧边栏中的某个工具
- **THEN** 内容区切换为该工具的页面，侧边栏高亮该项

#### Scenario: 工具按分类分组

- **WHEN** 用户查看侧边栏
- **THEN** 工具按分类（如 文件处理、系统与配置）分组展示，组标题可辨识

#### Scenario: 分类不出现空置入口

- **WHEN** 某个分类下的最后一个工具被移除
- **THEN** 该分类本身 SHALL 随之从可切换的分类集合中消失
- **AND** 侧边栏 MUST NOT 留下一个点进去没有任何工具的分类入口

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

应用 SHALL 记录工具使用顺序，并在侧边栏或搜索默认态中优先展示最近使用的工具。最近使用记录 MUST 持久化，重启后保留。最近使用中引用已不再注册的工具标识时，系统 MUST NOT 显示一个无法打开的条目，MUST NOT 崩溃。仅当被移除工具的功能被另一个工具承接时，系统 SHALL 将其重定向到该承接工具；无承接工具时，历史标识 SHALL 被静默忽略——MUST NOT 为了填满条目而重定向到功能不相关的工具。

#### Scenario: 最近使用排序

- **WHEN** 用户打开过某个工具后返回列表默认态
- **THEN** 该工具出现在最近使用区域的靠前位置，且重启应用后仍保留

#### Scenario: 已移除工具的历史记录被重定向

- **WHEN** 最近使用记录中保存了"清理构建产物"的历史条目，而该工具已并入智能磁盘瘦身
- **THEN** 最近使用区域呈现"智能磁盘瘦身"，点击后打开智能磁盘瘦身工具，且不出现空条目或报错

#### Scenario: 无承接者的已移除工具标识被忽略

- **WHEN** 最近使用记录或使用次数中保存了一个已移除且无功能承接者的工具标识（如"KMA 包生成"）
- **THEN** 该标识不出现在任何可见区域，不产生空条目、不报错、不跳转到功能不相关的工具
- **AND** 应用仍能正常启动并选中一个已注册的工具

#### Scenario: 新增工具进入常用集合

- **WHEN** 新增一个工具并被用户使用
- **THEN** 该工具与其他工具一样参与常用统计与排序，不需要为它单独维护一份工具清单

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

### Requirement: 工具面板列表项悬停与选中视觉层级

工具列表项（ToolPanel 中的工具条目）SHALL 在鼠标滑入时即时响应悬停视觉效果，且 MUST NOT 产生两项同时变灰闪烁的过渡延迟拖影；在浅色与深色主题下，悬停背景色 SHALL 具有肉眼清晰可辨的对比度。当前选中项（Active）SHALL 呈现明确的强调色视觉指示（如左侧指示条与高亮联动），与悬停态（Hover）形成清晰分明的视觉层级。

#### Scenario: 鼠标快速滑过工具列表无残影闪烁
- **WHEN** 用户在工具列表中快速移动鼠标滑过多个工具项
- **THEN** 鼠标所在项即时呈现悬停背景，上一项即时复原
- **AND** 不会出现两项或多项同时变灰并持续渐变闪烁的拖影现象。

#### Scenario: 浅色与深色模式下悬停具有清晰对比度
- **WHEN** 用户将鼠标悬停在工具项上且保持静止
- **THEN** 该项呈现肉眼清晰可见的悬停背景色与前景色反馈
- **AND** 在浅色与深色主题下均与面板底色形成舒适且分明的视觉对比。

#### Scenario: 选中项与悬停项视觉层级分明
- **WHEN** 列表中存在一个已选中的活动工具项，且鼠标移动到另一个未选中项上悬停
- **THEN** 已选中项保留明确的激活视觉标识（如左侧指示条与选中状态）
- **AND** 悬停项呈现不同于选中项的轻量悬停反馈
- **AND** 两者在视觉上不会混淆为同一种灰色块。

### Requirement: 窗口拖拽仅限专用拖拽区，不得使用全局背景拖拽

应用主窗口及所有子窗口 MUST NOT 启用 `isMovableByWindowBackground`（macOS NSWindow 全局背景拖拽）。窗口拖动 SHALL 仅由 ActivityBar 顶部的专用 `DragToMoveArea` widget（38px 高）响应用户的 pan/drag 手势，通过 `windowManager.startDragging()` 委托给系统执行窗口移动。

全局启用 `isMovableByWindowBackground` 会导致 NSWindow 在收到任何落在 FlutterView 上的 mouseDown 时，不将事件传入 Flutter 事件系统，从而使 showDialog / showModalBottomSheet 等模态层内的所有可交互控件（按钮、IconButton、InkWell）点击失效。

#### Scenario: 用户在 ActivityBar 顶部区域拖动窗口

- **WHEN** 用户在 ActivityBar 顶部 38px 的专用拖拽区按下并拖动鼠标
- **THEN** 窗口随鼠标移动，松开后停在新位置

#### Scenario: 模态对话框内的按钮可正常点击

- **WHEN** 任意 showDialog 或 showModalBottomSheet 弹出的模态层处于前台
- **THEN** 该层内的所有按钮（包括右上角关闭按钮、图标按钮、FilledButton）的 onPressed/onTap SHALL 被正常触发，不得被 NSWindow 原生事件截获

#### Scenario: ActivityBar 顶部区域之外不可拖动

- **WHEN** 用户在 ActivityBar 顶部拖拽区以外的区域（如内容区、工具面板、弹窗内）按下并拖动鼠标
- **THEN** 窗口 MUST NOT 被拖动，鼠标事件正常传递给 Flutter widget 处理

### Requirement: 桌面模态弹窗顶部交互安全区

系统在沉浸式桌面无边框窗口环境下呈现模态弹窗（Dialog）与模态抽屉（BottomSheet）时，弹窗顶部交互元素 SHALL 与应用窗口顶边保持至少 48px 的安全避让距离，确保右上角关闭、导出、定位及各快捷操作按钮不会落入 macOS 系统级标题栏拖拽截获区。

#### Scenario: 媒体预览弹窗操作栏可点击
- **WHEN** 用户在分镜工作台打开分镜媒体预览弹窗
- **THEN** 弹窗外边距与顶部保持至少 48px 间距，右上角的操作按钮（外部播放器、在访达中显示、导出、关闭）处于系统拖拽盲区之外，鼠标点击能正常触发对应操作

#### Scenario: 模态编辑抽屉顶部关闭按钮可点击
- **WHEN** 用户在资产页面唤起资产编辑模态抽屉
- **THEN** 模态抽屉内部顶部提供安全边距避让，右上角的关闭按钮完整处于有效交互区域内，点击后能正常关闭抽屉

### Requirement: 窗口关闭事件防重入与递归熔断

所有实现了 `WindowListener` 并在 `onWindowClose()` 回调中触发窗口销毁或二次关闭逻辑的界面组件，SHALL 实现状态自锁保护（例如 `_isClosing` 标志位），并在调用底层关闭命令前显式注销自身监听器（`windowManager.removeListener(this)`），MUST NOT 在 `onWindowClose()` 回调中无防护地直接调用 `windowManager.close()`。

#### Scenario: 确认关闭含有运行任务的工坊窗口
- **WHEN** 用户在有未完成小说解构任务时点击窗口关闭按钮，并在确认弹窗中选择「确认关闭并中断」
- **THEN** 系统先将关闭状态置为锁定，注销 `WindowListener`，解除 `preventClose`
- **AND** 随后调用底层关闭逻辑
- **AND** 关闭过程不会形成 Native ↔ Dart 间的二次 `close` 事件递归风暴，主线程 CPU 占用不得激增至 100%

### Requirement: 子窗口生命周期隔离

由 `desktop_multi_window` 创建的独立辅助子窗口（如查词浮窗 `lookupPanel` 等）在失焦关闭、点击关闭或隐藏时，SHALL 仅针对自身所属的子窗口实例执行关闭或隐藏操作（通过 `WindowController` 或特定子窗口通道），MUST NOT 调用作用于应用全局主窗口的 `windowManager.close()`。

#### Scenario: 查词浮窗失去焦点自动关闭
- **WHEN** 用户点击查词浮窗外部区域导致浮窗失焦
- **THEN** 查词浮窗通过子窗口实例或通道执行关闭/隐藏
- **AND** 主应用窗口的 `WindowListener` 监听器不会收到关闭事件，主应用生命周期与 CPU 占用保持平稳正常

### Requirement: 常驻透明悬浮字幕窗形态的工具

工具注册表 SHALL 支持一种"常驻透明悬浮窗 + 主窗口管理界面"的工具形态：主窗口内容区呈现该工具的管理与设置界面，同时拥有一个独立于主窗口、常驻置顶、背景透明的悬浮窗承载实时内容，两者共享同一份状态。

该形态与"内嵌于主窗口内容区"和"整页独立窗口"不同：其悬浮窗 MUST NOT 抢夺焦点，且 MUST NOT 因悬浮窗关闭而丢失主窗口持有的状态。常驻形态工具的标识 SHALL 同样在 `tool_definition.dart` 中以常量声明，且 MUST NOT 硬编码于任何导航或快捷键代码中。

#### Scenario: 注册常驻悬浮窗形态工具

- **WHEN** 开发者注册一个声明为常驻悬浮窗形态的工具
- **THEN** 该工具在主窗口内容区呈现管理界面，并可打开一个独立于主窗口的常驻透明悬浮窗，无需修改外壳导航代码

#### Scenario: 关闭悬浮窗不丢失状态

- **WHEN** 用户关闭悬浮窗后从主窗口管理界面重新打开
- **THEN** 悬浮窗恢复到关闭前的状态（含未导出的记录数据），主窗口持有的状态不受悬浮窗关闭影响

### Requirement: 实时会议翻译工具的归类

实时会议翻译工具 SHALL 归类于"笔记与学习"（`ToolCategory.note`）分类，MUST NOT 归类于"AI 与资讯"（`ToolCategory.ai`）。

**理由**：该工具处理的是用户自己的会议音频转录（用户自己产出的文字），符合 note 分类"组织用户自己产出的文字"的语义；它虽用 AI 能力，但"带 AI 能力不改变归属"。

#### Scenario: 侧边栏中的位置

- **WHEN** 用户查看侧边栏分类
- **THEN** "实时会议翻译"出现在"笔记与学习"分组下，不在"AI 与资讯"分组下

