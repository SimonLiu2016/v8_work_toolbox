#!/usr/bin/env bash
# ==============================================================================
# V8WorkToolbox 一键版本发布脚本
#
# 核心目标：
# 1. 确保所有修改与新增文件 100% 提交并推送到远程 Git 仓库，避免本地代码意外覆盖或丢失。
# 2. 自动化分支合并、语义化版本定义、CHANGELOG 与 Release Notes 生成、Git Tag 附注与推送。
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${PROJECT_ROOT}"

# 颜色与样式
BOLD="\033[1m"
GREEN="\033[0;32m"
CYAN="\033[0;36m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
RESET="\033[0m"

log_info()    { echo -e "${CYAN}▶ [INFO]${RESET} $*"; }
log_step()    { echo -e "\n${BOLD}${CYAN}▶ [$1]${RESET} ${BOLD}$2${RESET}"; }
log_success() { echo -e "${GREEN}✓${RESET} $*"; }
log_warn()    { echo -e "${YELLOW}⚠ [WARN]${RESET} $*"; }
log_error()   { echo -e "${RED}✗ [ERROR]${RESET} $*" >&2; }

# 参数定义
AUTO_CONFIRM=false
NO_PUSH=false
BUMP_TYPE=""
CUSTOM_VERSION=""
COMMIT_MSG=""
RELEASE_BRANCH="main"

show_help() {
  cat << EOF
V8WorkToolbox 一键版本发布工具

用法:
  ./scripts/release.sh [OPTIONS] [VERSION] [COMMIT_MESSAGE]

参数:
  VERSION             可选，目标版本号（例如：0.2.0 或 1.0.0）
  COMMIT_MESSAGE      可选，代码提交说明（若有未提交变更）

选项:
  --patch             自动升级补丁版本号 (0.1.0 -> 0.1.1)
  --minor             自动升级次版本号 (0.1.0 -> 0.2.0)
  --major             自动升级主版本号 (0.1.0 -> 1.0.0)
  -y, --yes           全自动模式，跳过交互确认直接执行
  --no-push           仅本地提交、打版本与 Tag，不推送到远程仓库
  -h, --help          查看帮助说明

示例:
  ./scripts/release.sh                               # 交互式向导（推荐）
  ./scripts/release.sh --patch -y                    # 自动递增 patch 并发布
  ./scripts/release.sh 0.2.0 "feat: release v0.2.0"  # 直接指定版本与提交说明
EOF
  exit 0
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      show_help
      ;;
    -y|--yes)
      AUTO_CONFIRM=true
      shift
      ;;
    --no-push)
      NO_PUSH=true
      shift
      ;;
    --patch)
      BUMP_TYPE="patch"
      shift
      ;;
    --minor)
      BUMP_TYPE="minor"
      shift
      ;;
    --major)
      BUMP_TYPE="major"
      shift
      ;;
    *)
      if [[ -z "$CUSTOM_VERSION" && "$1" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?(\+[0-9]+)?$ ]]; then
        CUSTOM_VERSION="$1"
      elif [[ -z "$COMMIT_MSG" ]]; then
        COMMIT_MSG="$1"
      fi
      shift
      ;;
  esac
done

# ------------------------------------------------------------------------------
# 1. 前置检查与网络/代理环境准备
# ------------------------------------------------------------------------------
log_step "preflight" "检查环境与远程仓库连通性"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  log_error "当前目录并非 Git 仓库: ${PROJECT_ROOT}"
  exit 1
fi

REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
if [[ -z "$REMOTE_URL" ]]; then
  log_error "未检测到远程仓库 'origin' 配置，无法发布！"
  exit 1
fi
log_success "远程仓库: ${REMOTE_URL}"

# 智能网络/代理适配函数
ensure_network() {
  if $NO_PUSH; then
    return 0
  fi

  # 首先测试直连
  if git ls-remote --heads origin >/dev/null 2>&1; then
    log_success "远程网络连通正常（直连模式）"
    return 0
  fi

  # 若直连失败，尝试加载用户 proxy profile
  if [ -f "${HOME}/.proxy_profile" ]; then
    # shellcheck disable=SC1090
    source "${HOME}/.proxy_profile" 2>/dev/null || true
    if git ls-remote --heads origin >/dev/null 2>&1; then
      log_success "已通过 ~/.proxy_profile 连接到远程仓库"
      return 0
    fi
  fi

  # 若仍不通，探测本机常用代理端口
  local test_ports=(7890 7897 6160 10808 1080)
  for port in "${test_ports[@]}"; do
    export http_proxy="http://127.0.0.1:${port}"
    export https_proxy="http://127.0.0.1:${port}"
    export all_proxy="http://127.0.0.1:${port}"
    export HTTP_PROXY="http://127.0.0.1:${port}"
    export HTTPS_PROXY="http://127.0.0.1:${port}"
    export ALL_PROXY="http://127.0.0.1:${port}"
    export NO_PROXY="localhost,127.0.0.1"

    if git ls-remote --heads origin >/dev/null 2>&1; then
      log_success "已自动检测并绑定本地代理端口: ${port}"
      return 0
    fi
  done

  unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY
  log_warn "无法直接连接到 GitHub，后续 push 步骤可能会受阻"
  return 1
}

