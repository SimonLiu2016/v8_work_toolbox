## ADDED Requirements

### Requirement: 资产库多窗口同步与刷新

系统 SHALL 支持跨窗口/跨进程的资产索引变动感知与刷新，使在独立子窗口（如 Agnes 试炼场）写入的资产能够被主窗口或其他已打开资产库的页面即时发现与加载。

`AssetLibrary` 单例 SHALL 在加载或查询时检查磁盘 `asset_index.json` 的修改时间；当磁盘文件修改时间晚于内存最后加载时间时，SHALL 自动重载磁盘索引。同时，`AssetLibrary` SHALL 暴露显式的重载接口（如 `reload()`）。

`AssetLibraryPage` 界面 SHALL 提供手动的「刷新」按钮，并在切换回该页面时主动触发资产重载，使用户无需重启整个应用即可看到最新入库的资产。

#### Scenario: 外部进程更新资产索引后自动重载

- **WHEN** 磁盘上的 `asset_index.json` 被试炼场等子窗口写入了新条目
- **THEN** 主窗口的 `AssetLibrary` 在下一次读取或显式刷新时检测到时间戳变动并重新加载磁盘数据
- **AND** 内存中的资产列表包含最新添加的条目

#### Scenario: 用户在资产库界面手动刷新

- **WHEN** 用户在资产库界面点击「刷新」按钮
- **THEN** 界面重新读取磁盘索引并更新网格列表，显示最新资产数量与卡片
