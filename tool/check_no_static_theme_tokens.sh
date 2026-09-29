#!/usr/bin/env bash
# 禁止在 widget 代码中引用静态深色主题 token。
#
# 背景：AppTheme 的 bgCard / textPrimary / borderSubtle 等色值是编译期常量，
# 直接引用会绕过 Flutter 的 ThemeExtension 解析，导致浅色模式下工具页大面积
# 渲染成深色（深灰卡片叠白底、浅灰文字落白卡、深色边框在白底上不可见）。
#
# 规则：lib/ 下除 lib/theme/app_theme.dart 外，不得出现
#       AppTheme.<颜色 token> 引用。app_theme.dart 是 light/dark 两套 preset
#       的定义源，是唯一合法的引用点；widget 层一律走 BuildContext 扩展
#       （context.bgCard / context.colors.bgCard）。
#
# 覆盖三类 token：中性表面色、强调色（accent*）、语义色（success/warning/
# error/info，含 *Subtle）。强调色与语义色虽不是"表面色"，但同样是浅深共用的
# static const，浅色下的对比度不达标且无法靠改 widget 修好——必须由
# app_theme.dart 提供按模式取值的 token。
#
# 用法：
#   tool/check_no_static_theme_tokens.sh            # 命中即退出码 1
#   WARN=1 tool/check_no_static_theme_tokens.sh     # 仅打印计数，退出码 0
#
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WHITELIST="lib/theme/app_theme.dart"

# 三类都不许出现在 widget 层：
#   1. 中性表面色  bg* / text* / border*
#   2. 强调色      accent / accentLight / accentDark / accentSubtle
#   3. 语义色      success / warning / error / info（含各自 *Subtle）
# 强调色与语义色同为 static const、浅深共用一组值，且都没有定义"实底之上的
# 前景色"角色，因此浅色模式下既有白字落浅底（对比度 1.10），也有 500 档语义色
# 文字压浅底（success 仅 1.85）。二者与中性色同源同病，故同规则。
TOKEN_RE='AppTheme\.(bgWindow|bgActivityBar|bgSidebar|bgContent|bgCard|bgCardHover|bgInput|bgSelected|borderSubtle|borderStrong|textPrimary|textSecondary|textTertiary|textDisabled|accent|accentLight|accentDark|accentSubtle|success|successSubtle|warning|warningSubtle|error|errorSubtle|info|infoSubtle)'

# 注意：macOS 自带 bash 3.2 无 mapfile，这里用临时文件避开
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

rg -n --no-heading -e "$TOKEN_RE" "$ROOT/lib" \
  -g '*.dart' -g "!$WHITELIST" 2>/dev/null \
  | sed "s|^$ROOT/||" > "$TMP"

COUNT="$(grep -c '' "$TMP" || true)"

# 反向规则：抓"把前景/实底值直接当底色、没做半透明派生"的误映射签名。
# 历史事故：`unify-accent-tokens-and-fix-light-mode-contrast` 的批量迁移漏了
# `*Subtle`（12% 半透明底）这个第三角色，导致底色与文字同色——用户看到
# "只有一个色块、看不见文字"。
#
# 正确形态是 `context.<sem>Text.withValues(alpha: 0x1F / 255)`（淡底深字）；
# 下面这条正则专门抓**没带半透明系数**的直接用法。
# 只抓 Text——Solid 作底色是合法的实底按钮（配 onAccentSolid 白字），
# 而 Text 作底色几乎必然是 wash 角色丢失。
# 判据：Text 出现在**明确的底色变量名**（backgroundColor:/bg =/badgeBg =）且
# 同一行没有 withValues/withAlpha —— 有半透明系数的是正确 wash，没有的就是角色丢失。
#
# ⚠️ 覆盖盲区（有意接受）：`color: context.xText` 这一形态无法与"文字前景"区分，
# 单靠正则做不到。真正的守卫是 test/theme_subtle_role_test.dart 的渲染级断言，
# 那里能取到实际生效的底色与文字色。此处只兜"变量名已经自证是底色"的情形。
WASH_SUSPECT="$(rg -n --no-heading -e '(backgroundColor|bg|badgeBg)\s*[:=]\s*(?:[\w.]+ \? )?context\.(success|warning|error|info)Text\b' "$ROOT/lib" -g '*.dart' -g "!$WHITELIST" 2>/dev/null | grep -v 'withValues\|withAlpha' | sed "s|^$ROOT/||" | head -40)"
if [[ -n "$WASH_SUSPECT" ]]; then
  echo "⚠ 前景/实底 token 被直接当作底色（缺半透明派生，可能是 wash 角色丢失）：" >&2
  printf '%s\n' "$WASH_SUSPECT" >&2
fi

if [[ ${WARN:-0} == 1 ]]; then
  echo "静态主题 token 引用：$COUNT 处（warning 级，不阻断）"
  [[ $COUNT -gt 0 ]] && cat "$TMP"
  exit 0
fi

if [[ "$COUNT" -eq 0 ]]; then
  echo "✓ 静态主题 token 引用：0 处"
  exit 0
fi

echo "✗ 发现 $COUNT 处静态主题 token 引用（应改为 context.<token>）：" >&2
cat "$TMP" >&2
exit 1
