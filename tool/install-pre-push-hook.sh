#!/usr/bin/env bash
# 把静态主题 token 守卫挂到 .git/hooks/pre-push。
# 幂等：重复执行只会覆盖同一段标记之间的内容。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$ROOT/.git/hooks/pre-push"
BEGIN="# >>> theme-token-guard >>>"
END="# <<< theme-token-guard <<<"

mkdir -p "$ROOT/.git/hooks"

if [[ -f "$HOOK" ]]; then
  # 去掉旧的标记段
  TMP="$(mktemp)"
  if grep -qF "$BEGIN" "$HOOK"; then
    sed "/$BEGIN/,/$END/d" "$HOOK" > "$TMP"
  else
    cat "$HOOK" > "$TMP"
  fi
  cat "$TMP" > "$HOOK"
  rm -f "$TMP"
fi

cat >> "$HOOK" <<EOF
$BEGIN
# 由 tool/install-pre-push-hook.sh 写入；删除本段即可卸载。
bash "\$(git rev-parse --show-toplevel)/tool/pre-push-theme-guard.sh"
$END
EOF

chmod +x "$HOOK"
echo "已安装 pre-push 守卫：$HOOK"
echo "当前为 warning 级，不会阻断 push。"
