#!/usr/bin/env bash
# 🍣 Sushi Conveyor Belt Status Line for Claude Code
# 每秒 L→R 滾動的迴轉壽司 status line。
# 文件：見同目錄的 README.md。
#
# 外部行程：每次 render 一定有 jq 一次；bash < 4.2 再加 date（現在時間一次、有重設時間再一次）。
# 快取過期的那一次（預設每 5 秒）多 git 一次與 mv 兩次。其餘全部是 bash 內建。

# Claude Code 把終端機寬度放在 COLUMNS。bash 可能在跑完外部指令後自己改寫它，
# 所以趁還沒 fork 任何東西先抄下來。
TERM_COLS=${COLUMNS:-0}

# 字串一律當 bytes 處理：行為不隨使用者的 locale 改變（zh_TW 的定序會讓 [...] 多吃字、
# de_DE 的小數點是逗號），子行程的輸出也固定。
export LC_ALL=C
set -f   # 不做檔名展開：下面有幾處刻意不加引號來切字

# ═══════════════════════════════════════════
# 可調參數 — 直接改預設值，或用 SUSHI_* 環境變數覆寫（不必動這個檔案）
# ═══════════════════════════════════════════
SLOTS_VISIBLE=${SUSHI_SLOTS:-0}       # 帶子格數；0 = 自動貼齊終端機寬度（拿不到寬度時 30 格）
EMPTY_PROB=${SUSHI_EMPTY_PROB:-65}    # % 空格機率（越高越稀疏）
MARGIN=${SUSHI_MARGIN:-4}             # 終端機寬度要扣掉的邊。settings.json 有設 padding 就再加 2×padding
GIT_TTL=${SUSHI_GIT_TTL:-5}           # git 狀態快取秒數；0 = 每次都問 git
SHOW_GH=${SUSHI_GH:-1}                # 1 = 用 gh 查 GitHub 的 open issue / PR 數量；0 = 關掉
GH_TTL=${SUSHI_GH_TTL:-300}           # GitHub 數量快取秒數（最少 60）
# 終端機太窄時，資訊列依這個順序一次拿掉一段（📁 永遠留著）
DROP_ORDER=${SUSHI_DROP_ORDER:-time cost pr gh model rate ctx git}
# 🍣 壽司 emoji 池，自行替換口味（每個都要是 2 欄寬的 emoji）
# shellcheck disable=SC2206  # 刻意不加引號：用空白切成陣列（上面已 set -f，不會展開檔名）
SUSHI=(${SUSHI_EMOJI:-🍣 🍱 🍤 🍙 🍥 🐙 🍵 🦐 🥟 🦑 🍶 🍘})
NUM_SUSHI=${#SUSHI[@]}

# uint 值 預設 → REPLY：不是非負整數（或長得離譜）就用預設值，後面的算術才不會噴錯
uint() {
  case $1 in
    '' | *[!0-9]* | ????????????????*) REPLY=$2 ;;
    *) REPLY=$((10#$1)) ;;
  esac
}
uint "$TERM_COLS" 0;      TERM_COLS=$REPLY
uint "$SLOTS_VISIBLE" 0;  SLOTS_VISIBLE=$REPLY
uint "$EMPTY_PROB" 65;    EMPTY_PROB=$REPLY
uint "$MARGIN" 4;         MARGIN=$REPLY
uint "$GIT_TTL" 5;        GIT_TTL=$REPLY
uint "$GH_TTL" 300;       GH_TTL=$REPLY
# 和 GIT_TTL 不同，這個沒有「0 = 不快取」：那等於每次 render 打一次 GitHub API，幾十分鐘就把額度用完
[ "$GH_TTL" -lt 60 ] && GH_TTL=60

# ═══════════════════════════════════════════
# 時間
# ═══════════════════════════════════════════
# fmt_time 格式 epoch → REPLY。bash ≥ 4.2 有內建的 printf %(...)T，不用 fork；
# macOS 內附的 bash 3.2 沒有，退回 date（BSD 吃 -r <epoch>，GNU / busybox 吃 -d @<epoch>）
fmt_time() {
  printf -v REPLY "%($1)T" "$2" 2>/dev/null && return
  # 先 cd /：GNU 的 date -r 是「讀檔案的 mtime」，目前目錄裡要是剛好有個檔名等於這個 epoch 的檔案，
  # 它就會成功並給出錯的時間，輪不到後面的 -d。根目錄不是別人放得了檔案的地方。
  REPLY=$(cd / 2>/dev/null; date -r "$2" "+$1" 2>/dev/null || date -d "@$2" "+$1" 2>/dev/null)
  [ -n "$REPLY" ]
}

uint "${SUSHI_NOW:-}" ""
if [ -n "$REPLY" ]; then                # SUSHI_NOW：把「現在」釘在指定的 epoch（測試、截圖用）
  NOW=$REPLY; fmt_time '%H:%M:%S' "$NOW"; CLOCK=$REPLY
else
  printf -v REPLY '%(%s %H:%M:%S)T' -1 2>/dev/null || REPLY=$(date '+%s %H:%M:%S' 2>/dev/null)
  NOW=${REPLY%% *}; CLOCK=${REPLY#* }
fi
uint "$NOW" 0; NOW=$REPLY

# ═══════════════════════════════════════════
# 一次 jq 讀完所有欄位
#   · 一欄一行，沒有值就印空行，後面的欄位才不會往前擠
#   · 數字在 jq 裡就四捨五入成整數（jq 不看 locale，bash 之後只做整數運算）
#   · 字串裡的控制字元換成空白：值裡有換行也不會多出一行；C1（U+0080–9F）與雙向覆寫字元
#     也一併處理，資料夾名稱之類的外來字串不能拿來操控終端機
#   · 欄位不存在或型別不對一律當成沒有（at 會吞掉 getpath 的錯誤）
#   · 目錄給兩欄：CWD_SHOW 是濾過、拿來顯示的；CWD 是原樣、拿來問檔案系統的。兩者不能混用——
#     濾過的路徑可能剛好是另一個真實存在的目錄。路徑裡有換行時沒辦法一行送過來，
#     CWD 就留空（等於不查 git），而不是送一個改過的路徑。tab 之類的其他字元照原樣送。
# ═══════════════════════════════════════════
{
  IFS= read -r CWD_SHOW; IFS= read -r CWD
  IFS= read -r MODEL;    IFS= read -r SESSION
  IFS= read -r COST_E4;  IFS= read -r CTX_PCT
  IFS= read -r RATE_5H;  IFS= read -r RESET_5H
  IFS= read -r RATE_7D;  IFS= read -r RESET_7D
  IFS= read -r PR_NUM;   IFS= read -r PR_STATE
  IFS= read -r GH_HOST;  IFS= read -r GH_OWNER; IFS= read -r GH_NAME
} < <(jq -r '
  def at(p): try getpath(p) catch null;
  def text:  if type == "string" then
               ( explode
               | map(if . < 32 or (. >= 127 and . <= 159)                        # C0、DEL、C1
                        or . == 8206 or . == 8207                               # LRM / RLM
                        or (. >= 8234 and . <= 8238) or (. >= 8294 and . <= 8297) # 雙向嵌入、覆寫、隔離
                     then 32 else . end)
               | implode )
             else "" end;
  def path:  if type == "string" and (explode | all(. != 10 and . != 0)) then . else "" end;
  def num:   if type == "number" then . else 0 end;
  def int:   if type == "number" then (. + 0.5 | floor) else "" end;

  ((at(["workspace", "current_dir"]) | strings) // at(["cwd"])) as $cwd
  | ($cwd | text),
  ($cwd | path),
  (at(["model", "display_name"]) | text),
  (at(["session_id"]) | text),
  (at(["cost", "total_cost_usd"]) | num * 10000 | int),
  ( at(["context_window", "used_percentage"]) as $official
    | if ($official | type) == "number" then $official
      else
        # 舊版 Claude Code 沒有 used_percentage，照官方同一條公式自己算（只算 input 與兩種 cache）
        (at(["context_window", "context_window_size"]) | num) as $size
        | if $size > 0 then
            ( (at(["context_window", "current_usage", "input_tokens"]) | num)
            + (at(["context_window", "current_usage", "cache_creation_input_tokens"]) | num)
            + (at(["context_window", "current_usage", "cache_read_input_tokens"]) | num) ) * 100 / $size
          else 0 end
      end
    | int ),
  (at(["rate_limits", "five_hour", "used_percentage"]) | int),
  (at(["rate_limits", "five_hour", "resets_at"]) | int),
  (at(["rate_limits", "seven_day", "used_percentage"]) | int),
  (at(["rate_limits", "seven_day", "resets_at"]) | int),
  (at(["pr", "number"]) | int),
  (at(["pr", "review_state"]) | text),
  (at(["workspace", "repo", "host"]) | text),
  (at(["workspace", "repo", "owner"]) | text),
  (at(["workspace", "repo", "name"]) | text)
' 2>/dev/null)

# jq 一定會印出花費那一行；連它都沒有，代表 jq 沒跑起來，或輸入根本不是 JSON
NOTE=""
if [ -z "$COST_E4" ]; then
  command -v jq >/dev/null 2>&1 || NOTE="❗ 找不到 jq，請先安裝"
fi
[ -z "$MODEL" ] && MODEL="N/A"
if [ -z "$CWD_SHOW" ]; then CWD=$PWD; CWD_SHOW=$PWD; fi   # 輸入沒給目錄：用自己所在的目錄

uint "$COST_E4" 0;   COST_E4=$REPLY
uint "$CTX_PCT" 0;   CTX_PCT=$REPLY
uint "$RATE_5H" "";  RATE_5H=$REPLY
uint "$RESET_5H" ""; RESET_5H=$REPLY
uint "$RATE_7D" "";  RATE_7D=$REPLY
uint "$RESET_7D" ""; RESET_7D=$REPLY
uint "$PR_NUM" "";   PR_NUM=$REPLY

# ═══════════════════════════════════════════
# 建構輸送帶
# 核心：slot 內容 = f(position - NOW)
#   NOW 每秒 +1，同一內容會出現在右邊一格 → L→R，無需保存 state
# 每格固定 3 欄（═══ 或「壽司 + ═」），帶子總寬恆為 3 × 格數 + 2，才能精準貼齊終端機
# ═══════════════════════════════════════════
MAX_W=0   # 一行最多能用幾欄；0 = 不知道終端機多寬
if [ "$TERM_COLS" -gt 0 ]; then
  MAX_W=$((TERM_COLS - MARGIN))
  [ "$MAX_W" -lt 1 ] && MAX_W=1
fi

SLOTS=$SLOTS_VISIBLE
if [ "$MAX_W" -gt 0 ]; then
  FIT=$(( (MAX_W - 2) / 3 ))
  [ "$FIT" -lt 1 ] && FIT=1
  if [ "$SLOTS" -eq 0 ] || [ "$SLOTS" -gt "$FIT" ]; then SLOTS=$FIT; fi
elif [ "$SLOTS" -eq 0 ]; then
  SLOTS=30
fi
# 上限 1000 格（約 3000 欄）：COLUMNS 要是傳來一個離譜的數字，幾萬格算下來會超過 refreshInterval
[ "$SLOTS" -gt 1000 ] && SLOTS=1000
[ "$NUM_SUSHI" -eq 0 ] && EMPTY_PROB=100

BELT="▸"
for ((p = 0; p < SLOTS; p++)); do
  # 整數雜湊（xor-shift 與乘法交替）：把連續的 slot_id 攪成看不出規律的 32-bit 數。
  # 只做「乘大質數再取餘數」不夠——對連續整數那只是等差數列，壽司會照池子順序輪播。
  # 乘數 < 2^27、h < 2^32，乘積不會超過 bash 的 64-bit 整數。
  h=$(( (p - NOW) & 0xFFFFFFFF ))
  h=$(( (((h >> 16) ^ h) * 0x45D9F3B) & 0xFFFFFFFF ))
  h=$(( (((h >> 16) ^ h) * 0x45D9F3B) & 0xFFFFFFFF ))
  h=$(( (h >> 16) ^ h ))
  # 同一個 h 的餘數與商各管一件事：這格空不空、放哪一盤
  if (( h % 100 < EMPTY_PROB )); then
    BELT+="═══"
  else
    BELT+="${SUSHI[h / 100 % NUM_SUSHI]}═"
  fi
done
BELT+="▸"

# ═══════════════════════════════════════════
# 資訊列各段
# ═══════════════════════════════════════════
# strip_ctl 字串 → REPLY：拿掉會操控終端機的字元。資料夾與分支名稱都可能來自陌生的 repo。
#   C0 與 DEL；C1（UTF-8 的 C2 80–9F，有些終端機把 U+009B 當成 ESC [）；
#   雙向控制字元（E2 80 8E/8F/AA–AE、E2 81 A6–A9，能把畫面上的順序弄反）
strip_ctl() {
  REPLY=${1//[$'\x01'-$'\x1F\x7F']/}
  REPLY=${REPLY//$'\xC2'[$'\x80'-$'\x9F']/}
  REPLY=${REPLY//$'\xE2\x80'[$'\x8E\x8F\xAA'-$'\xAE']/}
  REPLY=${REPLY//$'\xE2\x81'[$'\xA6'-$'\xA9']/}
}

FOLDER=${CWD_SHOW%"${CWD_SHOW##*[!/]}"}   # 去掉尾端所有的 /
FOLDER=${FOLDER##*/}
strip_ctl "$FOLDER"; FOLDER=$REPLY       # jq 那邊濾過了，但退回 $PWD 時沒有經過 jq
[ -z "$FOLDER" ] && FOLDER=/

# 快取放在自己擁有的目錄裡。/tmp 是共用的，別人先建好的同名目錄或 symlink 一律不用。
CACHE_DIR=${TMPDIR:-/tmp}
CACHE_DIR=${CACHE_DIR%/}/sushi-statusline-${UID:-0}
have_cache() {
  [ -d "$CACHE_DIR" ] || mkdir -m 700 "$CACHE_DIR" 2>/dev/null
  [ -d "$CACHE_DIR" ] && [ ! -L "$CACHE_DIR" ] && [ -O "$CACHE_DIR" ]
}
# put 檔案 行...：寫到暫存檔再 mv。同一個檔案系統內的 mv 是原子操作，
# 同時在讀的另一個 render 只會看到舊的或新的，不會讀到寫一半的。
# （2>/dev/null 放前面：轉向由左至右生效，開檔失敗的訊息才會被吃掉）
put() {
  local file=$1; shift
  printf '%s\n' "$@" 2>/dev/null >"$file~$$" || return 1
  mv -f "$file~$$" "$file" 2>/dev/null && return 0
  rm -f "$file~$$" 2>/dev/null   # mv 失敗就把暫存檔收掉：檔名帶 PID，放著不管每次 render 都會多一個
  return 1
}

# ── 🌿 git ──
# 一次 git status 拿到分支和所有變動（同一個檔案又暫存又再改只算一次）。
# GIT_OPTIONAL_LOCKS=0：不順手回寫 index，每秒 render 才不會和 Claude 正在跑的 git 搶 index.lock。
# core.fsmonitor=false：repo 自己的 .git/config 可以把 fsmonitor 設成任意指令，git status 會去執行它。
# 這只關掉最容易被利用的一條路，不是完整的防護：clean filter 等設定一樣會被 git 執行
# （關掉 filter 會讓 Git LFS 的檔案全部被算成已修改）。來路不明的 .git 目錄本來就不該拿來跑 git。
git_info() {
  GIT_INFO=""
  [ -n "$CWD" ] && [ -d "$CWD" ] || return 0
  local line branch="" oid="" dirty=0
  while IFS= read -r line; do
    case $line in
      '# branch.head '*) branch=${line#'# branch.head '} ;;
      '# branch.oid '*)  oid=${line#'# branch.oid '} ;;
      '#'*) ;;
      # 數到 1000 就停：沒 ignore 的 node_modules 可以有好幾萬行，bash 逐行數完要好幾秒，
      # 拖過 refreshInterval 整個 render 會被 Claude Code 砍掉，status line 就永遠出不來
      ?*) dirty=$((dirty + 1)); [ "$dirty" -ge 1000 ] && break ;;
    esac
  done < <(GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false -C "$CWD" \
             status --porcelain=v2 --branch --untracked-files=all 2>/dev/null)
  [ -n "$branch" ] || return 0   # 不是 git repo（或沒裝 git）
  [ "$branch" = "(detached)" ] && branch=${oid:0:7}
  strip_ctl "$branch"   # git 只擋 ASCII 控制字元，C1 與雙向控制字元都進得了分支名
  GIT_INFO="🌿 $REPLY"
  if [ "$dirty" -ge 1000 ]; then GIT_INFO="$GIT_INFO (+999+)"
  elif [ "$dirty" -gt 0 ]; then GIT_INFO="$GIT_INFO (+$dirty)"; fi
}

# 官方文件建議快取 git：GIT_TTL 秒內的 render 直接讀檔，完全不 fork（代價是 +N 最多慢 GIT_TTL 秒）。
# 一個 session 一個檔，檔內記著時間與目錄；時間戳寫在內容裡，就不必用 BSD / GNU 寫法不同的 stat。
GIT_INFO=""; GIT_CACHE=""; GIT_HIT=""
case $SESSION in
  '' | *[!A-Za-z0-9_-]*) ;;   # 沒有 session_id、或它不適合當檔名：不快取
  *) if [ "$GIT_TTL" -gt 0 ] && have_cache; then GIT_CACHE="$CACHE_DIR/git-$SESSION"; fi ;;
esac
STALE=""   # 同一個目錄上一次的結果，過期了但還能先頂著用
if [ -n "$GIT_CACHE" ] && [ -f "$GIT_CACHE" ]; then
  C_TS=""; C_DIR=""; C_INFO=""
  { IFS= read -r C_TS; IFS= read -r C_DIR; IFS= read -r C_INFO; } 2>/dev/null <"$GIT_CACHE"
  strip_ctl "$C_INFO"; C_INFO=$REPLY   # 凡是要印出來的都過一次濾網，快取檔也不例外
  uint "$C_TS" ""
  if [ -n "$REPLY" ] && [ "$C_DIR" = "$CWD" ]; then
    STALE=$C_INFO
    if [ $((NOW - REPLY)) -ge 0 ] && [ $((NOW - REPLY)) -lt "$GIT_TTL" ]; then
      GIT_INFO=$C_INFO; GIT_HIT=1
    fi
  fi
fi
if [ -z "$GIT_HIT" ]; then
  # 先用舊結果佔位再去問 git。repo 大到 git status 跑超過 refreshInterval 時，這次 render 會被 Claude Code
  # 砍掉；沒有佔位的話快取永遠寫不進去，之後每次 render 都重跑 git、每次都被砍，status line 就再也出不來。
  [ -n "$GIT_CACHE" ] && put "$GIT_CACHE" "$NOW" "$CWD" "$STALE"
  git_info
  [ -n "$GIT_CACHE" ] && put "$GIT_CACHE" "$NOW" "$CWD" "$GIT_INFO"
fi

# ── GitHub open issues / PRs ──
# 每次 render 都打 API 太慢又吃額度：只讀快取；過期了就在背景用 gh 更新，這一輪先顯示舊值
# （第一次沒有快取就先不顯示）。repo 身分用 Claude Code 從 origin 解析好的 workspace.repo。
GH_INFO=""
if [ "$SHOW_GH" = 1 ] && [ "$GH_HOST" = github.com ] && [ -n "$GH_OWNER" ] && [ -n "$GH_NAME" ]; then
  case $GH_OWNER$GH_NAME in
    *[!A-Za-z0-9._-]*) ;;   # 要拿來當檔名和 API 參數，只收 GitHub 名稱會有的字元
    *)
      if command -v gh >/dev/null 2>&1 && have_cache; then
        GH_CACHE="$CACHE_DIR/gh-${GH_OWNER}__${GH_NAME}"
        G_TS=""; G_ISSUES=""; G_PRS=""
        [ -f "$GH_CACHE" ] && read -r G_TS G_ISSUES G_PRS 2>/dev/null <"$GH_CACHE"
        uint "$G_TS" 0;      G_TS=$REPLY
        uint "$G_ISSUES" ""; G_ISSUES=$REPLY
        uint "$G_PRS" "";    G_PRS=$REPLY
        [ -n "$G_ISSUES" ] && [ -n "$G_PRS" ] && GH_INFO="issues:${G_ISSUES}, PRs:${G_PRS}"
        if [ $((NOW - G_TS)) -ge "$GH_TTL" ] || [ $((NOW - G_TS)) -lt 0 ]; then
          # 先把時間戳更新（數字沿用舊的），之後的 render 和其他 session 就不會重複去查。
          # 佔位寫成功才去查：快取寫不進去（磁碟滿、目錄唯讀）還照查的話，每次 render 都會打一次 API。
          if put "$GH_CACHE" "$NOW ${G_ISSUES:--} ${G_PRS:--}"; then
            # stdio 全部切斷再丟背景：status line 不等網路，Claude Code 也不會等這個子行程。
            # （不能寫成 put … && ( … ) &：那樣進背景的是整串 &&，外層的子 shell 還握著 stdout）
            (
              # shellcheck disable=SC2016  # $owner / $name 是 GraphQL 變數，不是 shell 變數
              # -f 而不是 -F：-F 會把 123 這種名字當成數字送出去，GraphQL 的 String! 不收
              counts=$(gh api graphql -f owner="$GH_OWNER" -f name="$GH_NAME" -f query='
                query($owner:String!,$name:String!){repository(owner:$owner,name:$name){
                  issues(states:OPEN){totalCount} pullRequests(states:OPEN){totalCount}}}' \
                --jq '"\(.data.repository.issues.totalCount) \(.data.repository.pullRequests.totalCount)"')
              # 查不到（沒登入、沒網路、沒權限）：把舊數字清掉，不拿過期的數字繼續顯示；等 GH_TTL 再試
              [[ $counts =~ ^[0-9]+\ [0-9]+$ ]] || counts="- -"
              put "$GH_CACHE" "$NOW $counts"
            ) </dev/null >/dev/null 2>&1 &
          fi
        fi
      fi
      ;;
  esac
fi

# ── 🔀 目前分支的 PR ──（Claude Code 直接給，不用外呼）
PR_INFO=""
if [ -n "$PR_NUM" ] && [ "$PR_NUM" -gt 0 ]; then
  case $PR_STATE in
    approved)                  PR_ICON=" ✅" ;;
    changes_requested)         PR_ICON=" 💬" ;;
    pending | review_required) PR_ICON=" 👀" ;;
    draft)                     PR_ICON=" 📝" ;;
    '' | *[!A-Za-z0-9_-]*)     PR_ICON="" ;;
    *)                         PR_ICON=" $PR_STATE" ;;   # 之後才出現的新狀態：先照字面顯示
  esac
  PR_INFO="🔀#${PR_NUM}${PR_ICON}"
