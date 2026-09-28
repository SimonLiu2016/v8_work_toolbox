#!/bin/bash

# V8WorkToolbox 本地 macOS 一键部署脚本
#
# 把人工摸索出的部署流程固化为一条命令：清理 → 构建 → 注入 mihomo →
# 重新 ad-hoc 签名 → 优雅退出旧实例 → 替换 → 校验 → 启动。
#
# 与 scripts/build_installer.sh 的分工：后者产出分发包（DMG/ZIP）给用户装；
# 本脚本只做「本机构建并替换 /Applications 下的应用」，不产出安装包。
#
# 任一步失败即整体中止，不留下半部署状态。
#
# 用法：
#   ./scripts/deploy_local.sh              # 完整部署（含 flutter clean）
#   ./scripts/deploy_local.sh --skip-clean # 跳过 clean（仅调试用，见下方警告）
#
# ⚠️ --skip-clean 警告：flutter clean 是规避「增量构建残留失效 framework
#    seal → macOS 拒绝访问 Keychain → DEK 走文件兜底生成新 DEK → 旧密文
#    全部解不开」的唯一可靠手段。跳过它意味着用数据安全性换几分钟构建时间。

set -euo pipefail

# ---------------------------------------------------------------------------
# 配置
# ---------------------------------------------------------------------------
APP_NAME="V8WorkToolbox"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_DIR="/Applications"
BUNDLE_ID="com.v8en.V8WorkToolbox"

# 部署目标。绝对路径，供 rm -rf 前的安全断言使用。
TARGET_APP="$INSTALL_DIR/$APP_NAME.app"

# 构建产物
BUILD_PRODUCTS="$PROJECT_DIR/build/macos/Build/Products/Release"
SOURCE_APP="$BUILD_PRODUCTS/$APP_NAME.app"

# Dart AOT 快照 = 真正的应用代码身份。
# 不能用 Contents/MacOS/V8WorkToolbox 判断——那是瘦启动器，跨构建可能不变。
AOT_SNAPSHOT="Contents/Frameworks/App.framework/Versions/A/App"

# mihomo 二进制。它在 .gitignore 中，flutter clean 会删掉，必须从别处恢复。
MIHOMO_REL="Contents/Resources/mihomo"
MIHOMO_CURRENT="$TARGET_APP/$MIHOMO_REL"
MIHOMO_SOURCE="$PROJECT_DIR/macos/Runner/Resources/mihomo"

SKIP_CLEAN=0
if [ "${1:-}" = "--skip-clean" ]; then
    SKIP_CLEAN=1
    shift
fi

# ---------------------------------------------------------------------------
# 颜色与日志
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

step() { echo -e "\n${BLUE}▶ [$1]${NC} $2"; }
ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}!${NC} $1"; }
die()  { echo -e "\n${RED}✗ 部署中止@[$1]${NC} $2" >&2; exit 1; }

md5_of() { md5 -q "$1" 2>/dev/null || echo ""; }

# ---------------------------------------------------------------------------
# 1. preflight
# ---------------------------------------------------------------------------
preflight() {
    step "preflight" "校验环境"

    [ "$(uname -s)" = "Darwin" ] || die preflight "仅支持 macOS"
    command -v flutter >/dev/null 2>&1 || die preflight "flutter 不在 PATH 中"
    command -v ditto   >/dev/null 2>&1 || die preflight "ditto 不可用"
    command -v codesign >/dev/null 2>&1 || die preflight "codesign 不可用"

    # 防呆：TARGET_APP 必须是预期的绝对路径，否则绝不执行后续的 rm -rf。
    # 变量一旦被误改，删掉的就是别的应用。
    case "$TARGET_APP" in
        "$INSTALL_DIR/$APP_NAME.app") ;;
        *) die preflight "部署目标路径异常: $TARGET_APP" ;;
    esac

    ok "项目目录: $PROJECT_DIR"
    ok "部署目标: $TARGET_APP"
    ok "flutter: $(flutter --version 2>/dev/null | head -n1)"
}

