#!/usr/bin/env bash
# Installer for claude-code-statusline.
# Copies the script into ~/.claude and registers it in settings.json.
# Safe to re-run; your existing settings are backed up and preserved.
#
# Author: Swawibe Alam
# License: MIT
set -euo pipefail

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
DEST="$CLAUDE_DIR/statusline.sh"
SETTINGS="$CLAUDE_DIR/settings.json"
REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/swawibe/claude-code-statusline/main}"

say()  { printf '%s\n' "$*"; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

# Use the statusline.sh sitting next to this installer, or download it when we're
# being run straight from `curl ... | bash` (no local copy available).
tmp_src=""
trap '[ -n "$tmp_src" ] && rm -f "$tmp_src"' EXIT
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)
SRC="$script_dir/statusline.sh"
if [ ! -f "$SRC" ]; then
  command -v curl >/dev/null 2>&1 || die "need curl to download statusline.sh"
  tmp_src=$(mktemp)
  curl -fsSL "$REPO_RAW/statusline.sh" -o "$tmp_src" || die "failed to download statusline.sh from $REPO_RAW"
  SRC="$tmp_src"
fi

# jq is required to read Claude Code's JSON. Try to install it if it's missing.
if ! command -v jq >/dev/null 2>&1; then
  say "jq is required but not installed."
  if command -v brew >/dev/null 2>&1; then
    say "Installing jq with Homebrew..."
    brew install jq
  elif command -v apt-get >/dev/null 2>&1; then
    say "Installing jq with apt..."
    sudo apt-get update && sudo apt-get install -y jq
  else
    die "please install jq manually, then re-run (https://jqlang.github.io/jq/)"
  fi
fi

# Install the script.
mkdir -p "$CLAUDE_DIR"
cp "$SRC" "$DEST"
chmod +x "$DEST"
say "Installed script -> $DEST"

# Seed a commented config on first run only — never clobber one the user edited.
CONF="$CLAUDE_DIR/statusline.conf"
if [ -f "$CONF" ]; then
  say "Kept your existing $CONF"
else
  cat > "$CONF" <<'CONF_EOF'
# claude-code-statusline configuration. Plain shell, sourced by statusline.sh —
# use VAR=value with no spaces around "=". Works for the CLI and the desktop app.
# All settings are optional; the defaults are shown below.
#
# The cost shown is a USD list-price estimate. Anthropic bills in USD, so that
# is the real billing currency — your card converts to local funds at its own
# rate and fees, which no fixed number could match, so there is intentionally no
# currency-conversion option. List prices also don't reflect account discounts.

# Show the session cost estimate. 1 = show (default), 0 = hide (tokens only).
#STATUSLINE_SHOW_COST=1

# Color thresholds, in USD. At/below WARN is green; above WARN yellow; above CRIT red.
#STATUSLINE_COST_WARN=50
#STATUSLINE_COST_CRIT=100
CONF_EOF
  say "Wrote $CONF (all commented; edit to toggle cost / set thresholds)"
fi

CMD="bash $DEST"

# Register in settings.json without disturbing anything else.
if [ -f "$SETTINGS" ]; then
  jq empty "$SETTINGS" 2>/dev/null \
    || die "$SETTINGS is not valid JSON; fix it (or move it aside) and re-run"
  backup="$SETTINGS.bak"
  cp "$SETTINGS" "$backup"
  tmp=$(mktemp)
  jq --arg cmd "$CMD" '.statusLine = {type: "command", command: $cmd}' "$SETTINGS" > "$tmp"
  mv "$tmp" "$SETTINGS"
  say "Updated $SETTINGS (backup: $backup)"
else
  jq -n --arg cmd "$CMD" '{statusLine: {type: "command", command: $cmd}}' > "$SETTINGS"
  say "Created $SETTINGS"
fi

# Smoke test: feed sample JSON through the installed script.
sample='{"session_id":"install-smoke-test","model":{"display_name":"Sonnet"},"workspace":{"current_dir":"'"$HOME"'"},"context_window":{"used_percentage":10,"total_input_tokens":20000,"context_window_size":200000,"current_usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":0}}}'
if [ -z "$(printf '%s' "$sample" | bash "$DEST")" ]; then
  die "smoke test produced no output; something is wrong"
fi

say ""
say "Done. The status line appears after your next message in Claude Code."
say "(Restart Claude Code if it's already running.)"
say "Toggle the cost estimate and its thresholds in $CLAUDE_DIR/statusline.conf"
