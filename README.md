# V8 工作工具箱

V8 工作工具箱是一个实用的文件处理工具集合，包含以下工具：

1. Beyond Compare 配置修改工具 - 用于自动修改 Beyond Compare 的配置文件，以禁用更新检查并清理会话标志。
2. 批量重命名工具 - 按规则批量重命名文件。
3. 文件夹对比工具 - 对比两个文件夹中同名文件的内容差异。

## Beyond Compare 配置修改工具功能说明

1. 自动导航到 Beyond Compare 配置目录
2. 修改 BCState.xml 文件，删除更新检查相关的 CheckID 和 LastChecked 标签
3. 修改 BCSessions.xml 文件，删除 Flags 属性
4. 启动 Beyond Compare 应用程序

## 批量重命名工具功能说明

批量重命名工具允许用户使用正则表达式规则批量重命名文件。

## 文件夹对比工具功能说明

文件夹对比工具用于对比两个文件夹中同名文件的内容差异，支持多种文件格式（目前实现 YAML 格式），并可将差异结果导出为 CSV 文件。

详细使用说明请参见 [文件夹对比工具使用说明](README_COMPARE_TOOL.md)。

## 使用方法

### 方法一：使用图形界面应用程序（可能遇到权限问题）

在应用程序中运行 V8WorkToolbox，选择 "BC 配置工具"。

### 方法二：使用终端脚本（推荐，避免权限问题）

在终端中执行以下命令：

```bash
./fix_bc_config.sh
```

### 方法三：手动执行命令

如果上述方法都无法使用，可以手动执行以下命令：

```bash
cd "/Users/$USER/Library/Application Support/Beyond Compare"
sed -i "" "/<CheckID/d" BCState.xml
sed -i "" "/<LastChecked/d" BCState.xml
sed -i "" "s/Flags=\"[^\"]*\" //" BCSessions.xml
open -a "Beyond Compare"
```

## 脚本说明

### fix_bc_config.sh（推荐使用）

这个脚本是为了解决 macOS 权限问题而创建的终端脚本版本。

```bash
#!/bin/bash

# Beyond Compare 配置修复脚本
# 这个脚本可以直接在终端中运行，避免 macOS 应用程序权限问题

echo "Beyond Compare 配置修复工具"
echo "=========================="

# 检查是否提供了 Beyond Compare 配置目录路径
if [ $# -eq 0 ]; then
    # 默认路径
    BC_DIR="/Users/$(whoami)/Library/Application Support/Beyond Compare"
    echo "使用默认路径: $BC_DIR"
else
    BC_DIR="$1"
    echo "使用指定路径: $BC_DIR"
fi

# 检查目录是否存在
if [ ! -d "$BC_DIR" ]; then
    echo "错误: Beyond Compare 配置目录不存在: $BC_DIR"
    echo "请确保 Beyond Compare 已安装，或提供正确的配置目录路径"
    echo "用法: ./fix_bc_config.sh [配置目录路径]"
    exit 1
fi

echo "正在处理 Beyond Compare 配置文件..."

# 步骤1: 修改 BCState.xml 文件
BC_STATE_FILE="$BC_DIR/BCState.xml"
if [ -f "$BC_STATE_FILE" ]; then
    # 创建备份文件
    cp "$BC_STATE_FILE" "$BC_STATE_FILE.bak"
    echo "已创建 BCState.xml 备份文件"

    # 删除 CheckID 和 LastChecked 标签
    sed -i '' '/<CheckID/d' "$BC_STATE_FILE"
    sed -i '' '/<LastChecked/d' "$BC_STATE_FILE"
    echo "✓ BCState.xml 文件已更新"
else
    echo "警告: BCState.xml 文件不存在: $BC_STATE_FILE"
fi

# 步骤2: 修改 BCSessions.xml 文件
BC_SESSIONS_FILE="$BC_DIR/BCSessions.xml"
if [ -f "$BC_SESSIONS_FILE" ]; then
    # 创建备份文件
    cp "$BC_SESSIONS_FILE" "$BC_SESSIONS_FILE.bak"
    echo "已创建 BCSessions.xml 备份文件"

    # 删除 Flags 属性
    sed -i '' 's/Flags="[^"]*" //' "$BC_SESSIONS_FILE"
    echo "✓ BCSessions.xml 文件已更新"
else
    echo "警告: BCSessions.xml 文件不存在: $BC_SESSIONS_FILE"
fi

# 步骤3: 启动 Beyond Compare
echo "正在启动 Beyond Compare..."
open -a "Beyond Compare"

echo "所有操作已完成！"
echo ""
echo "提示: 如果仍然遇到权限问题，请尝试以下方法:"
echo "1. 在终端中运行此脚本: ./fix_bc_config.sh"
echo "2. 或者手动运行以下命令:"
echo "   cd '/Users/$(whoami)/Library/Application Support/Beyond Compare'"
echo "   sed -i '' '/<CheckID/d' BCState.xml"
echo "   sed -i '' '/<LastChecked/d' BCState.xml"
echo "   sed -i '' 's/Flags=\"[^\"]*\" //' BCSessions.xml"
```

### modify_bc_config.sh（原始版本）

```bash
#!/bin/bash

# 定义 Beyond Compare 配置文件路径
BC_DIR="$HOME/Library/ApplicationSupport/Beyond Compare"

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

```
<TCheckForUpdatesState>
    <Build Value="24545"/>
</TCheckForUpdatesState>
```

### BCSessions.xml

修改前：

``xml
<BCSessions Flags="2516348444542" Version="1" MinVersion="1">
</BCSessions>

```

修改后：

```

<BCSessions Version="1" MinVersion="1">
</BCSessions>
