#!/usr/bin/env bash
# 🍣 一鍵準備：chmod + 印出要貼進 settings.json 的 JSON 片段
# 不會自動改你的 settings.json，貼上動作留給你自己。
#
#   ./install.sh          印出說明與片段
#   ./install.sh --json   只印 JSON 物件（給想用 jq 自己合併的人）

set -e
export LC_ALL=C   # 下面的 [A-Za-z…] 要照 byte 比對，不能跟著使用者的定序走

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/sushi-statusline.sh"
DEMO="$HERE/demo.sh"

if [ ! -f "$SCRIPT" ]; then
  echo "❌ 找不到 sushi-statusline.sh，確認你在正確的資料夾執行" >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "❌ 需要 jq（status line 本身也要用）。macOS：brew install jq；Debian / Ubuntu：sudo apt install jq" >&2
  exit 1
fi

chmod +x "$SCRIPT" "$DEMO" 2>/dev/null || true

# Claude Code 會把 command 整串交給 shell 執行，所以路徑裡有空白或特殊字元時
# 要先包成單引號字串（' 本身寫成 '\''），再交給 jq 做 JSON 跳脫。
# 取代用的字串先放進變數：直接在 ${…//…/…} 裡寫反斜線，各版 bash 的解讀不一樣。
SQ="'"
SQ_ESCAPED="'\\''"
case $SCRIPT in
  *[!A-Za-z0-9_./-]*) COMMAND="'${SCRIPT//$SQ/$SQ_ESCAPED}'" ;;
  *) COMMAND=$SCRIPT ;;
esac
SNIPPET=$(jq -n --arg command "$COMMAND" \
  '{statusLine: {type: "command", command: $command, refreshInterval: 1}}')

if [ "${1:-}" = "--json" ]; then
  printf '%s\n' "$SNIPPET"
  exit 0
fi

# 給人複製的片段：只有 "statusLine" 這個 key，整段往右縮兩格
# （heredoc 裡不會解讀 $'\n'，所以先在外面把每個換行換成「換行 + 兩格」）
NL=$'\n'
FRAGMENT=$(printf '%s' "$SNIPPET" | jq '.statusLine')
FRAGMENT=${FRAGMENT//$NL/$NL  }

cat <<EOF

🍣 準備完成！

請把以下片段加入 ~/.claude/settings.json 的最上層（若已有其他欄位，只要合併 "statusLine" key）：

  "statusLine": $FRAGMENT

步驟：
  1. 打開 ~/.claude/settings.json
  2. 貼入上面片段（注意跟現有內容間的逗號）
  3. 存檔
  4. 重啟 Claude Code session

想先看效果？
  $DEMO

EOF