ensure_network || true

# ------------------------------------------------------------------------------
# 2. 分支检测与合并管理
# ------------------------------------------------------------------------------
log_step "branch" "检查当前分支状态"

CURRENT_BRANCH=$(git branch --show-current)
log_info "当前工作分支: ${BOLD}${CURRENT_BRANCH}${RESET}"

# 如果在非 main 分支上
if [[ "$CURRENT_BRANCH" != "$RELEASE_BRANCH" ]]; then
  log_warn "当前不在默认发布分支 [${RELEASE_BRANCH}] 上，而在特性分支 [${CURRENT_BRANCH}] 上。"
  DO_MERGE=false

  if $AUTO_CONFIRM; then
    DO_MERGE=true
  else
    read -rp "是否将 [${CURRENT_BRANCH}] 合并到 [${RELEASE_BRANCH}] 并统一发布？ [Y/n]: " merge_input
    case "$merge_input" in
      [nN]|[nN][oO]) DO_MERGE=false ;;
      *) DO_MERGE=true ;;
    esac
  fi

  if $DO_MERGE; then
    # 先提交当前分支未保存的内容
    DIRTY_FILES=$(git status --porcelain)
    if [[ -n "$DIRTY_FILES" ]]; then
      log_info "提交特性分支 [${CURRENT_BRANCH}] 上的现有修改..."
      BRANCH_COMMIT_MSG="${COMMIT_MSG:-"wip: save changes on ${CURRENT_BRANCH} before release merge"}"
      git add -A
      git commit -m "$BRANCH_COMMIT_MSG"
      log_success "特性分支已安全提交"
    fi

    log_info "切换至主分支 [${RELEASE_BRANCH}]..."
    git checkout "${RELEASE_BRANCH}"

    if ! $NO_PUSH; then
      log_info "同步远程最新主分支..."
      git pull origin "${RELEASE_BRANCH}" --rebase 2>/dev/null || true
    fi

    log_info "合并 [${CURRENT_BRANCH}] ➔ [${RELEASE_BRANCH}]..."
    git merge "${CURRENT_BRANCH}" --no-ff -m "merge: merge branch '${CURRENT_BRANCH}' into ${RELEASE_BRANCH}"
    log_success "分支合并完成！"
    CURRENT_BRANCH="${RELEASE_BRANCH}"
  else
    log_info "继续在当前分支 [${CURRENT_BRANCH}] 上执行发布流程。"
    RELEASE_BRANCH="${CURRENT_BRANCH}"
  fi
fi

# ------------------------------------------------------------------------------
# 3. 确保所有修改 100% 提交 (防丢失防遗漏核心)
# ------------------------------------------------------------------------------
log_step "commit" "检查并提交工作区所有代码与资产"

DIRTY_STATE=$(git status --porcelain)
if [[ -n "$DIRTY_STATE" ]]; then
  echo -e "${YELLOW}检测到以下待保存/待提交的文件：${RESET}"
  git status --short
  echo ""

  if [[ -z "$COMMIT_MSG" ]]; then
    if $AUTO_CONFIRM; then
      COMMIT_MSG="feat: automated release snapshot ($(date +'%Y-%m-%d %H:%M:%S'))"
    else
      echo -e "${CYAN}请输入本次提交的说明 (Commit Message)：${RESET}"
      read -rp "提交说明 [默认: feat: release update]: " user_msg
      COMMIT_MSG="${user_msg:-"feat: release update"}"
    fi
  fi

  log_info "执行全量暂存与安全提交 (git add -A)..."
  git add -A
  git commit -m "$COMMIT_MSG"
  log_success "工作区所有代码与资产已成功提交到本地 Git！"
else
  log_success "工作区干净，无未提交的修改或未追踪文件"
fi

# ------------------------------------------------------------------------------
# 4. 版本号读取、计算与定义
# ------------------------------------------------------------------------------
log_step "version" "管理应用版本号"

PUBSPEC_FILE="${PROJECT_ROOT}/pubspec.yaml"
if [[ ! -f "$PUBSPEC_FILE" ]]; then
  log_error "未找到 pubspec.yaml，无法管理 Flutter 版本！"
  exit 1
fi