fi

# ── rate limit ──
# 5h 與 7d 各自獨立：有的方案只送其中一個，所以不能把 7d 掛在 5h 底下。
RATE_INFO=""
if [ -n "$RATE_5H" ] || [ -n "$RATE_7D" ]; then
  # 燈號跟著比較滿的那個窗口：這週用到 95% 就是紅燈，即使 5h 窗口才 10%
  LEAD=${RATE_5H:-0}
  [ "${RATE_7D:-0}" -gt "$LEAD" ] && LEAD=$RATE_7D
  if [ "$LEAD" -ge 80 ]; then RATE_INFO="🔴"
  elif [ "$LEAD" -ge 50 ]; then RATE_INFO="🟡"
  else RATE_INFO="🟢"; fi
  [ -n "$RATE_5H" ] && RATE_INFO="$RATE_INFO 5h:${RATE_5H}%"
  [ -n "$RATE_7D" ] && RATE_INFO="$RATE_INFO 7d:${RATE_7D}%"
  # 5h 的重設頂多幾小時後，給時刻就夠；只有 7d 時可能是好幾天後，要帶日期
  if [ -n "$RATE_5H" ]; then
    [ -n "$RESET_5H" ] && fmt_time '%H:%M' "$RESET_5H" && RATE_INFO="$RATE_INFO ↻$REPLY"
  elif [ -n "$RESET_7D" ]; then
    fmt_time '%m/%d %H:%M' "$RESET_7D" && RATE_INFO="$RATE_INFO ↻$REPLY"
  fi
