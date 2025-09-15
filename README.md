# Beyond Compare 配置修改工具

这个工具用于自动修改 Beyond Compare 的配置文件，以禁用更新检查并清理会话标志。

## 功能说明

1. 自动导航到 Beyond Compare 配置目录
2. 修改 BCState.xml 文件，删除更新检查相关的 CheckID 和 LastChecked 标签
3. 修改 BCSessions.xml 文件，删除 Flags 属性
4. 启动 Beyond Compare 应用程序

## 使用方法

在终端中执行以下命令：

```bash
./modify_bc_config.sh
```

## 脚本说明

### modify_bc_config.sh

```bash
#!/bin/bash

# 定义 Beyond Compare 配置文件路径
BC_DIR="/Users/simon/Library/ApplicationSupport/Beyond Compare"

echo "正在处理 Beyond Compare 配置文件..."

# 检查目录是否存在
if [ ! -d "$BC_DIR" ]; then
  echo "错误: Beyond Compare 配置目录不存在: $BC_DIR"
  exit 1
fi

# 步骤1: 修改 BCState.xml 文件
BC_STATE_FILE="$BC_DIR/BCState.xml"
if [ -f "$BC_STATE_FILE" ]; then
  # 删除 CheckID 和 LastChecked 标签
  sed -i '' '/<CheckID/d' "$BC_STATE_FILE"
  sed -i '' '/<LastChecked/d' "$BC_STATE_FILE"
  echo "BCState.xml 文件已更新"
else
  echo "警告: BCState.xml 文件不存在: $BC_STATE_FILE"
fi

# 步骤2: 修改 BCSessions.xml 文件
BC_SESSIONS_FILE="$BC_DIR/BCSessions.xml"
if [ -f "$BC_SESSIONS_FILE" ]; then
  # 删除 Flags 属性
  sed -i '' 's/Flags="[^"]*" //' "$BC_SESSIONS_FILE"
  echo "BCSessions.xml 文件已更新"
else
  echo "警告: BCSessions.xml 文件不存在: $BC_SESSIONS_FILE"
fi

# 步骤3: 启动 Beyond Compare
echo "正在启动 Beyond Compare..."
open -a "Beyond Compare"

echo "所有操作已完成！"
```

## 修改前后的文件格式示例

### BCState.xml

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

### BCSessions.xml

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
