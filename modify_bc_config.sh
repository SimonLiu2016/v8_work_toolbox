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
  # 创建备份文件
  cp "$BC_STATE_FILE" "$BC_STATE_FILE.bak"
  
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
  # 创建备份文件
  cp "$BC_SESSIONS_FILE" "$BC_SESSIONS_FILE.bak"
  
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