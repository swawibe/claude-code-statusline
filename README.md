# claude-code-statusline

A status line for [Claude Code](https://claude.com/claude-code). Shows the
model, reasoning effort, working directory, a context-window bar, and a running
token count for the whole thread.

```
Opus 4.8 (1M context) high │ ~/Documents/my-project │ context █░░░░░░░░░ 8% 81.0K/1.00M │ session 21.0K │ 5h 42% │ 7d 18%
```

## What it shows

Reading left to right:

| Part | Example | Meaning |
| --- | --- | --- |
| model | `Opus 4.8 (1M context)` | The model you're talking to. |
| effort | `high` | Reasoning effort (`low`/`medium`/`high`/`xhigh`/`max`). Hidden if the model has no effort setting. |
| path | `~/Documents/my-project` | Working directory, with your home folder shortened to `~`. |
| branch | `main` | Current git branch. Shown only inside a git repo. |
| context | `context █░░░░░░░░░ 8% 81.0K/1.00M` | How full the current context window is: bar, percent, and tokens-loaded / window-size. |
| session | `session 21.0K` | Running token total for the whole thread. |
| 5h / 7d | `5h 42% reset 8pm` `7d 18%` | Share of your rolling 5-hour / 7-day plan usage; the 5h segment also shows when the window resets. Pro/Max only. |

The two token numbers (`context` and `session`) mean different things — see
[The two token numbers](#the-two-token-numbers) below.

## Prerequisites

- **bash** — the script is bash (uses arrays and `$'...'`); `sh`/`dash` won't do.
- **[jq](https://jqlang.github.io/jq/)** — parses the JSON Claude Code sends.
  - macOS: `brew install jq`
  - Debian/Ubuntu: `sudo apt install jq`
  - If it's missing the status line prints a one-line hint instead of breaking.
- **awk** — used for the K/M number formatting. Present on macOS and every Linux.
- **git** — optional; only used to show the current branch. Without it that
  segment is simply skipped.
- A terminal with 256-color support (any modern one). No Nerd Font needed — the
  bar is plain Unicode blocks and the colors are standard ANSI.

Claude Code v2.1.132 or newer is recommended: it's the version whose status-line
JSON exposes the `context_window` and per-turn token fields this script reads.

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
`~/.claude/statusline.sh`, and registers it in `~/.claude/settings.json` —
merging into your existing settings and backing them up to
`settings.json.bak` first. Re-running is safe. Restart Claude Code if it's
already open.

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

   If you already have settings, add it next to your existing keys — order
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

## The two token numbers

**`context`** is what's loaded right now — the bar and `81.0K/1.00M` are the
current window. It rises as you work and drops after `/compact`. The bar goes
green → yellow at 70% → red at 90%.

**`session`** is the running total for the whole thread. Claude Code's JSON only
reports the current turn's tokens, so the script keeps the total itself in
`~/.claude/statusline-token-cache/<session_id>`. It survives `/compact` and
picks back up on `claude --resume`, even days later.

`session` counts each token once — new input, output, and cache-writes. It skips
cache-reads on purpose: those are the earlier conversation re-sent on every turn,
so counting them would tally the same tokens over and over. What's left is the
unique work done on the thread, which is the number that actually tracks cost.
It's a token count, not dollars — on a Pro/Max plan usage is included in the
subscription, so a dollar figure wouldn't mean anything and isn't shown.

`5h` / `7d` only appear for Claude.ai Pro/Max accounts (the plan-usage fields
aren't in the JSON otherwise). Any segment whose data is missing is dropped, so
the line stays tidy on any plan or model.

## Tweaking it

The knobs are all near the top of the script:

- colors → the ANSI variables (`RED`, `YELLOW`, `GREEN`, …)
- thresholds → `color_for_pct`
- bar width → `width=10` in `make_bar`
- separator → `sep`
- drop a segment → delete its `parts+=(...)` block

## License

MIT — see [LICENSE](LICENSE).
