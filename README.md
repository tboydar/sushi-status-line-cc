# 🍣 Sushi Status Line for Claude Code

![Sushi belt demo](assets/demo.gif)

Claude Code 的 status line 變成一條迴轉壽司輸送帶：每秒 🍣🍱🍤 從左往右流過，中間隨機空隙，idle 時也會動。帶子長度會自動貼齊終端機寬度。

## 預覽

連續 5 秒的輸送帶（注意 🍵 從左邊緩緩滑到右邊，新的壽司從左邊進場）：

```
▸═══════════════🍵════🍙═🍶══════════🍙══════════🦐═══════════════════🦑═🥟════▸
▸══════════════════🍵════🍙═🍶══════════🍙══════════🦐═══════════════════🦑═🥟═▸
▸🦑═══════════════════🍵════🍙═🍶══════════🍙══════════🦐═══════════════════🦑═▸
▸🍣═🦑═══════════════════🍵════🍙═🍶══════════🍙══════════🦐═══════════════════▸
▸🍤═🍣═🦑═══════════════════🍵════🍙═🍶══════════🍙══════════🦐════════════════▸
```

下方資訊列：

```
📁 my-project | 🌿 main | 🥢 Opus 4.7 | 💰$0.1234 | 📐26% | 🕐19:06:40
```

資料齊全時最長會是這樣：

```
📁 my-project | 🌿 main (+3) | issues:2, PRs:1 | 🔀#3 ✅ | 🥢 Opus 4.7 | 💰$0.1234 | 📐26% | 🟢 5h:12% 7d:34% ↻21:53 | 🕐19:06:40
```

