#!/usr/bin/env bash
# 静态主题 token 守卫 —— 供本地 pre-push 使用。
#
# CI 已通过 .github/workflows/build-release.yml 的 theme-token-guard job 接入；
# 本地执行 `tool/install-pre-push-hook.sh` 后会挂到 .git/hooks/pre-push。
#
# 存量 671 处已由 clean-up-tool-page-static-theme-tokens 清零，现为阻断式：
# 任何新增的静态 token 引用都会阻止 push。
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

tool/check_no_static_theme_tokens.sh