# ---------------------------------------------------------------------------
# 2. clean + build
# ---------------------------------------------------------------------------
build() {
    cd "$PROJECT_DIR"

    if [ "$SKIP_CLEAN" -eq 1 ]; then
        warn "已跳过 flutter clean——seal 失效风险自负"
    else
        step "clean" "清理构建产物（规避增量构建残留失效 seal）"
        flutter clean >/dev/null 2>&1
        ok "已清理"
    fi

    step "build" "release 构建"
    # 失败即停：此时还未触碰 /Applications，旧应用完好可用。
    if ! flutter build macos --release > /tmp/deploy_build.log 2>&1; then
        tail -n 30 /tmp/deploy_build.log >&2
        die build "flutter build 失败（完整日志: /tmp/deploy_build.log）"
    fi

    [ -d "$SOURCE_APP" ] || die build "构建产物不存在: $SOURCE_APP"
    ok "构建完成: $SOURCE_APP"
}

# ---------------------------------------------------------------------------
# 3. inject_mihomo
# ---------------------------------------------------------------------------
inject_mihomo() {
    step "inject_mihomo" "注入 mihomo 二进制（构建系统不产出它）"

    local src=""
    if [ -f "$MIHOMO_CURRENT" ]; then
        # 首选上一版已部署 bundle：那是"当前正在跑的版本"
        src="$MIHOMO_CURRENT"
        ok "来源: 已部署 bundle"
    elif [ -f "$MIHOMO_SOURCE" ]; then
        src="$MIHOMO_SOURCE"
        warn "已部署 bundle 中无 mihomo，回落源码目录"
    else
        die inject_mihomo "两处都找不到 mihomo：
   $MIHOMO_CURRENT
   $MIHOMO_SOURCE
   请手动放置后重试。"
    fi

    local dst="$SOURCE_APP/$MIHOMO_REL"
    mkdir -p "$(dirname "$dst")"
    cp -p "$src" "$dst"
    chmod 755 "$dst"

    # 拷贝完整性
    local a b
    a="$(md5_of "$src")"
    b="$(md5_of "$dst")"
    [ -n "$a" ] && [ "$a" = "$b" ] || die inject_mihomo "mihomo 拷贝校验失败"
    ok "mihomo 已注入 (md5 ${a:0:8}…)"
}

# ---------------------------------------------------------------------------
# 4. resign
# ---------------------------------------------------------------------------
resign() {
    step "resign" "重新 ad-hoc 签名"

    # 顺序不可交换：往已签名 bundle 加文件会破坏 seal。必须先注入再签名。
    codesign --remove-signature "$SOURCE_APP" 2>/dev/null || true
    codesign -s - --force "$SOURCE_APP" \
        || die resign "签名失败"
    codesign -v --strict "$SOURCE_APP" \
        || die resign "签名后 strict 校验失败（seal 不自洽）"
    ok "签名通过 strict 校验"
}

# ---------------------------------------------------------------------------
# 5. stop_running
# ---------------------------------------------------------------------------
stop_running() {
    step "stop_running" "退出正在运行的旧实例"

    local main_pids
    # 只匹配本应用的可执行文件路径，不匹配 mihomo 子进程。
    main_pids="$(pgrep -f "$TARGET_APP/Contents/MacOS/$APP_NAME" || true)"

    if [ -z "$main_pids" ]; then
        ok "无运行中的实例"
        return
    fi

    local pid
    for pid in $main_pids; do
        # SIGTERM：应用已注册信号监听，会走优雅退出清理 mihomo 子进程。
        kill -TERM "$pid" 2>/dev/null || true
    done
    ok "已发送 SIGTERM: $(echo $main_pids | tr '\n' ' ')"

    # 给优雅退出留时间（MihomoProcessManager.stop 内部等最多 3 秒）
    local waited=0
    while [ "$waited" -lt 8 ]; do
        if ! pgrep -f "$TARGET_APP/Contents/MacOS/$APP_NAME" >/dev/null 2>&1; then
            ok "旧实例已退出（${waited}s）"
            return
        fi
        sleep 1
        waited=$((waited + 1))
    done

    warn "旧实例 8s 未退出，升级为 SIGKILL"
    for pid in $main_pids; do
        kill -KILL "$pid" 2>/dev/null || true
    done
    sleep 1
}