fi

printf -v COST '%d.%04d' $((COST_E4 / 10000)) $((COST_E4 % 10000))

SEG_DIR="📁 $FOLDER"
SEG_GIT=$GIT_INFO
SEG_GH=$GH_INFO
SEG_PR=$PR_INFO
SEG_MODEL="🥢 $MODEL"
SEG_COST="💰\$$COST"
SEG_CTX="📐${CTX_PCT}%"
SEG_RATE=$RATE_INFO
SEG_TIME=""
[ -n "$CLOCK" ] && SEG_TIME="🕐$CLOCK"   # 時間格式化不出來（舊 bash 又沒有 date）就整段不顯示
if [ -n "$NOTE" ]; then SEG_MODEL=$NOTE; SEG_COST=""; SEG_CTX=""; fi

# ═══════════════════════════════════════════
# 組合資訊列；終端機太窄就依 DROP_ORDER 一次拿掉一段
# ═══════════════════════════════════════════
join_line2() {
  local seg
  LINE2=$SEG_DIR
  for seg in "$SEG_GIT" "$SEG_GH" "$SEG_PR" "$SEG_MODEL" "$SEG_COST" "$SEG_CTX" "$SEG_RATE" "$SEG_TIME"; do
    [ -n "$seg" ] && LINE2="$LINE2 | $seg"
  done
}

