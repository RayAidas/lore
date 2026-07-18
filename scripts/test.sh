#!/usr/bin/env bash
# 跑整个 Lore workspace 的测试与静态分析。
# 用法: bash scripts/test.sh   （或 ./scripts/test.sh）
#
# Flutter workspace 不会递归跑子包测试，本脚本依次跑每个有测试的包。
# 任一包失败也会继续跑完其余包，最后汇总，方便一次看全。
set -uo pipefail

cd "$(dirname "$0")/.."

command -v flutter >/dev/null 2>&1 || {
  echo "✗ 未找到 flutter，请确认 Flutter 已加入 PATH。"
  exit 127
}

# flutter_tester 走回环连接，必须绕过本地代理（若 shell 里有 http_proxy）。
export NO_PROXY="127.0.0.1,localhost,::1"
export no_proxy="127.0.0.1,localhost,::1"

fail=0
section() {
  echo ""
  echo "=== $1 ==="
}
run() {
  local label="$1"; shift
  if "$@"; then
    echo "✓ $label 通过"
  else
    echo "✗ $label 失败"
    fail=1
  fi
}

section "静态分析"
run "flutter analyze" flutter analyze

section "纯 Dart 包"
run "lore_domain (dart test)" sh -c 'cd packages/lore_domain && dart test'
run "lore_application (dart test)" sh -c 'cd packages/lore_application && dart test'
run "lore_storage (dart test)" sh -c 'cd packages/lore_storage && dart test'

section "Flutter 包"
run "lore_ui (flutter test)" sh -c 'cd packages/lore_ui && flutter test'
run "lore_editor (flutter test)" sh -c 'cd packages/lore_editor && flutter test'
run "lore_platform_adapters (flutter test)" sh -c 'cd packages/lore_platform_adapters && flutter test'
run "lore_app (flutter test)" sh -c 'cd apps/lore_app && flutter test'

echo ""
if [ "$fail" -eq 0 ]; then
  echo "全部通过 ✅"
else
  echo "存在失败 ❌（见上方 ✗ 标记）"
fi
exit "$fail"