# ---------------------------------------------------------------------------
# 6. cleanup_orphans（兜底，仅在有残留时执行）
# ---------------------------------------------------------------------------
cleanup_orphans() {
    step "cleanup_orphans" "清理孤儿子进程（兜底）"

    # 精确匹配本应用 bundle 下的完整路径。
    # 绝不能用裸 `mihomo` 匹配——本机可能同时跑着 Clash Verge 的
    # verge-mihomo，裸匹配会误杀。
    local orphans
    orphans="$(pgrep -f "$TARGET_APP/$MIHOMO_REL" || true)"

    if [ -z "$orphans" ]; then
        ok "无残留 mihomo"
        return
    fi

    warn "发现未随主进程退出的 mihomo: $(echo $orphans | tr '\n' ' ')"
    warn "（意味着优雅退出未生效，本次为兜底清理）"
    local pid
    for pid in $orphans; do
        kill -TERM "$pid" 2>/dev/null || true
    done
    sleep 2
    for pid in $orphans; do
        kill -KILL "$pid" 2>/dev/null || true
    done
    ok "已清理"
}

# ---------------------------------------------------------------------------
# 7. replace
# ---------------------------------------------------------------------------
replace() {
    step "replace" "替换已部署应用"

    # 记录旧 AOT 快照哈希：部署后比对，用于确认代码真的更新了。
    local old_hash=""
    if [ -f "$TARGET_APP/$AOT_SNAPSHOT" ]; then
        old_hash="$(md5_of "$TARGET_APP/$AOT_SNAPSHOT")"
        ok "旧 AOT 快照: $old_hash"
    else
        warn "尚未安装过（首次部署）"
    fi

    # ditto 是「合并」语义：直接覆盖会让新 bundle 残留旧 bundle 独有的文件
    # （kernel_blob.bin / vm_snapshot_data / debug.dylib 等），进而导致
    # strict 校验失败。必须先删干净。
    rm -rf "$TARGET_APP"
    ditto "$SOURCE_APP" "$TARGET_APP" || die replace "ditto 失败"

    ok "已替换: $TARGET_APP"
    echo "$old_hash" > /tmp/deploy_prev_aot.txt
}

# ---------------------------------------------------------------------------
# 8. verify
# ---------------------------------------------------------------------------
verify() {
    step "verify" "部署后校验"

    [ -d "$TARGET_APP" ] || die verify "部署后 bundle 不存在"
    [ -f "$TARGET_APP/$AOT_SNAPSHOT" ] || die verify "AOT 快照缺失"
    [ -f "$TARGET_APP/$MIHOMO_REL" ] || die verify "mihomo 缺失"

    codesign -v --strict "$TARGET_APP" \
        || die verify "部署后 strict 签名校验失败——不启动应用"

    local new_hash old_hash
    new_hash="$(md5_of "$TARGET_APP/$AOT_SNAPSHOT")"
    old_hash="$(cat /tmp/deploy_prev_aot.txt 2>/dev/null || echo "")"

    ok "新 AOT 快照: $new_hash"
    if [ -n "$old_hash" ] && [ "$old_hash" = "$new_hash" ]; then
        warn "新 AOT 快照与旧版相同——若本次改动应影响 Dart 代码，请检查构建"
    elif [ -n "$old_hash" ]; then
        ok "AOT 快照已变化（代码确实更新）"
    fi

    ok "strict 签名校验通过"
}

# ---------------------------------------------------------------------------
# 9. launch
# ---------------------------------------------------------------------------
launch() {
    step "launch" "启动应用"

    open -a "$TARGET_APP" || die launch "open 失败"

    local waited=0
    while [ "$waited" -lt 15 ]; do
        if pgrep -f "$TARGET_APP/Contents/MacOS/$APP_NAME" >/dev/null 2>&1; then
            ok "应用已启动并存活（${waited}s）"
            echo -e "\n${GREEN}════════════════════════════════════════${NC}"
            echo -e "${GREEN}  部署完成${NC}"
            echo -e "${GREEN}════════════════════════════════════════${NC}"
            echo "  应用: $TARGET_APP"
            echo "  构建: $SOURCE_APP"
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
    done

    die launch "应用 15s 内未存活——bundle 已部署但未启动，请手动检查"
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
    echo -e "${BLUE}V8WorkToolbox 本地部署${NC}"
    echo "  开始时间: $(date '+%Y-%m-%d %H:%M:%S')"

    preflight
    build
    inject_mihomo
    resign
    stop_running
    cleanup_orphans
    replace
    verify
    launch

    echo "  结束时间: $(date '+%Y-%m-%d %H:%M:%S')"
}

main "$@"