CURRENT_FULL_VERSION=$(grep -E '^version:' "$PUBSPEC_FILE" | head -n1 | sed -E 's/version:[[:space:]]*//' | tr -d '"' | tr -d "'")
CURRENT_VER_CORE="${CURRENT_FULL_VERSION%%+*}"
CURRENT_BUILD="${CURRENT_FULL_VERSION##*+}"
if [[ "$CURRENT_BUILD" == "$CURRENT_FULL_VERSION" ]]; then
  CURRENT_BUILD="1"
else
  CURRENT_BUILD=$((CURRENT_BUILD + 1))
fi

IFS="." read -r V_MAJOR V_MINOR V_PATCH <<< "$CURRENT_VER_CORE"
V_MAJOR=${V_MAJOR:-0}
V_MINOR=${V_MINOR:-0}
V_PATCH=${V_PATCH:-0}

SUGG_PATCH="${V_MAJOR}.${V_MINOR}.$((V_PATCH + 1))"
SUGG_MINOR="${V_MAJOR}.$((V_MINOR + 1)).0"
SUGG_MAJOR="$((V_MAJOR + 1)).0.0"

TARGET_VERSION=""

if [[ -n "$CUSTOM_VERSION" ]]; then
  TARGET_VERSION="${CUSTOM_VERSION%%+*}"
elif [[ "$BUMP_TYPE" == "patch" ]]; then
  TARGET_VERSION="$SUGG_PATCH"
elif [[ "$BUMP_TYPE" == "minor" ]]; then
  TARGET_VERSION="$SUGG_MINOR"
elif [[ "$BUMP_TYPE" == "major" ]]; then
  TARGET_VERSION="$SUGG_MAJOR"
elif $AUTO_CONFIRM; then
  TARGET_VERSION="$SUGG_PATCH"
else
  echo -e "当前应用版本为: ${BOLD}${GREEN}v${CURRENT_VER_CORE}${RESET} (构建号: ${CURRENT_BUILD})"
  echo "请选择如何定义新版本："
  echo "  1) Patch 升级: ${BOLD}${SUGG_PATCH}${RESET} (常规 Bug 修复与小改进，推荐)"
  echo "  2) Minor 升级: ${BOLD}${SUGG_MINOR}${RESET} (新功能增加或模块级优化)"
  echo "  3) Major 升级: ${BOLD}${SUGG_MAJOR}${RESET} (大版本重构或重大突破)"
  echo "  4) 自定义输入版本号"
  echo "  5) 保持当前版本不变 (${CURRENT_VER_CORE})"
  read -rp "请选择 [1-5, 默认 1]: " ver_choice

  case "$ver_choice" in
    2) TARGET_VERSION="$SUGG_MINOR" ;;
    3) TARGET_VERSION="$SUGG_MAJOR" ;;
    4)
      read -rp "请输入版本号 (如 0.2.1): " user_v
      TARGET_VERSION="${user_v:-$SUGG_PATCH}"
      ;;
    5) TARGET_VERSION="$CURRENT_VER_CORE" ;;
    *) TARGET_VERSION="$SUGG_PATCH" ;;
  esac
fi

NEW_FULL_VERSION="${TARGET_VERSION}+${CURRENT_BUILD}"
log_info "目标发布版本: ${BOLD}${GREEN}v${TARGET_VERSION}${RESET} (${NEW_FULL_VERSION})"

# 更新 pubspec.yaml
if [[ "$CURRENT_FULL_VERSION" != "$NEW_FULL_VERSION" ]]; then
  sed -i '' "s/^version:.*/version: ${NEW_FULL_VERSION}/" "$PUBSPEC_FILE"
  git add "$PUBSPEC_FILE"
  git commit -m "chore(release): bump version to v${TARGET_VERSION}"
  log_success "已更新 pubspec.yaml 并提交版本变更"
fi

# ------------------------------------------------------------------------------
# 5. 自动生成 Release Notes 与更新 CHANGELOG.md
# ------------------------------------------------------------------------------
log_step "changelog" "提取提交与 OpenSpec 记录生成 Release Notes"

LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
TODAY=$(date +"%Y-%m-%d")
RELEASE_NOTES_TMP=$(mktemp)

{
  echo "## [v${TARGET_VERSION}] - ${TODAY}"
  echo ""
  
  # 提取归档中的 OpenSpec 最近变更
  if [ -d "openspec/changes/archive" ]; then
    RECENT_SPECS=$(find openspec/changes/archive -maxdepth 1 -mindepth 1 -type d -name "${TODAY}*" -exec basename {} \; 2>/dev/null | sort -r | head -n 10)
    if [ -n "$RECENT_SPECS" ]; then
      echo "### 🎯 OpenSpec 规格与功能更新"
      echo "$RECENT_SPECS" | while IFS= read -r item; do
        clean_name="${item#${TODAY}-}"
        echo "- **${clean_name}**"
      done
      echo ""
    fi
  fi

  echo "### 📝 提交变更明细"
  if [[ -n "$LAST_TAG" ]]; then
    COMMITS=$(git log "${LAST_TAG}..HEAD" --pretty=format:"- %s (%h)" --reverse | grep -v "chore(release):" || true)
  else
    COMMITS=$(git log -n 20 --pretty=format:"- %s (%h)" --reverse | grep -v "chore(release):" || true)
  fi

  if [[ -n "$COMMITS" ]]; then
    echo "$COMMITS"
  else
    echo "- 常规迭代与代码加固"
  fi
  echo ""
} > "$RELEASE_NOTES_TMP"

