#!/usr/bin/env bash
# 🍣 sushi-statusline.sh 的測試
#
#   bash tests/run.sh          # 用 PATH 上的 bash
#   /bin/bash tests/run.sh     # 指定 bash：測試用哪個 bash 跑，主腳本就用哪個 bash 跑
#
# 需要 jq、git、python3。python3 只有測試會用：拿 unicodedata 獨立量「顯示寬度」，
# 不沿用主腳本自己的估算（否則兩邊錯得一樣也看不出來）。
#
# 每個測試都餵受控輸入、檢查真正的輸出：時間用 SUSHI_NOW 釘住、時區釘 UTC，
# PATH 只留主腳本允許 fork 的外部指令（jq git date mkdir mv），多用一個別的就會失敗。

# shellcheck disable=SC2016  # 預期值裡的 💰$0.1234 是字面上的錢字號，不是變數

set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT=${SUSHI_SCRIPT:-$ROOT/sushi-statusline.sh}   # 可指定別份腳本來測（例如故意改壞的版本）

for tool in jq git python3; do
  command -v "$tool" >/dev/null 2>&1 || { echo "測試需要 $tool" >&2; exit 2; }
done

WORK="$(mktemp -d "${TMPDIR:-/tmp}/sushi-test.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/cache" "$WORK/proj"

# ── 受控的 PATH ──────────────────────────────────────────
mkbin() {  # mkbin 目錄 指令...
  local dir=$1 tool path; shift
  mkdir -p "$dir"
  for tool in "$@"; do
    path=$(command -v "$tool") && ln -sf "$path" "$dir/$tool"
  done
}
mkbin "$WORK/bin"      jq git date mkdir mv
mkbin "$WORK/bin-nojq" git date mkdir mv
mkbin "$WORK/bin-gh"   jq git date mkdir mv sleep
# 假的 gh：真的那支要網路和登入。每次呼叫記成一行（參數裡的查詢字串有換行，要壓平），
# 再回傳 --jq 之後會得到的那一行。
{
  printf '#!%s\n' "$BASH"
  cat <<'EOF'
args=$*
printf '%s\n' "${args//$'\n'/ }" >>"$GH_LOG"
[ -n "${GH_STUB_SLEEP:-}" ] && sleep "$GH_STUB_SLEEP"
printf '%s\n' "$GH_STUB_OUT"
EOF
} >"$WORK/bin-gh/gh"
chmod +x "$WORK/bin-gh/gh"
# 假的慢 git：模擬大到 git status 要跑好幾秒的 repo
mkbin "$WORK/bin-slowgit" jq date mkdir mv sleep
cat >"$WORK/bin-slowgit/git" <<'EOF'
#!/bin/sh
echo call >>"$GIT_LOG"
sleep 3
EOF
chmod +x "$WORK/bin-slowgit/git"
START_DIR=$PWD

# ── 執行主腳本 ───────────────────────────────────────────
NOW=1795000000   # 2026-11-18 11:06:40 UTC

sl() {  # sl 'JSON' [VAR=值 ...] → L1 L2 NLINES ERR RC
  local json=$1; shift
  printf '%s' "$json" | env -i PATH="$WORK/bin" TMPDIR="$WORK/cache" TZ=UTC \
    SUSHI_NOW="$NOW" SUSHI_GH=0 "$@" "$BASH" "$SCRIPT" >"$WORK/stdout" 2>"$WORK/stderr"
  RC=$?
  L1=""; L2=""
  { IFS= read -r L1; IFS= read -r L2; } <"$WORK/stdout"
  NLINES=$(wc -l <"$WORK/stdout" | tr -d ' ')
  ERR=$(cat "$WORK/stderr")
}

GH_STUB_OUT='2 1'
ghsl() {  # 同 sl，但開啟 GitHub 數量、PATH 上有假的 gh
  local json=$1; shift
  sl "$json" PATH="$WORK/bin-gh" SUSHI_GH=1 GH_LOG="$WORK/gh.log" GH_STUB_OUT="$GH_STUB_OUT" "$@"
}
wait_for() {  # wait_for 字串 ghsl參數...：背景更新是非同步的，重跑到出現為止（最多約 10 秒）
  local want=$1 i=0; shift
  while [ "$i" -lt 100 ]; do
    ghsl "$@"
    case $L2 in *"$want"*) return 0 ;; esac
    sleep 0.1; i=$((i + 1))
  done
  return 1
}
gh_calls() {  # gh_calls [字串]：假 gh 被呼叫幾次（可只算含某字串的）
  local n=0 line
  [ -f "$WORK/gh.log" ] || { echo 0; return; }
  while IFS= read -r line; do
    case $line in *"${1:-}"*) n=$((n + 1)) ;; esac
  done <"$WORK/gh.log"
  echo "$n"
}

