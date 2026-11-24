#!/usr/bin/env bash
# 🍣 本機預覽輸送帶，不需要動 Claude Code 設定。
# 每秒跑一次 sushi-statusline.sh，看帶子滾動效果。Ctrl+C 離開。

SCRIPT="$(cd "$(dirname "$0")" && pwd)/sushi-statusline.sh"

if [ ! -f "$SCRIPT" ]; then
  echo "❌ sushi-statusline.sh 不在同一個資料夾" >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "❌ 需要 jq（macOS：brew install jq；Debian / Ubuntu：sudo apt install jq）" >&2
  exit 1
fi

# 用 jq 組假資料：$PWD 裡有引號或反斜線也不會組出壞掉的 JSON
FAKE_INPUT=$(jq -n --arg cwd "$PWD" '{
  cwd: $cwd,
  model: {display_name: "Demo"},
  cost: {total_cost_usd: 0.1234},
  context_window: {context_window_size: 200000, used_percentage: 26},
  rate_limits: {
    five_hour: {used_percentage: 12, resets_at: (now + 7200 | floor)},
    seven_day: {used_percentage: 34}
  }
}')

# Claude Code 會把終端機寬度放進 COLUMNS 交給 status line；這裡 demo 自己接著終端機，直接問就好
term_cols() { tput cols 2>/dev/null || echo 80; }

trap 'printf "\033[?25h\n\nbye 🍣\n"; exit 0' INT TERM

printf '═══ 🍣 Sushi Belt Preview (Ctrl+C 離開) ═══\n\n'
printf '\033[?25l'             # 藏游標，畫面比較乾淨（離開時 trap 會還原）

first=1
while true; do
  if [ -z "$first" ]; then
    printf '\033[2A\033[J'     # 上移 2 行並清除到螢幕底，原地更新不閃爍
  fi
  first=
  printf '%s' "$FAKE_INPUT" | COLUMNS=$(term_cols) bash "$SCRIPT"
  sleep 1
done