# disp_w 字串 → W（顯示寬度，欄）。字串是 UTF-8 bytes，用起始 byte 分類，不必 fork：
#   ASCII 與 2-byte 字元（拉丁、希臘…）1 欄；3-byte（中日韓）與 4-byte（emoji）2 欄。
#   ↻ 是 3-byte 卻只佔 1 欄，另外扣回來。其他窄的 3-byte 符號會多算 1 欄，寧可高估。
disp_w() {
  local s=$1 t
  t=${s//[$'\x80'-$'\xBF']/}    # 拿掉接續 byte，剩下一個字元一個 byte
  W=${#t}
  t=${t//[$'\x01'-$'\xDF']/}    # 再拿掉 ASCII 與 2-byte 字元，剩下的都是寬字元
  W=$((W + ${#t}))
  t=${s//↻/}
  W=$((W - (${#s} - ${#t}) / 3))
}

join_line2
if [ "$MAX_W" -gt 0 ]; then
  for drop in $DROP_ORDER; do
    disp_w "$LINE2"
    [ "$W" -le "$MAX_W" ] && break
    case $drop in
      time)  SEG_TIME="" ;;
      cost)  SEG_COST="" ;;
      pr)    SEG_PR="" ;;
      gh)    SEG_GH="" ;;
      model) SEG_MODEL="" ;;
      rate)  SEG_RATE="" ;;
      ctx)   SEG_CTX="" ;;
      git)   SEG_GIT="" ;;
      *)     continue ;;
    esac
    join_line2
  done
fi

printf '%s\n%s\n' "$BELT" "$LINE2"
exit 0   # exit code 不是 0 的話 Claude Code 會把整條 status line 清空
