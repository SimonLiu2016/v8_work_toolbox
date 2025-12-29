#!/bin/bash

# Beyond Compare 配置修改工具
# 作者: Simon
# 日期: 2025-09-15

# 定义颜色代码
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 定义 Beyond Compare 配置文件路径
BC_DIR="$HOME/Library/ApplicationSupport/Beyond Compare"

echo -e "${GREEN}Beyond Compare 配置修改工具${NC}"
echo "================================"

# 检查目录是否存在
if [ ! -d "$BC_DIR" ]; then
  echo -e "${RED}错误: Beyond Compare 配置目录不存在: $BC_DIR${NC}"
  exit 1
fi

echo -e "${YELLOW}正在处理配置文件...${NC}"

# 步骤1: 修改 BCState.xml 文件
BC_STATE_FILE="$BC_DIR/BCState.xml"
if [ -f "$BC_STATE_FILE" ]; then
  # 创建备份文件
  cp "$BC_STATE_FILE" "$BC_STATE_FILE.bak"
  
  # 删除 CheckID 和 LastChecked 标签
  sed -i '' '/<CheckID/d' "$BC_STATE_FILE"
  sed -i '' '/<LastChecked/d' "$BC_STATE_FILE"
  
  # 验证修改是否成功
  if grep -q "<CheckID\|<LastChecked" "$BC_STATE_FILE"; then
    echo -e "${RED}警告: BCState.xml 文件中的 CheckID 或 LastChecked 未完全删除${NC}"
  else
    echo -e "${GREEN}✓ BCState.xml 文件已更新${NC}"
  fi
else
  echo -e "${YELLOW}警告: BCState.xml 文件不存在: $BC_STATE_FILE${NC}"
fi

# 步骤2: 修改 BCSessions.xml 文件
BC_SESSIONS_FILE="$BC_DIR/BCSessions.xml"
if [ -f "$BC_SESSIONS_FILE" ]; then
  # 创建备份文件
  cp "$BC_SESSIONS_FILE" "$BC_SESSIONS_FILE.bak"
  
  # 删除 Flags 属性
  sed -i '' 's/ Flags="[^"]*"//g' "$BC_SESSIONS_FILE"
  
  # 验证修改是否成功
  if grep -q 'Flags="[^"]*"' "$BC_SESSIONS_FILE"; then
    echo -e "${RED}警告: BCSessions.xml 文件中的 Flags 属性未完全删除${NC}"
  else
    echo -e "${GREEN}✓ BCSessions.xml 文件已更新${NC}"
  fi
else
  echo -e "${YELLOW}警告: BCSessions.xml 文件不存在: $BC_SESSIONS_FILE${NC}"
fi

# 询问用户是否启动 Beyond Compare
echo ""
read -p "是否启动 Beyond Compare? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo -e "${YELLOW}正在启动 Beyond Compare...${NC}"
  open -a "Beyond Compare"
  echo -e "${GREEN}Beyond Compare 已启动${NC}"
else
  echo -e "${YELLOW}已跳过启动 Beyond Compare${NC}"
fi

echo -e "${GREEN}所有操作已完成！${NC}"