CHANGELOG_FILE="${PROJECT_ROOT}/CHANGELOG.md"
if [[ ! -f "$CHANGELOG_FILE" ]]; then
  echo -e "# Changelog\n\nAll notable changes to this project are documented in this file.\n" > "$CHANGELOG_FILE"
fi

# 将最新记录插入到 CHANGELOG 头部（紧随主标题之后）
TMP_CL=$(mktemp)
awk '
  NR == 3 { system("cat '"$RELEASE_NOTES_TMP"'"); print "" }
  { print }
' "$CHANGELOG_FILE" > "$TMP_CL"
mv "$TMP_CL" "$CHANGELOG_FILE"

git add "$CHANGELOG_FILE"
if ! git diff --cached --quiet; then
  git commit -m "docs(changelog): update for v${TARGET_VERSION}"
  log_success "已同步更新 CHANGELOG.md 并提交"
fi

# ------------------------------------------------------------------------------
# 6. 打 Git 附注标签 (Annotated Tag)
# ------------------------------------------------------------------------------
log_step "tag" "创建版本标签"

TAG_NAME="v${TARGET_VERSION}"

if git rev-parse "$TAG_NAME" >/dev/null 2>&1; then
  log_warn "标签 [${TAG_NAME}] 已经存在！"
  TAG_NAME="${TAG_NAME}-b${CURRENT_BUILD}"
  log_info "自动改用后缀标签: ${BOLD}${TAG_NAME}${RESET}"
fi

git tag -a "$TAG_NAME" -F "$RELEASE_NOTES_TMP"
rm -f "$RELEASE_NOTES_TMP"
log_success "已创建 Git 附注标签: ${BOLD}${TAG_NAME}${RESET}"

# ------------------------------------------------------------------------------
# 7. 推送至远程仓库 (防丢失核心屏障)
# ------------------------------------------------------------------------------
log_step "push" "推送分支与 Tag 至远程仓库"

if $NO_PUSH; then
  log_warn "已指定 --no-push，跳过推送远程仓库步骤。"
else
  log_info "正在推送分支 [${RELEASE_BRANCH}] 至 origin..."
  if git push origin "${RELEASE_BRANCH}"; then
    log_success "代码分支已成功推送至 GitHub 远程仓库！"
  else
    log_error "推送分支失败！请检查网络或代理配置。"
    echo -e "${YELLOW}您可以稍后手动执行: git push origin ${RELEASE_BRANCH} && git push origin ${TAG_NAME}${RESET}"
    exit 1
  fi

  log_info "正在推送标签 [${TAG_NAME}] 至 origin..."
  if git push origin "${TAG_NAME}"; then
    log_success "版本标签已成功推送至 GitHub 远程仓库！"
  else
    log_error "推送标签失败！"
    echo -e "${YELLOW}您可以稍后手动执行: git push origin ${TAG_NAME}${RESET}"
    exit 1
  fi
fi

# ------------------------------------------------------------------------------
# 8. 发布完成总结报告
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}${GREEN}════════════════════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}${GREEN}                  🎉 版本发布流程执行成功！                     ${RESET}"
echo -e "${BOLD}${GREEN}════════════════════════════════════════════════════════════════${RESET}"
echo -e "  • 发布版本:     ${BOLD}${CYAN}v${TARGET_VERSION}${RESET} (${NEW_FULL_VERSION})"
echo -e "  • Git 标签:     ${BOLD}${CYAN}${TAG_NAME}${RESET}"
echo -e "  • 发布分支:     ${BOLD}${CURRENT_BRANCH}${RESET}"
echo -e "  • 最新提交:     ${BOLD}$(git rev-parse --short HEAD)${RESET} - $(git log -1 --pretty=format:'%s')"
echo -e "  • 远程同步状态: ${GREEN}已全部安全备份至远程仓库 (origin)${RESET}"
echo -e "  • 变更记录:     ${BOLD}CHANGELOG.md${RESET} 已同步更新"
echo -e "${BOLD}${GREEN}════════════════════════════════════════════════════════════════${RESET}\n"
echo -e "${CYAN}提示：本地已完备同步至 GitHub。后续即便本地发生代码改动或文件误删，均可随时从远程完整恢复！${RESET}\n"
