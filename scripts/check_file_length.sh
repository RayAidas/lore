#!/usr/bin/env bash
# 检测 Lore 源码文件是否过长：超过阈值的文件直接列出并报错退出。
# 无状态、不生成任何文件，也不接入 test.sh —— 需要时手动跑一次看看债务。
# 用法:
#   bash scripts/check_file_length.sh                # 默认阈值 1000 行
#   MAX_LINES=800 bash scripts/check_file_length.sh  # 临时调整阈值
#
# 仅扫描 apps/ 与 packages/ 下的源文件（仓库根的 .dart 不计入）。
# 白名单直接写在下方的 WHITELIST 数组里，列在其中的文件豁免检测。
# 不纳入统计：test/、build/、.dart_tool/，以及 *.g.dart / *.freezed.dart / *.mocks.dart 生成文件。
set -uo pipefail

cd "$(dirname "$0")/.."

MAX_LINES="${MAX_LINES:-1000}"
# MAX_LINES 必须是正整数，否则下方 [ "$count" -gt "$MAX_LINES" ] 会因非数值报错并静默丢文件。
[[ "$MAX_LINES" =~ ^[0-9]+$ ]] || { echo "✗ MAX_LINES 必须是正整数：${MAX_LINES}" >&2; exit 2; }

# 白名单：这些文件豁免长度检测（确实不便拆分、经评审认可）。
# 每行一个路径，必须以 apps/ 或 packages/ 开头、与 find 输出完全一致
# （无前导 ./、非绝对路径）；含空格的路径用双引号包起来。
WHITELIST=(
  # 示例（按需增删，删去行首 # 即生效）：
  # "apps/lore_app/lib/features/some/big_but_legitimate.dart"
)

# 该文件是否在白名单中。兼容 bash 3.2：空数组在 set -u 下须先判长度再展开。
is_whitelisted() {
  [ ${#WHITELIST[@]} -eq 0 ] && return 1
  local w
  for w in "${WHITELIST[@]}"; do
    [ "$w" = "$1" ] && return 0
  done
  return 1
}

# 收集文件列表。find 失败（apps/packages 缺失或不可读）必须显式报错——
# 否则空输入会让脚本误报"全部在控"。pipefail 下命令替换会透传 find 的非零退出码。
if ! file_list="$(find apps packages \
    -name '*.dart' \
    -not -path '*/test/*' \
    -not -path '*/build/*' \
    -not -path '*/.dart_tool/*' \
    -not -name '*.g.dart' \
    -not -name '*.freezed.dart' \
    -not -name '*.mocks.dart' \
    -type f | sort)"; then
  echo "✗ 扫描源文件失败：请确认 apps/ 与 packages/ 存在且可读。" >&2
  exit 2
fi

oversized=()
while IFS= read -r f; do
  [ -z "$f" ] && continue
  is_whitelisted "$f" && continue
  # 用 awk NR 而非 wc -l：末尾无换行的文件 wc 会少算一行。
  count="$(awk 'END { print NR }' "$f")"
  [[ "$count" =~ ^[0-9]+$ ]] || { echo "✗ 无法统计行数：$f" >&2; continue; }
  [ "$count" -gt "$MAX_LINES" ] && oversized+=("${count}  ${f}")
done <<< "$file_list"

if [ "${#oversized[@]}" -gt 0 ]; then
  echo "✗ 以下文件超过 ${MAX_LINES} 行上限："
  printf '  %s\n' "${oversized[@]}"
  echo "提示：拆分大文件以降低单文件复杂度，或必要时用 MAX_LINES 调整阈值。"
  exit 1
fi

echo "✓ 文件长度全部在控（阈值 ${MAX_LINES} 行）。"
exit 0
