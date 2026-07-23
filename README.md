# claude-code-statusline

A status line for [Claude Code](https://claude.com/claude-code). It shows the
model, reasoning effort, working directory, a context-window bar, and a running
cost and token count for the whole thread.

```
Opus 4.8 (1M context) high │ ~/Documents/my-project │ context █░░░░░░░░░ 8% 81.0K/1.00M │ session ~US$45.00 · 1.20M total · 972.0K cache reads │ 5h 42% │ 7d 18%
```

## What it shows

Left to right:

| Part | Example | Meaning |
| --- | --- | --- |
| model | `Opus 4.8 (1M context)` | The model you're talking to. |
| effort | `high` | Reasoning effort (`low`/`medium`/`high`/`xhigh`/`max`). Hidden if the model has no effort setting. |
| path | `~/Documents/my-project` | Working directory, with your home folder shortened to `~`. |
| branch | `main` | Current git branch. Shown only inside a git repo. |
| context | `context █░░░░░░░░░ 8% 81.0K/1.00M` | How full the current context window is: bar, percent, and tokens-loaded / window-size. |
| session | `session ~US$45.00 · 1.20M total · 972.0K cache reads` | Cost of the whole thread (USD, color-coded), then the whole-thread token total and the cache reads within it. All of it comes from Claude Code's local transcript. |
| 5h / 7d | `5h 42% reset 8pm` `7d 18%` | Share of your rolling 5-hour / 7-day plan usage. The 5h segment also shows when the window resets. Pro/Max only. |

`context` and `session` are different numbers, and `session` is where the cost
estimate lives. See [`context` vs `session`](#context-vs-session) below.

## Prerequisites

- **bash**: the script uses arrays and `$'...'`, so `sh`/`dash` won't run it.
- **[jq](https://jqlang.github.io/jq/)**: parses the JSON Claude Code sends.
  - macOS: `brew install jq`
  - Debian/Ubuntu: `sudo apt install jq`
  - If it's missing, the status line prints a one-line hint instead of breaking.
- **awk**: used for the K/M number formatting. Present on macOS and every Linux.
- **git**: optional. Only used to show the current branch; without it, that
  segment is skipped.
- A terminal with 256-color support (any modern one). No Nerd Font needed. The
  bar is plain Unicode blocks and the colors are standard ANSI.

Use Claude Code v2.1.132 or newer. That's the version whose status-line JSON
exposes the `context_window` and per-turn token fields this script reads. The
`session` segment also reads the transcript Claude Code writes locally; if that
isn't available, it just drops that one segment.

## Install

### Quick (recommended)

One line, no clone needed:

```bash
curl -fsSL https://raw.githubusercontent.com/swawibe/claude-code-statusline/main/install.sh | bash
```

Or, from a clone of this repo:

```bash
./install.sh
```

Either way it installs `jq` if needed, copies the script to
`~/.claude/statusline.sh`, and registers it in `~/.claude/settings.json`. It
merges into your existing settings and backs them up to `settings.json.bak`
first. Re-running is safe. Restart Claude Code if it's already open.

### Manual

1. Copy the script somewhere stable:

   ```bash
   cp statusline.sh ~/.claude/statusline.sh
   chmod +x ~/.claude/statusline.sh
   ```

2. Add a `statusLine` key to `~/.claude/settings.json`.

   It's a top-level key, so it goes anywhere inside the outermost `{ }`,
   alongside whatever you already have. If the file doesn't exist yet, create it
   with just this:

   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "bash ~/.claude/statusline.sh"
     }
   }
   ```

   If you already have settings, add it next to your existing keys. Order
   doesn't matter, just remember the comma between entries:

   ```json
   {
     "model": "sonnet",
     "permissions": { "...": "..." },

     "statusLine": {
       "type": "command",
       "command": "bash ~/.claude/statusline.sh"
     }
   }
   ```

   (JSON has no trailing commas: the last key before the closing `}` must not
   have a comma after it.)

The status line shows up after the next message. Nothing else to run.

## `context` vs `session`

**`context`** is what's loaded right now. The bar and `81.0K/1.00M` are the
current window. It rises as you work and drops after `/compact`. The bar goes
green, then yellow at 70%, then red at 90%.

**`session`** is the whole thread's running **cost** and **token total**: the
price first (color-coded), then the total tokens, then the cache reads within
that total. Both come from Claude Code's local transcript, so they cover the
full thread, including across `/compact` and `claude --resume`, plus any
subagents the thread spawned.

### The cost estimate

The price (`~US$45.00`) comes from the transcript's per-model token usage priced
at Anthropic's base rates. It matches the Console billing CSVs to within about
0.3%. The status line only ever prices the
**current** thread, whose transcript is complete and on disk, so the "old data
gets purged" caveat that limits historical totals doesn't apply. The `~` marks
it an estimate; for the authoritative number use `/usage` or the
[Console](https://platform.claude.com/usage).

#### Why not Claude Code's own cost number?

Claude Code hands the status line a `cost.total_cost_usd` field, and printing
that would save the math. It doesn't work for a whole-thread total, because the
field is scoped to a single process. Start a session and it counts up fine, but
`claude --resume` (or `--continue`, or reopening the session in a new window)
resets it to zero, because the new process only knows the turns made since it
started. Long sessions get resumed all the time, so the field usually reports a
fraction of what the thread cost. I measured it: one turn billed at $0.033, then
a resume and one more turn, and the counter read $0.003. Turn one no longer
counted.

Summing the transcript avoids that. The transcript is the whole thread on disk,
so the total covers everything, `/compact` and resume included. That's why the
script does its own arithmetic.

It's not more accurate, either. Claude Code computes that field the same way this
script does: token usage times a per-model rate. Nothing in the transcript
stores a dollar amount for it to read. When I checked, its rates matched the
table below to the cent.

Rates by model family, USD per million tokens (edit the `rate()` table in the
script if Anthropic changes prices):

| Family | Input | Output | Cache write (5m) | Cache read |
| --- | --- | --- | --- | --- |
| Fable 5 / Mythos 5 | $10 | $50 | $12.50 | $1.00 |
| Opus 4.6 / 4.7 / 4.8 | $5 | $25 | $6.25 | $0.50 |
| Sonnet 4.5 / 4.6 / 5 | $3 | $15 | $3.75 | $0.30 |
| Haiku 4.5 | $1 | $5 | $1.25 | $0.10 |

A model that matches none of these (a future launch) is left **unpriced**: the
price is hidden for that render, tokens still show, and nothing breaks, until you
add its family to the table. Cost color is green up to the warn threshold, yellow
above it, and red above the crit threshold (defaults US$50 / US$100).

**Why USD only?** Anthropic bills in USD, so that's the real billing currency. If
you're outside the US, your card converts to local funds at its own rate plus an
FX fee, which no fixed multiplier here could match, so it stays in USD. It's also
a *list-price* estimate: account discounts or credits aren't reflected. Whether it
shows at all, and the thresholds, are configurable; see
[Configuration](#configuration).

### The token counts

`1.20M total · 972.0K cache reads` are the raw counts: the whole-thread total,
then the cache reads inside it. The total sums all four billable token types:

| Type | What it is |
| --- | --- |
| input | fresh tokens you send |
| output | tokens the model generates |
| cache write | new content written to the prompt cache |
| cache read | cached context re-sent every turn (usually the bulk of the count) |

A thread can show tens of millions of tokens yet cost only tens of dollars. Cache
reads dominate the *count* but are the *cheapest* type (~90% below fresh input),
so the dollar figure is that count re-weighted by per-type price. These are the
same four the Console meters under **Input / Prompt caching write / Prompt caching
read / Output**.

`transcript_path` is a documented field, but the transcript's internal shape is
not, so the read is best-effort: if the file is missing or its format ever
changes, the `session` segment drops out and the rest of the line is unaffected.

`5h` / `7d` only appear for Claude.ai Pro/Max accounts (the plan-usage fields
aren't in the JSON otherwise). Any segment whose data is missing is dropped, so
the line stays tidy on any plan or model.

## Configuration

Everything works out of the box with no config; cost shows in USD. To retune the
color thresholds or turn the cost off, edit **`~/.claude/statusline.conf`** (the
installer drops a fully-commented one there). It's a plain `VAR=value` file,
sourced by the script:

```sh
# ~/.claude/statusline.conf
STATUSLINE_SHOW_COST=1         # 0 to hide the price (tokens only)
STATUSLINE_COST_WARN=50        # USD; above this the price is yellow
STATUSLINE_COST_CRIT=100       # USD; above this it's red
```

| Variable | Default | Effect |
| --- | --- | --- |
| `STATUSLINE_SHOW_COST` | `1` | `0` hides the price entirely (tokens only). |
| `STATUSLINE_COST_WARN` | `50` | USD amount above which the price turns yellow. |
| `STATUSLINE_COST_CRIT` | `100` | USD amount above which it turns red. |

There's no currency-conversion option, on purpose; see
[Why USD only?](#the-cost-estimate) above.

**Why a config file and not just env vars?** The status line runs as a subprocess
of Claude Code, which only inherits environment variables in some setups. The CLI
picks up your shell's `export`s, but the **desktop app** (launched from the
Dock/Finder) does not. The config file is read directly by the script, so it
works everywhere. Environment variables still work as an override, which is handy
inline in the `settings.json` command:
`"command": "STATUSLINE_SHOW_COST=0 bash ~/.claude/statusline.sh"`. If you set the
same var in both, the file wins (it's sourced last).

## Tweaking it

The knobs are all near the top of the script:

- cost display → the `STATUSLINE_*` variables (see [Configuration](#configuration))
- model rates → the `rate()` table inside the session `jq` block
- cost number format → `format_cost`
- context-bar colors → the ANSI variables (`RED`, `YELLOW`, `GREEN`, etc.) and `color_for_pct`
- bar width → `width=10` in `make_bar`
- separator → `sep`
- drop a segment → delete its `parts+=(...)` block

## License

MIT. See [LICENSE](LICENSE).