| 段 | 意思 | 什麼時候出現 |
|---|---|---|
| `📁 my-project` | 目前資料夾 | 永遠 |
| `🌿 main (+3)` | git 分支。`(+3)` 是有變動的檔案數：已暫存、未暫存、未追蹤都算，同一個檔案只算一次，超過 999 個顯示 `(+999+)` | 在 git repo 裡 |
| `issues:2, PRs:1` | 這個 repo 在 GitHub 上 open 的 issue / PR 數量 | origin 在 github.com，且有裝並登入 [`gh`](https://cli.github.com/)（[細節](#github-的-issue--pr-數量)） |
| `🔀#3 ✅` | 目前分支的 PR 編號與審查狀態：✅ approved、👀 pending、💬 changes requested、📝 draft | 目前分支有開著的 PR |
| `🥢 Opus 4.7` | 模型 | 永遠 |
| `💰$0.1234` | 這個 session 的花費（Claude Code 用牌價估的，不等於帳單） | 永遠 |
| `📐26%` | context window 用量 | 永遠 |
| `🟢 5h:12% 7d:34% ↻21:53` | rate limit：5 小時與 7 天窗口各用了多少、5 小時窗口幾點重設。燈號跟著比較滿的那個窗口，50% 以上 🟡、80% 以上 🔴。只有 7 天窗口時 `↻` 會帶日期（`↻11/23 02:13`） | Claude Code 有回傳 `rate_limits`（claude.ai 訂閱方案，且 session 已有第一次 API 回應）。兩個窗口各自獨立，有哪個顯示哪個 |
| `🕐19:06:40` | 現在時間 | 永遠 |

### 終端機不夠寬時

帶子會跟著縮短；資訊列塞不下時，依 🕐 → 💰 → 🔀 → issues → 🥢 → rate limit → 📐 → 🌿 的順序一次拿掉一段（📁 永遠留著），順序可以用 [`SUSHI_DROP_ORDER`](#自訂參數) 改：

```
寬 100 欄：丟掉 🕐、💰、🔀
▸═══════════════🍵════🍙═🍶══════════🍙══════════🦐═══════════════════🦑═🥟═══════🦐═🍣═══════▸
📁 my-project | 🌿 main (+3) | issues:2, PRs:1 | 🥢 Opus 4.7 | 📐26% | 🟢 5h:12% 7d:34% ↻21:53

寬 80 欄：再丟掉 issues
▸═══════════════🍵════🍙═🍶══════════🍙══════════🦐═══════════════════🦑═▸
📁 my-project | 🌿 main (+3) | 🥢 Opus 4.7 | 📐26% | 🟢 5h:12% 7d:34% ↻21:53

寬 60 欄：再丟掉 🥢 與 rate limit
▸═══════════════🍵════🍙═🍶══════════🍙══════════🦐════▸
📁 my-project | 🌿 main (+3) | 📐26%
```

> 想看動畫版？見本 repo `assets/demo.tape`，用 [vhs](https://github.com/charmbracelet/vhs) 可以自動產生 GIF。

---

## 相容性

| 平台 | 狀態 |
|---|---|
| macOS（內附的 bash 3.2、BSD `date`） | ✅ 測試全過 |
| Linux：Debian 13、Ubuntu 20.04（glibc、bash 5、GNU `date`） | ✅ 測試全過 |
| Linux：Alpine 3.24（musl、bash 5、busybox `date`） | ✅ 測試全過 |
| Windows（WSL / Git Bash） | 🤔 理論可行，尚未實測，歡迎回報 |
| Windows（原生 PowerShell） | ❌ 不支援（腳本是 bash） |

需要的工具：

- **bash 3.2 以上**（macOS 內附的就夠）
- **jq 1.6 以上**（實測 1.6 – 1.8）
- **git 2.15 以上**（實測 2.25 – 2.54）。2.11 – 2.14 也能顯示，但不認得 `GIT_OPTIONAL_LOCKS`，render 時可能回寫 index。沒裝 git 也能跑，只是沒有 🌿
- [`gh`](https://cli.github.com/)：選用，只有 `issues:N, PRs:M` 那一段會用到

平常每次 render 啟動的外部行程只有 `jq` 一次，加上 bash 3.2 才需要的 `date`；`git` 預設 5 秒才問一次，其餘全是 bash 內建。`stat -f`、`sed -i ""` 這類 BSD-only 指令一概不用。

唯一的平台分歧是把 unix epoch 格式化成時刻（🕐 和 `↻` 都要）：bash 4.2 以上有內建的 `printf '%(...)T'`，不用 fork，Linux 幾乎都走這條；macOS 內附的 bash 3.2 沒有，退回 `date`。而 BSD 的 `date -r <epoch>` 到了 GNU coreutils 與 busybox 是「讀檔案 mtime」，要改用 `date -d @<epoch>`，所以兩種都試：

```bash
fmt_time() {
  printf -v REPLY "%($1)T" "$2" 2>/dev/null && return
  REPLY=$(cd / 2>/dev/null; date -r "$2" "+$1" 2>/dev/null || date -d "@$2" "+$1" 2>/dev/null)
  [ -n "$REPLY" ]
}
```

`cd /` 是為了 GNU 那一側：目前目錄裡要是剛好有個檔名等於那個 epoch 的檔案，`date -r` 會「成功」讀到它的 mtime，給出錯的時間。三種都失敗時就不顯示 `↻`，其餘欄位照常。

在 Linux 上 bash 都夠新，`date` 這條退回路線平常根本跑不到，所以測試會刻意把內建的 `printf` 蓋掉、強迫走一次 GNU 與 busybox 的 `date`。

---

## 從零開始安裝

### 1. 先有 Claude Code

這個 status line 只適用於 [Claude Code](https://claude.com/product/claude-code)（Anthropic 官方 CLI）。還沒有的話：

```bash
# macOS / Linux
curl -fsSL https://claude.com/claude-code/install.sh | bash
```

裝好後執行 `claude` 開第一個 session，確認能跑就 `exit` 離開。

> 需要 **Claude Code 2.x 以上**（`refreshInterval` 在 2.x 才加進去）。帶子自動貼齊寬度靠的是 Claude Code 放進 `COLUMNS` 的終端機寬度；太舊的版本沒有這個值，帶子會退回固定 30 格。

### 2. 確認相依工具

```bash
command -v bash && bash --version | head -1   # 需要 bash 3.2+
command -v jq   && jq --version               # 處理 status line 的 JSON 輸入
```

- macOS：`jq` 若沒裝 → `brew install jq`
- Ubuntu / Debian：`sudo apt install jq`

### 3. 取得本 repo

```bash
# 放到任一位置，例如 ~/.claude/hud/sushi
git clone https://github.com/tboydar/sushi-status-line-cc.git ~/.claude/hud/sushi
cd ~/.claude/hud/sushi
```

### 4. 預覽（選擇性，但推薦）

先看看是不是你喜歡的樣子，再決定要不要掛上 Claude Code：

```bash
./demo.sh
```

終端機會每秒更新一次壽司帶，按 `Ctrl+C` 離開。

### 5. 掛到 Claude Code

```bash
./install.sh
```

會印出要貼進 `~/.claude/settings.json` 的 JSON 片段，長這樣：

```json
"statusLine": {
  "type": "command",
  "command": "/your/clone/path/sushi-statusline.sh",
  "refreshInterval": 1
}
```

**貼進 settings.json 的步驟：**

1. 打開 `~/.claude/settings.json`（沒有就新建一個 `{}` 空物件）
2. 把上面的 `"statusLine": { ... }` 合併到最上層
3. 檢查整份 JSON 仍合法：`jq . ~/.claude/settings.json`

完整的 `settings.json` 長這樣（最小範例）：

```json
{
  "statusLine": {
    "type": "command",
    "command": "/Users/you/.claude/hud/sushi/sushi-statusline.sh",
    "refreshInterval": 1
  }
}
```

`install.sh` 本身不會動你的設定檔。不想手動貼的話，`./install.sh --json` 只印出 JSON 物件，可以自己交給 jq 合併（先備份）：

```bash
cp ~/.claude/settings.json ~/.claude/settings.json.bak
jq -s '.[0] * .[1]' ~/.claude/settings.json <(./install.sh --json) > ~/.claude/settings.json.new \
  && mv ~/.claude/settings.json.new ~/.claude/settings.json
```

### 6. 重啟 Claude Code

關掉現有 session（`exit`）然後重新 `claude`，壽司帶就會出現在底部。

---

## 自訂參數

兩種改法：直接編輯 `sushi-statusline.sh` 頂端的預設值，或用環境變數覆寫。用環境變數就不必動腳本，之後 `git pull` 更新不會衝突：

```json
"command": "SUSHI_EMOJI='🍜 🍥 🥚 🍖' SUSHI_EMPTY_PROB=50 /your/clone/path/sushi-statusline.sh"
```

| 環境變數 | 腳本裡的變數 | 預設 | 說明 |
|---|---|---|---|
| `SUSHI_SLOTS` | `SLOTS_VISIBLE` | `0` | 帶子格數。`0` = 自動貼齊終端機寬度；填數字就固定格數（還是不會超出終端機） |
| `SUSHI_EMPTY_PROB` | `EMPTY_PROB` | `65` | 空格機率（%）。30 很密、80 很稀疏 |
| `SUSHI_EMOJI` | `SUSHI=(...)` | 12 種 | 壽司 emoji 池，用空白隔開。每個都要是佔 2 欄的 emoji |
| `SUSHI_MARGIN` | `MARGIN` | `4` | 終端機寬度要扣掉的邊。`settings.json` 的 `statusLine` 有設 `padding` 的話，改成 `4 + 2 × padding` |
| `SUSHI_DROP_ORDER` | `DROP_ORDER` | `time cost pr gh model rate ctx git` | 終端機太窄時，資訊列由左到右依序捨棄哪些段 |
| `SUSHI_GIT_TTL` | `GIT_TTL` | `5` | git 狀態快取幾秒；`0` = 每次都問 git |
| `SUSHI_GH` | `SHOW_GH` | `1` | `0` = 不查 GitHub 的 issue / PR 數量 |
| `SUSHI_GH_TTL` | `GH_TTL` | `300` | GitHub 數量快取幾秒 |

改完執行 `./demo.sh` 即時看效果（環境變數一樣吃：`SUSHI_EMPTY_PROB=30 ./demo.sh`）。

---

## 運作原理

### L→R 滾動的數學

關鍵：**每個 slot 的內容只取決於 `slot_id = position - NOW`**。

```
C(p, t)     = g(p - t)
C(p+1, t+1) = g((p+1) - (t+1)) = g(p - t) = C(p, t)  ✓
```

時間推進 1 秒，同一個內容會出現在**右邊一格**——這就是 L→R。帶子不需要保存任何 state，每次渲染都是 pure function。

### 每格固定 3 欄

一格不是 `═══`，就是「一盤壽司 + 一個 `═`」。emoji 佔 2 欄，所以兩種都剛好 3 欄，帶子總寬恆為 `3 × 格數 + 2`。這樣才能算出剛好填滿終端機的格數，右邊的 `▸` 也不會隨著壽司進出而左右抖動。

### 把 slot_id 攪亂

「這格空不空」和「放哪一盤」都要看起來隨機，但同一個 `slot_id` 又必須永遠得到同一個答案。做法是把 `slot_id` 丟進一個整數雜湊，再從結果讀出兩個決定：

```bash
h=$(( (p - NOW) & 0xFFFFFFFF ))
h=$(( (((h >> 16) ^ h) * 0x45D9F3B) & 0xFFFFFFFF ))
h=$(( (((h >> 16) ^ h) * 0x45D9F3B) & 0xFFFFFFFF ))
h=$(( (h >> 16) ^ h ))

h % 100             # 這格空不空（跟 EMPTY_PROB 比）
h / 100 % NUM_SUSHI # 放哪一盤
```

**只「乘一個大質數再取餘數」是不夠的。** 這個專案的第一版就是這樣寫：

```bash
h2 = (slot_id * 374761393 + 668265263) % 12
```

看起來很亂，但 `slot_id` 是連續整數，`a·x + c` 對連續的 `x` 只是公差為 `a` 的等差數列，取餘數之後公差變成 `a mod 12`。而 `374761393 mod 12` 剛好是 1——所以壽司其實是照著陣列順序一盤接一盤輪播；決定空格的那條式子同理，每 100 格循環一次，整條帶子每 300 秒重複。中間的 xor-shift（`(h >> 16) ^ h`）才是把高位元攪進低位元、打破這種線性關係的步驟。

### bash 的負數

`slot_id = p - NOW` 必為很大的負數，而 bash 的 `%` 會保留被除數的正負號：

```bash
$ echo $(( -5 % 100 ))
-5          # 不是 95
```

直接拿去當陣列索引會出事。所以第一步先 `& 0xFFFFFFFF` 取低 32 位元，之後全程都是非負數；乘數挑小於 2²⁷ 的，乘積也不會超出 bash 的 64 位元整數。

### `refreshInterval: 1` 讓它真的動

Claude Code 的 status line 預設**只在事件觸發時重繪**（新訊息、權限模式切換等），idle 時會卡住。2.x 的 `settings.json` 支援 `refreshInterval`，單位秒，最小值 1：

```json
"statusLine": { ..., "refreshInterval": 1 }
```

官方文件：<https://code.claude.com/docs/en/statusline.md>

### 貼齊終端機寬度

status line 腳本的輸出是被 Claude Code 接走的，沒有接著終端機，所以 `tput cols`、`stty size` 問不到寬度。Claude Code 會在每次執行前把寬度放進環境變數 `COLUMNS`，[官方建議](https://code.claude.com/docs/en/statusline.md)每行至少留 4 欄給它自己的邊距，所以可用寬度是 `COLUMNS - 4`。

資訊列要知道自己多寬才能決定丟不丟段。腳本開頭設了 `LC_ALL=C`，字串全部當 bytes 處理，再用 UTF-8 的起始 byte 分類：ASCII 與 2-byte 字元算 1 欄，3-byte（中日韓）與 4-byte（emoji）算 2 欄。全程是 bash 的字串替換，不用為了量寬度 fork 一個 python 或 awk。

### 每秒跑一次，所以能不 fork 就不 fork

`refreshInterval: 1` 代表這支腳本一天要跑好幾萬次。幾個刻意的選擇：

- **jq 只呼叫一次**，所有欄位一起取出，四捨五入也在 jq 裡做完（jq 不看 locale；bash 的 `printf '%.0f'` 在小數點是逗號的 locale 會把 `12.4` 當成壞數字）。
- **git 只呼叫一次**：`git status --porcelain=v2 --branch` 同時給分支與變動清單。結果快取 5 秒，其間的 render 完全不碰 git。
- **`GIT_OPTIONAL_LOCKS=0`**：一般的 `git status` 會順手回寫 index、短暫佔用 `index.lock`。每秒來一次的話，遲早會撞上 Claude 正在跑的 `git commit`。
- **雜湊用算術展開直接算**，不透過 `$(...)`——每個 `$(...)` 都是一次 fork，30 格帶子就是 60 次。

快取放在 `${TMPDIR:-/tmp}/sushi-statusline-<uid>/`，只認自己擁有的目錄。時間戳寫在檔案內容裡而不是看 mtime，就不必用 BSD / GNU 寫法不同的 `stat`；寫入一律先寫暫存檔再 `mv`。

### 跑太久會被砍掉

下一次更新到來時，Claude Code 會直接砍掉還沒跑完的那一次 render。腳本只要有一步慢過 `refreshInterval`，就永遠畫不出來。為此有兩個設計：

- **變動檔案數到 1000 就停**（顯示 `(+999+)`）。沒有 ignore 的 `node_modules` 可以有好幾萬個未追蹤檔案，bash 逐行數完要好幾秒。
- **問 git 之前先用舊結果佔住快取**。repo 大到 `git status` 本身就超時的話，那一次 render 會被砍，但接下來 5 秒內的 render 會直接用佔位的結果，不會每一次都重跑 git、每一次都被砍。

### 不替外來的東西執行或顯示任何指令

status line 是無人看管、自動反覆執行的，資料夾名稱、分支名稱、repo 設定都可能來自一個剛解壓縮的陌生專案：

- 呼叫 git 時加上 `-c core.fsmonitor=false`。repo 自己的 `.git/config` 可以把 `core.fsmonitor` 設成任意指令，一般的 `git status` 會去執行它。
- 所有要印出來的外來字串都先濾掉控制字元，包含 C1（U+0080–9F）與雙向覆寫字元（U+202E 等），不讓它們操控終端機或把畫面順序弄反。
- 拿來組檔名的值（`session_id`、repo 的 owner / name）只收固定的字元集，其餘一律當成沒有。

### GitHub 的 issue / PR 數量

`issues:2, PRs:1` 是整支腳本**唯一會連網**的地方，機制如下：

- 只在 origin 是 `github.com`（用 Claude Code 解析好的 `workspace.repo`）、且找得到 `gh` 時啟用。
- render 當下只讀快取，**絕不等網路**。快取超過 300 秒，就在背景用你本機登入的 `gh` 對該 repo 發一次 GraphQL 查詢，這一輪先顯示舊數字，查到了下一輪才換新；第一次還沒有快取時先不顯示。
- 查詢失敗（沒登入、沒網路、私有 repo 沒權限）就不顯示，等下一個 300 秒才重試。

不想要的話設 `SUSHI_GH=0`。

---

## 延伸玩法

### 壽司旁邊加筆記標題

這版刻意把文字拿掉（留白比資訊量重要），但基礎邏輯通用。找到這行：

```bash
BELT+="${SUSHI[h / 100 % NUM_SUSHI]}═"
```

改成從你自己的文字池（例如 `~/notes/*.md` 的標題）再抽一則。`h` 的商還能繼續往下除，三個決定互不干擾：

```bash
BELT+="${SUSHI[h / 100 % NUM_SUSHI]}${ITEMS[h / 100 / NUM_SUSHI % NUM_ITEMS]} "
```

要注意：加了文字，一格就不再是固定 3 欄，帶子會超出自動算好的寬度——請用 `SUSHI_SLOTS` 改成固定格數。

記得用快取檔存掃描結果，不要每次渲染都 I/O。**但寫快取要用「暫存檔 + `mv`」，別直接 `> "$CACHE"`。** Claude Code 每次事件都會重繪 status line，多個 session 還會同時跑；就地截斷再逐行寫，另一個行程就可能讀到半截檔案——最慘讀到 0 行，畫面閃一下空清單。

```bash
tmp="${CACHE}.$$"
{ ...掃描... } > "$tmp"
mv -f "$tmp" "$CACHE"    # 同一個檔案系統內的 mv 是原子操作，讀者只會看到舊的或新的
```

這不是理論風險：12 個併發實例在冷快取下讀取，就地寫入版有 55/60 次讀到殘缺內容（其中 35 次讀到 0 筆），換成 `mv` 後 60/60 正確。

### 換成拉麵、啤酒、行星……

改 `SUSHI=(...)` 陣列，或直接設 `SUSHI_EMOJI`。邏輯是通用的輸送帶，換 emoji 就變主題。

### 產生動畫 GIF

安裝 [vhs](https://github.com/charmbracelet/vhs)：

```bash
brew install vhs           # macOS
# 或從 GitHub release 下載
```

然後：

```bash
vhs assets/demo.tape
# → 產出 assets/demo.gif
```

---

## 疑難排解

| 症狀 | 原因 | 解法 |
|---|---|---|
| 帶子完全不動 | `settings.json` 沒加 `refreshInterval: 1` | 編輯補上 |
| 資訊列出現 `❗ 找不到 jq` | 沒裝 jq，或 Claude Code 啟動時的 `PATH` 找不到它 | `brew install jq` / `sudo apt install jq` |
| 某些 slot 顯示 `�` 或方框 | 終端字型不支援部分 emoji | 換等寬 emoji 字型（Fira Code + emoji fallback、Hack Nerd Font 等） |
| 帶子太擠或太空 | `EMPTY_PROB` 不合胃口 | 設 `SUSHI_EMPTY_PROB`，用 `./demo.sh` 試 |
| 帶子右邊空一大塊（固定 30 格） | Claude Code 太舊，沒有把寬度放進 `COLUMNS` | 更新 Claude Code，或用 `SUSHI_SLOTS` 自己指定格數 |
| 帶子或資訊列被截掉、尾端出現 `…` | `statusLine` 設了 `padding`，可用寬度比腳本以為的窄 | 把 `SUSHI_MARGIN` 設成 `4 + 2 × padding` |
| 帶子變成兩倍寬、被截掉一大半 | 終端機把 `═` 這類「寬度不明確」的字元當成全形（部分終端機的中日韓設定） | 關掉終端機的「ambiguous width 視為全形」選項，或用 `SUSHI_SLOTS` 把格數減半 |
| 資訊列少了幾段 | 終端機不夠寬，被依序捨棄了 | 拉寬視窗，或用 `SUSHI_DROP_ORDER` 調整誰先被丟 |
| `(+N)` 慢幾秒才更新 | git 狀態有 5 秒快取 | 正常；要即時就設 `SUSHI_GIT_TTL=0` |
| 沒有 `issues:N, PRs:M` | 沒裝或沒登入 `gh`、origin 不在 github.com、或才剛開（第一次要等背景查完） | `gh auth status` 確認登入；不需要就不用管 |
| 資訊列缺 rate limit | Claude Code 未回傳 `rate_limits` 欄位 | 正常，只有訂閱方案在第一次 API 回應之後才有 |
| `install.sh: permission denied` | 沒執行權限 | `chmod +x install.sh demo.sh sushi-statusline.sh` |

---

## 測試

```bash
bash tests/run.sh        # 需要 jq、git、python3
/bin/bash tests/run.sh   # macOS：指定用內附的 bash 3.2 跑
```

測試餵受控的 JSON 給主腳本、檢查實際輸出：用 `SUSHI_NOW` 把時間釘住，`PATH` 只留腳本允許 fork 的指令，顯示寬度另外用 python3 的 `unicodedata` 量。CI 會在 Ubuntu 與 macOS 上各跑一次，並對所有腳本跑 shellcheck。

---

## 檔案結構

```
sushi-status-line-cc/
├── README.md                  # 本檔
├── LICENSE                    # MIT
├── .gitignore
├── sushi-statusline.sh        # 主腳本
├── settings.example.json      # settings.json 設定片段範例
├── install.sh                 # 印出待貼 JSON（不自動改設定）
├── demo.sh                    # 本機預覽，不動設定
├── tests/
│   └── run.sh                 # 測試
├── .github/workflows/ci.yml   # shellcheck + 測試（Ubuntu、macOS）
└── assets/
    ├── demo.gif               # README 頂端的動畫
    └── demo.tape              # vhs 錄 GIF 腳本
```

## 命名小註

repo 一開始叫 `susi-status-line-cc`（俏皮的拼法），後來改名成 `sushi-status-line-cc`，和腳本檔名一致。舊網址 GitHub 會自動轉址，之前 clone 的不用動。

## 歡迎許願 / 回報

喜歡的話、用起來卡關、想到新口味（拉麵車、啤酒輸送帶、行星軌道？）都歡迎：

- 🐛 bug、平台相容性（WSL / Git Bash 實測）：[開 issue](https://github.com/tboydar/sushi-status-line-cc/issues/new)
- 💡 新功能、新主題、排版想法：一樣開 issue 聊
- 🍣 PR 非常歡迎——特別是 WSL 的實測回報、新 emoji 主題包。送 PR 前請先跑 `bash tests/run.sh`

這是小玩具專案，但既然公開了就持續收 feedback 慢慢長大。

## 授權

MIT。詳見 `LICENSE`。
