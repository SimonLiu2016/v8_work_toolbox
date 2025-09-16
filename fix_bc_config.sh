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