wait_calls() {  # wait_calls 字串 N：等到假 gh 被呼叫滿 N 次（它在背景啟動，什麼時候寫下紀錄看機器快慢）
  local i=0
  while [ "$(gh_calls "$1")" -lt "$2" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
}

# 這份測試裡凡是「等背景的東西」都是等到事件真的發生（有上限），不用固定秒數的 sleep 去賭機器夠快。
# 固定的 sleep 只用在「確認某件事沒有發生」，那種寫法頂多漏抓，不會在慢機器上誤判失敗。

# ── 量測與斷言 ───────────────────────────────────────────
width() {  # 顯示寬度（欄）
  python3 -X utf8 -c '
import sys, unicodedata as u
print(sum(0 if u.combining(c) else 2 if u.east_asian_width(c) in "WF" else 1 for c in sys.argv[1]))' "$1"
}
count() {  # count 字串 子字串 → 出現次數
  local s=$1 sub=$2 rest
  rest=${s//"$sub"/}
  echo $(( (${#s} - ${#rest}) / ${#sub} ))
}

T=""; PASS=0; FAIL=0; SKIP=0
t()     { T=$1; }
ok()    { PASS=$((PASS + 1)); }
no()    { FAIL=$((FAIL + 1)); printf '✗ %s\n    %s\n' "$T" "$1"; }
skip()  { SKIP=$((SKIP + 1)); printf '– 略過：%s（%s）\n' "$T" "$1"; }
eq()    { if [ "$1" = "$2" ]; then ok; else no "預期 [$2]，實際 [$1]"; fi; }
has()   { case $1 in *"$2"*) ok ;; *) no "[$1] 應包含 [$2]" ;; esac; }
hasnt() { case $1 in *"$2"*) no "[$1] 不應包含 [$2]" ;; *) ok ;; esac; }
clean() { eq "$RC" 0; eq "$NLINES" 2; eq "$ERR" ""; }   # 輸出契約：exit 0、剛好兩行、stderr 沒東西

P="$WORK/proj"   # 不是 git repo 的普通資料夾
FULL='{"cwd":"'"$P"'","model":{"display_name":"Opus 4.7"},"cost":{"total_cost_usd":0.1234},
  "context_window":{"context_window_size":200000,"used_percentage":26.4,
    "current_usage":{"input_tokens":1000,"cache_creation_input_tokens":0,"cache_read_input_tokens":50000}},
  "rate_limits":{"five_hour":{"used_percentage":12.4,"resets_at":1795010000},
                 "seven_day":{"used_percentage":34.6,"resets_at":1795400000}}}'

# ═════════════════════════════════════════════════════════
# 輸出契約與壞輸入
# ═════════════════════════════════════════════════════════
t "完整輸入：兩行、exit 0、stderr 乾淨，資訊列內容正確"
sl "$FULL"; clean
eq "$L2" '📁 proj | 🥢 Opus 4.7 | 💰$0.1234 | 📐26% | 🟢 5h:12% 7d:35% ↻13:53 | 🕐11:06:40'

t "空輸入：照樣兩行，欄位用預設值"
sl ''; clean
has "$L2" '🥢 N/A | 💰$0.0000 | 📐0%'

t "不是 JSON：jq 的錯誤訊息不會漏到畫面上"
sl 'not json'; clean
has "$L2" '🥢 N/A'

t "空物件 {}"
sl '{}'; clean
has "$L2" '🥢 N/A'

t "欄位型別亂掉（字串、null）：不炸，當成 0"
sl '{"cwd":"'"$P"'","model":{"display_name":"X"},"cost":{"total_cost_usd":"abc"},"context_window":{"context_window_size":"big","current_usage":null}}'
clean
eq "$L2" '📁 proj | 🥢 X | 💰$0.0000 | 📐0% | 🕐11:06:40'

t "找不到 jq：帶子照跑，資訊列提示要裝 jq"
sl "$FULL" PATH="$WORK/bin-nojq"; clean
eq "$(width "$L1")" 92
has "$L2" 'jq'

t "欄位值含換行：不會多出第三行，後面的欄位也不會錯位"
sl '{"cwd":"'"$P"'","model":{"display_name":"Opus\n4.7"},"cost":{"total_cost_usd":0.5}}'
clean
has "$L2" '🥢 Opus 4.7 | 💰$0.5000'

t "控制字元不會原樣送到終端機：C1（U+0080–9F）與雙向覆寫字元換成空白"
sl '{"cwd":"'"$P"'/a\u009b31mRED\u202eX","model":{"display_name":"M\u009d0;title\u0007"}}'; clean
hasnt "$L2" $'\xc2\x9b'; hasnt "$L2" $'\xc2\x9d'; hasnt "$L2" $'\xe2\x80\xae'
has "$L2" '📁 a 31mRED X | 🥢 M 0;title '

# ═════════════════════════════════════════════════════════
# 帶子
# ═════════════════════════════════════════════════════════
t "SUSHI_NOW 決定帶子：同一時間同一條，不同時間不同條"
sl "$FULL"; belt_a=$L1
sl "$FULL"; eq "$L1" "$belt_a"
sl "$FULL" SUSHI_NOW=$((NOW + 7))
if [ "$L1" != "$belt_a" ]; then ok; else no "t 和 t+7 的帶子不該相同"; fi

t "每格固定 3 欄：30 格的帶子在任何時間點都是 92 欄"
for dt in 0 1 2 3 5 8 13 21 34 55 89 144; do
  sl "$FULL" SUSHI_NOW=$((NOW + dt)); eq "$(width "$L1")" 92
done

t "捲動不變式：t+1 的帶子 = 新進的一格 + t 的帶子"
for dt in 0 1 2 3 4 5 6 7 8 9; do
  # 內容只取決於「位置 − 時間」，所以 t+1 的 12 格 = 一格新的 + t 的前 11 格
  sl "$FULL" SUSHI_SLOTS=11 SUSHI_NOW=$((NOW + dt));     prev=${L1#▸}; prev=${prev%▸}
  sl "$FULL" SUSHI_SLOTS=12 SUSHI_NOW=$((NOW + dt + 1)); next=${L1#▸}; next=${next%▸}
  case $next in
    *"$prev") eq "$(width "${next%"$prev"}")" 3 ;;
    *) no "dt=${dt}：[$next] 的右邊應該是 [$prev]" ;;
  esac
done

t "有 COLUMNS：帶子是塞得進 COLUMNS−4 的最長長度"
for pair in 20:14 40:35 79:74 80:74 81:77 120:116 200:194; do
  sl "$FULL" COLUMNS="${pair%:*}"; eq "$(width "$L1")" "${pair#*:}"
done

t "COLUMNS 沒設、是 0、不是數字：退回 30 格"
sl "$FULL";              eq "$(width "$L1")" 92
sl "$FULL" COLUMNS=0;    eq "$(width "$L1")" 92
sl "$FULL" COLUMNS=wide; eq "$(width "$L1")" 92

t "極窄終端機：至少留 1 格，不會算出 0 格或負數"
sl "$FULL" COLUMNS=5; clean
eq "$(width "$L1")" 5

t "SUSHI_SLOTS 固定格數，但不超過終端機寬度"
sl "$FULL" SUSHI_SLOTS=10;             eq "$(width "$L1")" 32
sl "$FULL" SUSHI_SLOTS=10 COLUMNS=200; eq "$(width "$L1")" 32
sl "$FULL" SUSHI_SLOTS=10 COLUMNS=20;  eq "$(width "$L1")" 14

t "SUSHI_MARGIN：設了 padding 的人可以多留邊"
sl "$FULL" COLUMNS=80 SUSHI_MARGIN=8; eq "$(width "$L1")" 71

t "SUSHI_EMPTY_PROB=100 全空、=0 全是壽司；SUSHI_EMOJI 換口味"
sl "$FULL" SUSHI_SLOTS=4 SUSHI_EMPTY_PROB=100;               eq "$L1" '▸════════════▸'
sl "$FULL" SUSHI_SLOTS=3 SUSHI_EMPTY_PROB=0 SUSHI_EMOJI='🍜'; eq "$L1" '▸🍜═🍜═🍜═▸'

t "設定值亂填：退回預設，不噴錯"
sl "$FULL" SUSHI_SLOTS=abc SUSHI_EMPTY_PROB=xyz SUSHI_MARGIN=-3 SUSHI_EMOJI=; clean
eq "$(width "$L1")" 92

t "空格比例接近 EMPTY_PROB：600 格裡 65% ± 6%"
sl "$FULL" SUSHI_SLOTS=600
# 空格 3 個 ═、壽司格 1 個 ═ → ═ 總數 = 2×空格數 + 600
empty=$(( ($(count "$L1" '═') - 600) / 2 ))
if [ "$empty" -ge 354 ] && [ "$empty" -le 426 ]; then ok; else no "600 格裡有 $empty 格空的"; fi

t "12 種壽司都會出現"
sl "$FULL" SUSHI_SLOTS=600
for sushi in 🍣 🍱 🍤 🍙 🍥 🐙 🍵 🦐 🥟 🦑 🍶 🍘; do has "$L1" "$sushi"; done

t "沒有短週期：t、t+100、t+300 的帶子兩兩不同"   # 舊版每 300 秒整條重複
sl "$FULL";                          belt_a=$L1
sl "$FULL" SUSHI_NOW=$((NOW + 100)); belt_b=$L1
sl "$FULL" SUSHI_NOW=$((NOW + 300)); belt_c=$L1
if [ "$belt_a" != "$belt_b" ] && [ "$belt_a" != "$belt_c" ] && [ "$belt_b" != "$belt_c" ]; then ok
else no "帶子出現週期性重複"; fi

t "壽司不是照池子順序輪播"   # 舊版的 h2 等於 slot_id + 11，下一盤永遠是池子裡的下一個
sl "$FULL" SUSHI_SLOTS=240 SUSHI_EMPTY_PROB=0 SUSHI_EMOJI='A B C D E F G H I J K L'
seq_str=${L1//═/}; seq_str=${seq_str//▸/}
pool=ABCDEFGHIJKLA; in_order=0; i=0
while [ "$i" -lt $(( ${#seq_str} - 1 )) ]; do
  cur=${seq_str:i:1}; nxt=${seq_str:i+1:1}
  after=${pool#*"$cur"}
  [ "$nxt" = "${after:0:1}" ] && in_order=$((in_order + 1))
  i=$((i + 1))
done
eq "${#seq_str}" 240
if [ "$in_order" -lt 60 ]; then ok; else no "239 對相鄰壽司裡有 $in_order 對照著池子順序（隨機應約 20 對）"; fi

# ═════════════════════════════════════════════════════════
# 資訊列：資料夾、context、花費
# ═════════════════════════════════════════════════════════
t "資料夾名稱：cwd 最後一段，空白與中文照顯示"
mkdir -p "$WORK/我的 專案"
sl '{"cwd":"'"$WORK"'/我的 專案","model":{"display_name":"X"}}'; clean
has "$L2" '📁 我的 專案 | '
sl '{"cwd":"/","model":{"display_name":"X"}}';             has "$L2" '📁 / | '
sl '{"cwd":"'"$P"'/","model":{"display_name":"X"}}';       has "$L2" '📁 proj | '
sl '{"workspace":{"current_dir":"'"$P"'"},"model":{"display_name":"X"}}'; has "$L2" '📁 proj | '
sl '{"cwd":"'"$P"'//","model":{"display_name":"X"}}';      has "$L2" '📁 proj | '   # 尾端不只一個斜線
sl '{"workspace":{"current_dir":123},"cwd":"'"$P"'","model":{"display_name":"X"}}'; has "$L2" '📁 proj | '   # current_dir 不是字串就看 cwd

t "cwd 含換行：不會拿「換行變空白之後的路徑」去問 git，以免顯示到隔壁 repo 的分支"
NL_DIR="$WORK/line"$'\n'"break"; mkdir -p "$NL_DIR" "$WORK/line break"
GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git -C "$WORK/line break" init -q
GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git -C "$WORK/line break" symbolic-ref HEAD refs/heads/WRONG_REPO
sl '{"cwd":"'"$WORK"'/line\nbreak","model":{"display_name":"X"}}'; clean
has "$L2" '📁 line break | 🥢 X'
hasnt "$L2" 'WRONG_REPO'

t "cwd 含 C1 控制字元：畫面上濾掉，但問 git 用的是原本的路徑"
C1_DIR="$WORK/c1"$'\xc2\x9b'"repo"; mkdir -p "$C1_DIR"
GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git -C "$C1_DIR" init -q
GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git -C "$C1_DIR" symbolic-ref HEAD refs/heads/main
sl '{"cwd":"'"$WORK"'/c1\u009brepo","model":{"display_name":"X"}}'; clean
hasnt "$L2" $'\xc2\x9b'
has "$L2" '🌿 main | '

t "沒給 cwd 時退回 \$PWD：資料夾名稱裡的控制字元與換行一樣濾掉"
ESC_DIR="$WORK/esc"$'\e'"[31mRED"; mkdir -p "$ESC_DIR"
cd "$ESC_DIR" || exit 2; sl '{}'; cd "$START_DIR" || exit 2
clean; hasnt "$L2" $'\e'; has "$L2" '📁 esc[31mRED | '
cd "$NL_DIR" || exit 2; sl '{}'; cd "$START_DIR" || exit 2
clean; has "$L2" '📁 linebreak | '

t "context %：優先用官方的 used_percentage"
sl '{"cwd":"'"$P"'","context_window":{"used_percentage":42.4,"context_window_size":200000,"current_usage":{"input_tokens":1000}}}'
has "$L2" '📐42%'

t "context %：沒有 used_percentage 時用 input + 兩種 cache 自己算"
sl '{"cwd":"'"$P"'","context_window":{"used_percentage":null,"context_window_size":200000,"current_usage":{"input_tokens":1000,"cache_creation_input_tokens":2000,"cache_read_input_tokens":50000}}}'
has "$L2" '📐27%'   # 53000 / 200000 = 26.5%

t "context %：session 剛開始什麼都是 null → 0%"
sl '{"cwd":"'"$P"'","context_window":{"used_percentage":null,"context_window_size":200000,"current_usage":null}}'; clean
has "$L2" '📐0%'

t "花費：固定四位小數、四捨五入"
sl '{"cwd":"'"$P"'","cost":{"total_cost_usd":0.12346}}'; has "$L2" '💰$0.1235 '
sl '{"cwd":"'"$P"'","cost":{"total_cost_usd":12.5}}';    has "$L2" '💰$12.5000 '
sl '{"cwd":"'"$P"'","cost":{"total_cost_usd":0}}';       has "$L2" '💰$0.0000 '

# ═════════════════════════════════════════════════════════
# git
# ═════════════════════════════════════════════════════════
REPO="$WORK/repo"; mkdir -p "$REPO"
g() {  # 不吃使用者自己的 git 設定（簽章、hooks…）
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git -C "$REPO" \
    -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false "$@"
}
g init -q; g symbolic-ref HEAD refs/heads/main
RJ='{"cwd":"'"$REPO"'","model":{"display_name":"X"}}'

t "git：還沒有任何 commit 的新 repo 也顯示分支名"
sl "$RJ"; clean
has "$L2" '📁 repo | 🌿 main | 🥢 X'

echo one >"$REPO/a.txt"; g add a.txt; g commit -q -m init

t "git：乾淨的 repo 只顯示分支"
sl "$RJ"; clean
has "$L2" '📁 repo | 🌿 main | 🥢 X'

t "git：不執行 repo 設定裡的 core.fsmonitor 指令"
# 解壓縮來的專案可以自帶 .git/config；一般的 git status 會去跑裡面指定的 fsmonitor 程式
g config core.fsmonitor "printf x >$WORK/PWNED; :"
sl "$RJ"; clean
has "$L2" '🌿 main | '
if [ -e "$WORK/PWNED" ]; then no "core.fsmonitor 的指令被執行了"; else ok; fi
g config --unset core.fsmonitor

t "git：render 不改寫 .git/index（不跟其他 git 指令搶 index.lock）"
touch -t 202001010000 "$REPO/a.txt"   # stat 變了、內容沒變：一般的 git status 會順手回寫 index
index_before=$(cksum <"$REPO/.git/index")
sl "$RJ"
eq "$(cksum <"$REPO/.git/index")" "$index_before"

t "git：已暫存、未暫存、未追蹤各算一個"
echo two >>"$REPO/a.txt"                    # 未暫存
echo new >"$REPO/b.txt"; g add b.txt        # 已暫存
echo x >"$REPO/c.txt"                       # 未追蹤
sl "$RJ"; has "$L2" '🌿 main (+3) | '

t "git：同一個檔案又暫存又再改，只算一次；未追蹤資料夾裡的檔案逐一算"
g add a.txt; echo three >>"$REPO/a.txt"     # a.txt 變成 MM
mkdir "$REPO/d"; echo 1 >"$REPO/d/e.txt"; echo 2 >"$REPO/d/f.txt"
sl "$RJ"; has "$L2" '🌿 main (+5) | '

t "git：分支名含斜線與中文"
g add -A; g commit -q -m more; g checkout -q -b 'feat/壽司'
sl "$RJ"; clean
has "$L2" '🌿 feat/壽司 | '

t "git：分支名裡的 C1 控制字元與雙向覆寫字元會被拿掉"   # git 只擋 ASCII 控制字元
g checkout -q -b $'c1\xc2\x9b31mRED\xe2\x80\xaeX'
sl "$RJ"; clean
hasnt "$L2" $'\xc2\x9b'; hasnt "$L2" $'\xe2\x80\xae'
has "$L2" '🌿 c131mREDX | '
g checkout -q 'feat/壽司'

t "git：detached HEAD 顯示 7 碼 commit"
sha=$(g rev-parse HEAD); g checkout -q --detach
sl "$RJ"; has "$L2" "🌿 ${sha:0:7} | "
g checkout -q main

t "git：變動太多時數到 999 就停，顯示 (+999+)"
# 沒 ignore 的 node_modules 動輒上萬個檔案；bash 逐行數完要好幾秒，會拖過 refreshInterval 被 Claude Code 砍掉
BIG="$WORK/big"; mkdir -p "$BIG"
GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git -C "$BIG" init -q
GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git -C "$BIG" symbolic-ref HEAD refs/heads/main
BIGJ='{"cwd":"'"$BIG"'","model":{"display_name":"X"}}'
for ((i = 0; i < 999; i++)); do : >"$BIG/f$i"; done
sl "$BIGJ"; clean; has "$L2" '🌿 main (+999) | '      # 剛好 999 個還是照實顯示
for ((i = 999; i < 1200; i++)); do : >"$BIG/f$i"; done
sl "$BIGJ"; clean; has "$L2" '🌿 main (+999+) | '

t "git：不是 repo 就沒有 🌿；cwd 不存在也不炸"
sl "$FULL"; hasnt "$L2" '🌿'
sl '{"cwd":"/no/such/dir here","model":{"display_name":"X"}}'; clean
has "$L2" '📁 dir here | 🥢 X'

t "git 快取：5 秒內不重問 git，過期才更新"
SJ='{"session_id":"sess-1","cwd":"'"$REPO"'","model":{"display_name":"X"}}'
sl "$SJ";                          has "$L2" '🌿 main | '
echo x >"$REPO/new.txt"
sl "$SJ" SUSHI_NOW=$((NOW + 4));   has "$L2" '🌿 main | '        # 還在 5 秒內：沿用舊值
sl "$SJ" SUSHI_NOW=$((NOW + 5));   has "$L2" '🌿 main (+1) | '   # 過期：重問

t "git 快取：同一個 session 換了目錄，不會拿上一個目錄的結果來用"
sl '{"session_id":"sess-1","cwd":"'"$P"'","model":{"display_name":"X"}}' SUSHI_NOW=$((NOW + 6))
hasnt "$L2" '🌿'

t "git 快取：SUSHI_GIT_TTL=0 關閉快取"
sl "$SJ" SUSHI_GIT_TTL=0 SUSHI_NOW=$((NOW + 20)); has "$L2" '🌿 main (+1) | '
echo y >"$REPO/new2.txt"
sl "$SJ" SUSHI_GIT_TTL=0 SUSHI_NOW=$((NOW + 20)); has "$L2" '🌿 main (+2) | '

t "git 快取：session_id 不能讓快取寫到快取目錄外面"
# 先放一個 git-x 目錄，沒擋的話 git-x/../../escape 就會穿出去，寫到 $WORK/cache/escape
mkdir -p "$WORK/cache/sushi-statusline-$(id -u)/git-x"
sl '{"session_id":"x/../../escape","cwd":"'"$REPO"'","model":{"display_name":"X"}}' SUSHI_NOW=$((NOW + 40)); clean
has "$L2" '🌿 main (+2) | '
if [ -e "$WORK/cache/escape" ]; then no "快取寫到了快取目錄外面"; else ok; fi

t "快取目錄是別人先放好的 symlink：不跟著寫進去，照常輸出"
mkdir -p "$WORK/tmp2" "$WORK/victim"
ln -s "$WORK/victim" "$WORK/tmp2/sushi-statusline-$(id -u)"
sl "$SJ" TMPDIR="$WORK/tmp2" SUSHI_NOW=$((NOW + 50)); clean
has "$L2" '🌿 main (+2) | '
eq "$(find "$WORK/victim" -mindepth 1 | wc -l | tr -d ' ')" 0

t "git 很慢、render 被中途砍掉：之後的 render 不會再卡在 git 上"
# Claude Code 會在下一次更新到來時砍掉還在跑的 render。沒有先佔位的話快取永遠寫不進去，每次都重跑 git、每次都被砍
SLOWJ='{"session_id":"slow-1","cwd":"'"$REPO"'","model":{"display_name":"X"}}'
printf '%s' "$SLOWJ" | env -i PATH="$WORK/bin-slowgit" TMPDIR="$WORK/cache" TZ=UTC SUSHI_NOW="$NOW" SUSHI_GH=0 \
  GIT_LOG="$WORK/git.log" "$BASH" "$SCRIPT" >/dev/null 2>&1 &
slow_pid=$!
tries=0   # 等第一次 render 真的卡進 git 裡再砍它
while [ ! -s "$WORK/git.log" ] && [ "$tries" -lt 100 ]; do sleep 0.1; tries=$((tries + 1)); done
kill "$slow_pid" 2>/dev/null; wait "$slow_pid" 2>/dev/null
SECONDS=0
sl "$SLOWJ" PATH="$WORK/bin-slowgit" GIT_LOG="$WORK/git.log" SUSHI_NOW=$((NOW + 1)); clean
has "$L2" '📁 repo | 🥢 X'
if [ "$SECONDS" -lt 2 ]; then ok; else no "第二次 render 花了 ${SECONDS} 秒"; fi
eq "$(wc -l <"$WORK/git.log" | tr -d ' ')" 1

g add -A; g commit -q -m tidy

# ═════════════════════════════════════════════════════════
# rate limit
# ═════════════════════════════════════════════════════════
RL() { printf '{"cwd":"%s","model":{"display_name":"X"},"rate_limits":%s}' "$P" "$1"; }

t "rate：只有 7d（Max 方案的實際情況）也要顯示，↻ 帶日期"
sl "$(RL '{"seven_day":{"used_percentage":34.6,"resets_at":1795400000}}')"; clean
has "$L2" '| 🟢 7d:35% ↻11/23 02:13 | '

t "rate：只有 5h"
sl "$(RL '{"five_hour":{"used_percentage":12.4,"resets_at":1795010000}}')"
has "$L2" '| 🟢 5h:12% ↻13:53 | '

t "rate：燈號跟著比較滿的那個窗口，門檻 50 / 80"
sl "$(RL '{"five_hour":{"used_percentage":10},"seven_day":{"used_percentage":95}}')"; has "$L2" '🔴 5h:10% 7d:95%'
sl "$(RL '{"five_hour":{"used_percentage":49.4},"seven_day":{"used_percentage":3}}')"; has "$L2" '🟢 5h:49% 7d:3%'
sl "$(RL '{"five_hour":{"used_percentage":50}}')";   has "$L2" '🟡 5h:50%'
sl "$(RL '{"five_hour":{"used_percentage":79.4}}')"; has "$L2" '🟡 5h:79%'
sl "$(RL '{"five_hour":{"used_percentage":79.6}}')"; has "$L2" '🔴 5h:80%'

t "rate：resets_at 不是數字 → 不顯示 ↻，其餘照常"
sl "$(RL '{"five_hour":{"used_percentage":85,"resets_at":"soon"}}')"; clean
has "$L2" '| 🔴 5h:85% | '
hasnt "$L2" '↻'

t "rate：完全沒有 rate_limits → 整段不出現"
sl '{"cwd":"'"$P"'","model":{"display_name":"X"}}'
eq "$L2" '📁 proj | 🥢 X | 💰$0.0000 | 📐0% | 🕐11:06:40'

t "bash 沒有 printf %()T 時退回 date：BSD 的 -r、GNU / busybox 的 -d @ 都要對"
# bash 4.2 以上平常走內建的 printf，date 那條路在 Linux 上根本跑不到。這裡匯出一個同名函式蓋掉 printf，
# 遇到 %( 就失敗，等於模擬舊 bash。（bash 3.2 本來就走 date；它匯出函式用的變數名不同，這個設定對它沒作用）
OLD_PRINTF='BASH_FUNC_printf%%=() { case $* in *"%("*) return 1 ;; esac; builtin printf "$@"; }'
sl "$FULL" "$OLD_PRINTF"; clean
eq "$L2" '📁 proj | 🥢 Opus 4.7 | 💰$0.1234 | 📐26% | 🟢 5h:12% 7d:35% ↻13:53 | 🕐11:06:40'
sl "$(RL '{"seven_day":{"used_percentage":34.6,"resets_at":1795400000}}')" "$OLD_PRINTF"
has "$L2" '| 🟢 7d:35% ↻11/23 02:13 | '

t "沒釘住時間時：時鐘是現在的 HH:MM:SS（內建 printf 與 date 兩條路）"
for extra in SUSHI_GH=0 "$OLD_PRINTF"; do
  sl "$FULL" SUSHI_NOW= "$extra"; clean
  case $L2 in *' | 🕐'[0-2][0-9]:[0-5][0-9]:[0-5][0-9]) ok ;; *) no "時鐘格式不對：[$L2]" ;; esac
done

t "date 退回路線不會被目前目錄裡「檔名剛好是那個 epoch」的檔案騙走"   # GNU / busybox 的 date -r 是讀檔案的 mtime
mkdir -p "$WORK/epoch"; touch -t 202001010000 "$WORK/epoch/1795010000"
cd "$WORK/epoch" || exit 2
sl "$FULL" "$OLD_PRINTF"
cd "$START_DIR" || exit 2
has "$L2" ' ↻13:53 | '

# ═════════════════════════════════════════════════════════
# PR 徽章與 GitHub issue / PR 數量
# ═════════════════════════════════════════════════════════
PRJ() { printf '{"cwd":"%s","model":{"display_name":"X"},"pr":%s}' "$P" "$1"; }

t "PR：顯示目前分支的 PR 編號與審查狀態"
sl "$(PRJ '{"number":3,"review_state":"approved"}')"; clean
has "$L2" '📁 proj | 🔀#3 ✅ | 🥢 X'
sl "$(PRJ '{"number":3,"review_state":"pending"}')";           has "$L2" '| 🔀#3 👀 | '
sl "$(PRJ '{"number":3,"review_state":"changes_requested"}')"; has "$L2" '| 🔀#3 💬 | '
sl "$(PRJ '{"number":3,"review_state":"draft"}')";             has "$L2" '| 🔀#3 📝 | '
sl "$(PRJ '{"number":1234}')";                                 has "$L2" '| 🔀#1234 | '

t "PR：沒有 pr、或編號不是數字 → 不顯示"
sl "$FULL";                        hasnt "$L2" '🔀'
sl "$(PRJ '{"number":"oops"}')";   clean; hasnt "$L2" '🔀'

GHJ='{"cwd":"'"$REPO"'","model":{"display_name":"X"},"workspace":{"repo":{"host":"github.com","owner":"octo","name":"sushi"}}}'

t "GitHub 數量：第一次 render 不等網路，先不顯示；背景查完才出現在 🌿 後面"
ghsl "$GHJ"; clean
hasnt "$L2" 'issues:'
if wait_for 'issues:2, PRs:1' "$GHJ"; then ok; else no "等不到 issues:2, PRs:1（L2=[$L2]）"; fi
has "$L2" '🌿 main | issues:2, PRs:1 | 🥢 X'

t "GitHub 數量：查詢帶上 workspace.repo 的 owner / name"
has "$(cat "$WORK/gh.log")" '-f owner=octo -f name=sushi '   # -f 才是純字串；-F 會把 123 這種 repo 名當數字送

t "GitHub 數量：300 秒內不重查"
ghsl "$GHJ"; ghsl "$GHJ" SUSHI_NOW=$((NOW + 299)); sleep 0.3
eq "$(gh_calls)" 1

t "GitHub 數量：過期後這一輪先顯示舊值，背景查完再換新值"
GH_STUB_OUT='5 0'
ghsl "$GHJ" SUSHI_NOW=$((NOW + 300)); has "$L2" 'issues:2, PRs:1'
if wait_for 'issues:5, PRs:0' "$GHJ" SUSHI_NOW=$((NOW + 300)); then ok; else no "等不到更新後的數量（L2=[$L2]）"; fi
eq "$(gh_calls)" 2
GH_STUB_OUT='2 1'

t "GitHub 數量：gh 回了看不懂的東西 → 不顯示，也不會每次 render 都重試"
BROKEN='{"cwd":"'"$REPO"'","model":{"display_name":"X"},"workspace":{"repo":{"host":"github.com","owner":"octo","name":"broken"}}}'
GH_STUB_OUT='HTTP 401: Bad credentials'
ghsl "$BROKEN"; wait_calls 'name=broken' 1
for _ in 1 2 3; do ghsl "$BROKEN"; sleep 0.15; done
clean; hasnt "$L2" 'issues:'
eq "$(gh_calls 'name=broken')" 1
GH_STUB_OUT='2 1'

t "GitHub 數量：重查失敗後不再顯示舊數字，也一樣等 300 秒才重試"
STALEJ='{"cwd":"'"$REPO"'","model":{"display_name":"X"},"workspace":{"repo":{"host":"github.com","owner":"octo","name":"stale"}}}'
if wait_for 'issues:2, PRs:1' "$STALEJ"; then ok; else no "等不到第一次的數量"; fi
GH_STUB_OUT='HTTP 401: Bad credentials'
ghsl "$STALEJ" SUSHI_NOW=$((NOW + 300)); has "$L2" 'issues:2, PRs:1'     # 重查的這一輪還是舊值
tries=0
while [ "$tries" -lt 50 ]; do
  ghsl "$STALEJ" SUSHI_NOW=$((NOW + 301)); case $L2 in *issues:*) ;; *) break ;; esac
  sleep 0.1; tries=$((tries + 1))
done
hasnt "$L2" 'issues:'
eq "$(gh_calls 'name=stale')" 2
GH_STUB_OUT='2 1'

t "GitHub 數量：快取寫不進去時不發查詢（否則會變成每秒打一次 API）"
if [ "$(id -u)" = 0 ]; then
  skip "root 不受目錄權限限制，做不出寫不進去的快取目錄"
else
  RO="$WORK/ro/sushi-statusline-$(id -u)"; mkdir -p "$RO"; chmod 500 "$RO"
  for _ in 1 2 3; do
    ghsl '{"cwd":"'"$P"'","workspace":{"repo":{"host":"github.com","owner":"octo","name":"readonly"}}}' TMPDIR="$WORK/ro"; clean
  done
  sleep 0.4
  eq "$(gh_calls 'name=readonly')" 0
  chmod 700 "$RO"
fi

t "GitHub 數量：不是 github.com、SUSHI_GH=0、owner 有怪字元 → 完全不呼叫 gh"
calls_before=$(gh_calls)
ghsl '{"cwd":"'"$REPO"'","workspace":{"repo":{"host":"gitlab.com","owner":"octo","name":"other"}}}'
ghsl "$GHJ" SUSHI_GH=0 SUSHI_NOW=$((NOW + 9999))
ghsl '{"cwd":"'"$REPO"'","workspace":{"repo":{"host":"github.com","owner":"../x","name":"y z"}}}'
sleep 0.3
eq "$(gh_calls)" "$calls_before"

t "GitHub 數量：沒裝 gh → 安靜地不顯示"
sl '{"cwd":"'"$REPO"'","model":{"display_name":"X"},"workspace":{"repo":{"host":"github.com","owner":"octo","name":"nogh"}}}' SUSHI_GH=1
clean; hasnt "$L2" 'issues:'

t "GitHub 數量：gh 再慢也不拖住 render（輸出接在 pipe 上也一樣）"
# 背景工作要是沒切斷 stdout，接 pipe 的讀者（Claude Code）會一直等到 gh 結束
SECONDS=0
piped=$(printf '%s' '{"cwd":"'"$P"'","workspace":{"repo":{"host":"github.com","owner":"octo","name":"slow"}}}' |
  env -i PATH="$WORK/bin-gh" TMPDIR="$WORK/cache" TZ=UTC SUSHI_NOW="$NOW" SUSHI_GH=1 \
    GH_LOG="$WORK/gh.log" GH_STUB_OUT='2 1' GH_STUB_SLEEP=3 "$BASH" "$SCRIPT" 2>&1)
if [ "$SECONDS" -lt 2 ]; then ok; else no "render 等了 ${SECONDS} 秒"; fi
has "$piped" '📁 proj | '
wait_calls 'name=slow' 1
eq "$(gh_calls 'name=slow')" 1

# ═════════════════════════════════════════════════════════
# 窄終端機：依優先序捨棄資訊段
# ═════════════════════════════════════════════════════════
WIDEJ='{"cwd":"'"$REPO"'","model":{"display_name":"Opus 4.7"},"cost":{"total_cost_usd":0.1234},
  "context_window":{"used_percentage":26},"pr":{"number":3,"review_state":"approved"},
  "workspace":{"repo":{"host":"github.com","owner":"octo","name":"wide"}},
  "rate_limits":{"five_hour":{"used_percentage":12,"resets_at":1795010000},"seven_day":{"used_percentage":34}}}'
wide() { ghsl "$WIDEJ" "$@"; }
wait_for 'issues:2, PRs:1' "$WIDEJ" || echo "（等不到 wide 的 GitHub 數量，下面幾項會跟著失敗）"

t "寬度夠：每一段都在"
wide; clean
full=$L2
eq "$full" '📁 repo | 🌿 main | issues:2, PRs:1 | 🔀#3 ✅ | 🥢 Opus 4.7 | 💰$0.1234 | 📐26% | 🟢 5h:12% 7d:34% ↻13:53 | 🕐11:06:40'
wide COLUMNS=$(( $(width "$full") + 4 )); eq "$L2" "$full"   # 剛好塞得下就一段都不丟

t "寬度不夠：依 🕐 → 💰 → 🔀 → issues → 🥢 → rate → 📐 → 🌿 的順序一次丟一段，📁 永遠留著"
cur=$full
set -- '🕐' '💰' '🔀' 'issues:' '🥢' '5h:' '📐' '🌿'
while [ $# -gt 0 ]; do
  wide COLUMNS=$(( $(width "$cur") + 3 ))    # 比現在這行少 1 欄
  hasnt "$L2" "$1"                           # 輪到的這段被拿掉
  [ $# -gt 1 ] && has "$L2" "$2"             # 下一順位的還在
  cur=$L2; shift
done
eq "$L2" '📁 repo'

t "窄終端機：留下來的資訊列真的塞得進 COLUMNS−4"
for cols in 140 120 100 90 80 70 60 50 40; do
  wide COLUMNS=$cols; clean
  w=$(width "$L2")
  if [ "$w" -le $((cols - 4)) ]; then ok; else no "COLUMNS=${cols} 時資訊列寬 ${w}：[$L2]"; fi
done

t "窄終端機：中文資料夾名稱算 2 欄，不會低估"
mkdir -p "$WORK/壽司專案資料夾"
CJKJ='{"cwd":"'"$WORK"'/壽司專案資料夾","model":{"display_name":"Opus 4.7"},"cost":{"total_cost_usd":1}}'
sl "$CJKJ"; cjk_full=$L2
sl "$CJKJ" COLUMNS=$(( $(width "$cjk_full") + 4 )); eq "$L2" "$cjk_full"
sl "$CJKJ" COLUMNS=$(( $(width "$cjk_full") + 3 )); hasnt "$L2" '🕐'

t "SUSHI_DROP_ORDER：自訂捨棄順序，認不得的名字略過"
wide COLUMNS=$(( $(width "$full") + 3 )) SUSHI_DROP_ORDER='nonsense cost time'; clean
hasnt "$L2" '💰'
has "$L2" '🕐'

# ═════════════════════════════════════════════════════════
# locale
# ═════════════════════════════════════════════════════════
wide; base1=$L1; base2=$L2
have_locale() {  # glibc 的 locale -a 會把 de_DE.UTF-8 列成 de_DE.utf8，兩種寫法都認
  command -v locale >/dev/null 2>&1 || return 1
  case "$(locale -a 2>/dev/null)" in *"$1"* | *"${1%.UTF-8}.utf8"*) return 0 ;; esac
  return 1
}
for loc in zh_TW.UTF-8 de_DE.UTF-8 en_US.UTF-8; do
  t "locale ${loc}：輸出和預設環境一模一樣（de_DE 的小數點是逗號）"
  if have_locale "$loc"; then
    wide LC_ALL="$loc" COLUMNS=100; l1=$L1; l2=$L2; clean
    wide COLUMNS=100; eq "$l1" "$L1"; eq "$l2" "$L2"
  else
    skip "這台機器沒有 $loc"
  fi
done
t "locale：LANG=C 也不影響"
wide LANG=C; clean; eq "$L1" "$base1"; eq "$L2" "$base2"

# ═════════════════════════════════════════════════════════
# install.sh / demo.sh
# ═════════════════════════════════════════════════════════
for dir_name in 'has space' "it's here"; do
  t "install.sh --json：路徑含「${dir_name}」時，command 仍是能直接交給 shell 執行的合法 JSON"
  ODD="$WORK/$dir_name"; mkdir -p "$ODD"
  cp "$ROOT/sushi-statusline.sh" "$ROOT/install.sh" "$ROOT/demo.sh" "$ODD/"
  snippet=$("$BASH" "$ODD/install.sh" --json 2>/dev/null)
  eq "$(printf '%s' "$snippet" | jq -r '.statusLine | "\(.type) \(.refreshInterval)"' 2>/dev/null)" 'command 1'
  cmd=$(printf '%s' "$snippet" | jq -r '.statusLine.command' 2>/dev/null)
  # Claude Code 會把 command 整串交給 shell
  eq "$(printf '{}' | sh -c "$cmd" 2>/dev/null | wc -l | tr -d ' ')" 2
done
SPACED="$WORK/has space"
snippet=$("$BASH" "$SPACED/install.sh" --json 2>/dev/null)

t "install.sh 不帶參數：只印說明，不碰 ~/.claude"
out=$(HOME="$WORK/home" "$BASH" "$SPACED/install.sh" 2>&1); eq "$?" 0
if [ -e "$WORK/home" ]; then no "install.sh 動了 HOME"; else ok; fi
# 說明裡給人複製的片段：從 "statusLine" 到縮排兩格的 }，外面包一層 {} 要等於 --json 的結果
fragment=$(printf '%s\n' "$out" | sed -n '/^  "statusLine"/,/^  }$/p')
eq "$(printf '{%s}' "$fragment" | jq -c . 2>&1)" "$(printf '%s' "$snippet" | jq -c .)"

t "demo.sh：連續畫出畫面，收到結束訊號正常離開"
"$BASH" "$ROOT/demo.sh" >"$WORK/demo.out" 2>&1 &
demo_pid=$!
tries=0   # 等它至少畫出一個畫面
while [ "$tries" -lt 100 ]; do
  case "$(cat "$WORK/demo.out" 2>/dev/null)" in *📁*) break ;; esac
  sleep 0.1; tries=$((tries + 1))
done
kill -TERM "$demo_pid" 2>/dev/null; wait "$demo_pid"; eq "$?" 0
has "$(cat "$WORK/demo.out")" '▸'
has "$(cat "$WORK/demo.out")" '📁'

# ═════════════════════════════════════════════════════════
printf '\n%s：%d 通過、%d 失敗、%d 略過（bash %s）\n' "$([ "$FAIL" -eq 0 ] && echo '🍣 OK' || echo '✗ FAIL')" "$PASS" "$FAIL" "$SKIP" "$BASH_VERSION"
[ "$FAIL" -eq 0 ]
