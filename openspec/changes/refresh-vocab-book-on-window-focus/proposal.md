## Why

生词本的词条变化不会反映到已经打开的生词本页面上。

具体地说：从浏览器伴侣的浮窗（或任何其他进程/入口）往词库里加了一个词之后，主窗口里那个打开着的「生词本」工具页**不会多出这一条**——直到用户手动切走再切回来，或重启应用。

这不是某个环节写错了，而是**这个能力从来没实现过**：

```
VocabStore          普通类，不是 ChangeNotifier —— 没有任何通知机制
VocabBookPage       只在 initState 和自己的操作后 _loadData()
浮窗 / 桌面端查词窗口  desktop_multi_window 起的**独立进程**，写的是同一个 SQLite 库
```

`ChangeNotifier` 是进程内的，跨进程不生效。所以就算把 `VocabStore` 改成 `ChangeNotifier`，主窗口依然收不到浮窗的通知——它俩根本不是同一个进程。

项目里已有可参照的做法：`ScheduledNewsService extends ChangeNotifier`、`SettingsStore` 用 `ValueNotifier`。但那些都只在单进程内广播，没有解决跨进程的先例。

## What Changes

- **主窗口重新获得焦点时，生词本页重新查询词库**：这是一个显式的"外部可能动过数据"信号，不引入新的跨进程通道。
- **静默刷新**：查询期间不显示 loading、不清空现有列表——避免用户切回窗口时看到一次闪烁。
- **只在真正有变化时才重建列表**：查询结果与当前列表不一致才 `setState`，避免每次聚焦都触发无意义的重建。

这是方案①（聚焦刷新），不是真·实时。理由：生词本不是仪表盘，用户不会在浮窗点了之后盯着主窗口背后偷偷变；用户是在切回主窗口时看它，那时候新就够了。为"实时"要新建反向 EventChannel 或本地通知端点——架构成本与这个场景的价值不匹配。

## Capabilities

### New Capabilities

- `vocab-book-fresh-on-focus`: 生词本工具页在主窗口重新激活时重新查询词库，使其他入口（浏览器浮窗、独立查词窗口、系统服务）添加的词条对用户可见。

### Modified Capabilities

- `app-shell`: 主窗口的激活事件成为一次数据新鲜度信号 —— 获知外部进程可能改过共享数据，并按需刷新。

## Impact

- **Flutter 层**：`lib/tools/vocab_book/ui/vocab_book_page.dart`（挂 `WindowListener.onWindowFocus`、按变化决定是否重建）。
- **不需要**：新通道、新依赖、新表、新字段；`VocabStore` 与数据库不动。
- **非目标**：不做真·实时跨进程推送（需要反向 EventChannel 或本地通知端点，成本与收益不匹配）；不做其他工具页的同类刷新（本次只覆盖用户报告的生词本，但做法可复制——若将来笔记/运维也要,应抽成共享机制而不是各处复制监听）；不做轮询（费电且有延迟）。
