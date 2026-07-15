#!/usr/bin/env bash
# Claude Code status line. Reads the session JSON from stdin, prints one line.
# Requires jq. See README.md.
#
# Author: Swawibe Alam
# License: MIT

if ! command -v jq > /dev/null 2>&1; then
  printf 'statusline: jq not found (brew install jq / apt install jq)'
  exit 0
fi

input=$(cat)

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd')
model=$(echo "$input" | jq -r '.model.display_name // "Claude"')
effort=$(echo "$input" | jq -r '.effort.level // empty')
session_id=$(echo "$input" | jq -r '.session_id // empty')
ctx_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
ctx_tokens=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
ctx_max=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
hour_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
hour_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
week_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')

# Collapse $HOME to ~
dir="$cwd"
case "$dir" in
  "$HOME"*) dir="~${dir#$HOME}" ;;
esac

# Current git branch, if we're in a repo
branch=""
if git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
  branch=$(git -C "$cwd" symbolic-ref --quiet --short HEAD 2>/dev/null \
    || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
fi

# The JSON only reports tokens for the current turn, so we keep the running
# total ourselves, keyed by session_id. Cache-reads are excluded: they're the
# prior context re-sent every turn, so counting them re-counts the same tokens.
# Kept under ~/.claude (not /tmp) so it survives resumes days later.
session_tokens=0
if [ -n "$session_id" ]; then
  call_total=$(echo "$input" | jq -r '
    [.context_window.current_usage.input_tokens,
     .context_window.current_usage.output_tokens,
     .context_window.current_usage.cache_creation_input_tokens]
    | map(. // 0) | add
  ')

  cache_dir="$HOME/.claude/statusline-token-cache"
  mkdir -p "$cache_dir"
  cache_file="${cache_dir}/${session_id}"
  last_total=""
  cumulative=0
  if [ -f "$cache_file" ]; then
    read -r last_total cumulative extra < "$cache_file" 2>/dev/null
    # Reset if a concurrent write left the line torn (extra field / non-numeric).
    if [ -n "$extra" ] || ! [ "$cumulative" -ge 0 ] 2>/dev/null; then
      last_total=""
      cumulative=0
    fi
  fi
  # Only add when this is a new turn (the status line refreshes many times per
  # turn on the same numbers). Write atomically so a refresh can't tear the file.
  if [ "$call_total" != "$last_total" ] && [ "$call_total" -gt 0 ] 2>/dev/null; then
    cumulative=$(( cumulative + call_total ))
    tmp_file="${cache_file}.tmp.$$"
    printf '%s %s\n' "$call_total" "$cumulative" > "$tmp_file" && mv -f "$tmp_file" "$cache_file"
  fi
  session_tokens=$cumulative
fi

format_tokens() {
  local n=$1
  if [ "$n" -ge 1000000 ] 2>/dev/null; then
    awk -v n="$n" 'BEGIN { printf "%.2fM", n / 1000000 }'
  elif [ "$n" -ge 1000 ] 2>/dev/null; then
    awk -v n="$n" 'BEGIN { printf "%.1fK", n / 1000 }'
  else
    printf '%s' "$n"
  fi
}

# green < 70, yellow 70-89, red 90+
color_for_pct() {
  local pct=$1
  if   [ "$pct" -ge 90 ]; then printf '%s' "$RED"
  elif [ "$pct" -ge 70 ]; then printf '%s' "$YELLOW"
  else                          printf '%s' "$GREEN"
  fi
}

# Unix epoch -> "8pm" / "8:30pm" (drops :00, lowercase am/pm)
format_reset_time() {
  local t
  t=$(date -r "$1" "+%l:%M%p" 2>/dev/null || date -d "@$1" "+%l:%M%p" 2>/dev/null) || return 1
  t=${t# }                              # strip the space %l pads with
  t=$(printf '%s' "$t" | tr 'AP' 'ap'); t=${t/M/m}
  printf '%s' "${t/:00/}"
}

# e.g. ███░░░░░░░ for 30%
make_bar() {
  local pct=$1 width=10 i filled bar=""
  filled=$(( (pct * width + 50) / 100 ))
  [ "$filled" -gt "$width" ] && filled=$width
  [ "$filled" -lt 0 ] && filled=0
  for ((i = 0; i < filled; i++)); do bar+="█"; done
  for ((i = filled; i < width; i++)); do bar+="░"; done
  printf '%s' "$bar"
}

RESET=$'\033[0m'
DIM=$'\033[2m'
BOLD_CYAN=$'\033[1;36m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
RED=$'\033[0;31m'

model_display="${BOLD_CYAN}${model}${RESET}"
[ -n "$effort" ] && model_display="${model_display} ${DIM}${effort}${RESET}"

parts=("$model_display" "${DIM}${dir}${RESET}")
[ -n "$branch" ] && parts+=("${GREEN}${branch}${RESET}")

if [ -n "$ctx_pct" ]; then
  pct=$(printf '%.0f' "$ctx_pct")
  color=$(color_for_pct "$pct")
  bar=$(make_bar "$pct")
  parts+=("${DIM}context${RESET} ${color}${bar}${RESET} ${color}${pct}%${RESET} ${DIM}$(format_tokens "$ctx_tokens")/$(format_tokens "$ctx_max")${RESET}")
fi

if [ "$session_tokens" -gt 0 ] 2>/dev/null; then
  parts+=("${DIM}session${RESET} $(format_tokens "$session_tokens")")
fi

if [ -n "$hour_pct" ]; then
  pct=$(printf '%.0f' "$hour_pct")
  color=$(color_for_pct "$pct")
  seg="${DIM}5h${RESET} ${color}${pct}%${RESET}"
  [ -n "$hour_reset" ] && rt=$(format_reset_time "$hour_reset") && seg="${seg} ${DIM}reset ${rt}${RESET}"
  parts+=("$seg")
fi

if [ -n "$week_pct" ]; then
  pct=$(printf '%.0f' "$week_pct")
  color=$(color_for_pct "$pct")
  parts+=("${DIM}7d${RESET} ${color}${pct}%${RESET}")
fi

sep=" ${DIM}│${RESET} "
out=""
for p in "${parts[@]}"; do
  if [ -z "$out" ]; then
    out="$p"
  else
    out="${out}${sep}${p}"
  fi
done

printf '%s' "$out"
