# Beyond Compare 配置工具

## 简介

这是一个简单的 macOS 应用程序，用于自动修改 Beyond Compare 的配置文件，以禁用更新检查和清理会话标志。

## 功能

1. 自动导航到 Beyond Compare 配置目录
2. 修改 BCState.xml 文件，删除更新检查相关的 CheckID 和 LastChecked 标签
3. 修改 BCSessions.xml 文件，删除 Flags 属性
4. 提供图形界面提示操作结果

## 安装

1. 将 `BeyondCompareConfigTool.app` 拖拽到 Applications 文件夹中
2. 首次运行时可能需要在系统偏好设置中允许运行

## 使用方法

双击 `BeyondCompareConfigTool.app` 图标即可运行工具。

## 文件说明

- `bc_config_tool.sh`: 核心脚本文件
- `AppIcon.icns`: 应用程序图标文件

## 技术细节

### 修改前后的文件格式示例

#### BCState.xml

修改前：

```xml
<TCheckForUpdatesState>
    <Build Value="24545"/>
    <CheckID Value="173864067260425"/>
    <LastChecked Value="2019-12-13 10:28:02"/>
</TCheckForUpdatesState>
```

修改后：

```xml
<TCheckForUpdatesState>
    <Build Value="24545"/>
</TCheckForUpdatesState>
```

#### BCSessions.xml

修改前：

```xml
<BCSessions Flags="2516348444542" Version="1" MinVersion="1">
</BCSessions>
```

修改后：

```xml
<BCSessions Version="1" MinVersion="1">
</BCSessions>
```
