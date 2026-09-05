## Purpose

异步磁盘扫描能力确保扫描过程不阻塞 Flutter UI 线程，用户在扫描期间可以正常交互界面、查看实时进度，并能随时取消正在进行的扫描操作。

## ADDED Requirements

### Requirement: 非阻塞扫描执行

磁盘扫描 SHALL 在后台执行目录遍历与大小计算，MUST NOT 阻塞 Flutter 主 Isolate 的事件循环。扫描期间 UI SHALL 保持 60fps 响应，鼠标动画与进度指示器正常运行。

#### Scenario: 扫描期间 UI 保持响应

- **WHEN** 用户点击"开始全盘智能分析"按钮
- **THEN** 扫描立即开始，进度条动画流畅运行，鼠标不出现转圈等待状态，用户可随时切换分类标签或滚动已有结果

#### Scenario: 大目录遍历不冻结界面

- **WHEN** 扫描遇到包含数万文件的大型目录（如 Xcode DerivedData）
- **THEN** 遍历过程分批进行，每处理一定数量的文件后 yield 控制权给 Flutter 框架，UI 帧率不低于 30fps

### Requirement: 渐进式结果展示

扫描 SHALL 采用三阶段渐进式架构，每个阶段完成后立即 yield 当前发现的所有条目，用户无需等待全部扫描完成即可查看中间结果。

#### Scenario: 阶段 1 结果即时可见

- **WHEN** 阶段 1（高发构建缓存与大型安装包）扫描完成
- **THEN** 该阶段发现的条目立即显示在列表中，用户可查看详情或开始操作，阶段 2 在后台继续

#### Scenario: 阶段间结果累积

- **WHEN** 阶段 2 扫描完成
- **THEN** 新发现的条目追加到已有列表中，已展示的条目位置与勾选状态保持不变

### Requirement: 可修改的扫描结果列表

扫描结果列表 SHALL 支持用户手动修改每项的勾选状态。Stream yield 的结果 MUST 为可修改的普通列表，MUST NOT 使用 `List.unmodifiable`。

#### Scenario: 手动勾选与取消

- **WHEN** 用户点击某个条目的复选框
- **THEN** 该条目的勾选状态立即切换，底部"安全移入废纸篓"按钮的预估大小同步更新
