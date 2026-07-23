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

# ── Cost display config ─────────────────────────────────────────────────────
# The cost is a USD list-price estimate — Anthropic bills in USD, so that's the
# real billing currency (your card does any conversion to local funds, at its
# own rate + fees, which no fixed multiplier could match). It also uses public
# list prices, so account-specific discounts or credits aren't reflected.
#   STATUSLINE_SHOW_COST   1 = show the price (default), 0 = hide it (tokens only)
#   STATUSLINE_COST_WARN   USD amount above which the price turns yellow
#   STATUSLINE_COST_CRIT   USD amount above which it turns red. Defaults 50 / 100.
#
# Set these in ~/.claude/statusline.conf (a plain `VAR=value` file, sourced
# below) — that works for both the CLI and the desktop app. Environment
# variables also work but only reach the desktop app if set inside the
# settings.json command; the config file avoids that. Override the config path
# with STATUSLINE_CONF.
_conf="${STATUSLINE_CONF:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/statusline.conf}"
# shellcheck disable=SC1090
[ -f "$_conf" ] && . "$_conf"

: "${STATUSLINE_SHOW_COST:=1}"
: "${STATUSLINE_COST_WARN:=50}"
: "${STATUSLINE_COST_CRIT:=100}"

input=$(cat)

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd')
model=$(echo "$input" | jq -r '.model.display_name // "Claude"')
effort=$(echo "$input" | jq -r '.effort.level // empty')
transcript=$(echo "$input" | jq -r '.transcript_path // empty')
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

# Whole-thread token total + cost estimate, read from Claude Code's local
# transcript (the same ledger /usage and cost reports read). We sum every API
# response's usage, deduped by message id, so it reflects the full thread across
# compaction and --resume. Cost is priced per model family at base rates —
# verified against real Console billing CSVs (Mar–Jul 2026) to ~0.3%: no
# long-context premium, no discount. The live transcript is complete (never
# purged), so the per-session estimate is accurate, not a rough guess. The path
# comes from the payload (no hardcoded location); streaming with `inputs` keeps
# memory flat regardless of transcript size. If the file is absent or the format
# ever changes, jq yields nothing and the segment drops.
session_tokens=""
session_cache_reads=""
session_cost=""
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  # Feed the main transcript plus every subagent transcript found anywhere
  # under the session's own directory (<session>/**/*.jsonl), so nested or
  # relocated subagent threads are never silently undercounted. Dedup is by
  # message id, so extra files can't double-count; a missing dir just leaves us
  # with the main transcript.
  files=("$transcript")
  session_dir="$(dirname "$transcript")/$(basename "$transcript" .jsonl)"
  if [ -d "$session_dir" ]; then
    while IFS= read -r f; do files+=("$f"); done \
      < <(find "$session_dir" -type f -name '*.jsonl' 2>/dev/null)
  fi
  # Rates are USD per million tokens: {input, output, cache_read, cache_write}.
  # Keep in sync with claude-cost-report.py's PRICING table. Each family is
  # matched explicitly; a model matching none (a future launch) that carries
  # real tokens is flagged unknown -> the price is suppressed for that render
  # (tokens still shown), rather than guessing a wrong rate. Add the new family
  # here to re-enable it. A zero-token turn (e.g. Claude Code's <synthetic>
  # messages) is never flagged, so it can't blank the price.
  session_usage=$(jq -rn '
    def rate($m):
      ($m | ascii_downcase) as $l
      | if   ($l | test("fable|mythos")) then {i:10, o:50, cr:1.00, cw:12.50, known:true}
        elif ($l | test("opus"))         then {i:5,  o:25, cr:0.50, cw:6.25,  known:true}
        elif ($l | test("sonnet"))       then {i:3,  o:15, cr:0.30, cw:3.75,  known:true}
        elif ($l | test("haiku"))        then {i:1,  o:5,  cr:0.10, cw:1.25,  known:true}
        else                                  {i:0,  o:0,  cr:0,    cw:0,     known:false} end;
    reduce inputs as $e ({};
      if ($e.type == "assistant" and ($e.message.usage != null))
      then
        ($e.message.usage) as $u
        | (rate($e.message.model // "")) as $r
        | (($u.input_tokens // 0)) as $in
        | (($u.output_tokens // 0)) as $out
        | (($u.cache_read_input_tokens // 0)) as $cr
        | (($u.cache_creation_input_tokens // 0)) as $cw
        | .[$e.message.id // "anon"] = {
            total: ($in + $out + $cr + $cw),
            cache_reads: $cr,
            cost: (($in*$r.i + $out*$r.o + $cr*$r.cr + $cw*$r.cw) / 1000000),
            unknown: (if ($r.known or ($in + $out + $cr + $cw) == 0) then 0 else 1 end)
          }
      else . end)
    | reduce .[] as $x ({ total: 0, cache_reads: 0, cost: 0, unknown: 0 };
        .total += $x.total | .cache_reads += $x.cache_reads
        | .cost += $x.cost | .unknown += $x.unknown)
    | [.total, .cache_reads, .cost, (if .unknown > 0 then 1 else 0 end)] | @tsv
  ' "${files[@]}" 2>/dev/null)
  IFS=$'\t' read -r session_tokens session_cache_reads session_cost session_unknown <<< "$session_usage"
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

# Format a USD cost, always to 2 decimals: "~US$4.30", "~US$45.00".
# "US$" disambiguates from CAD/AUD/etc.
format_cost() {
  awk -v c="$1" 'BEGIN { printf "~US$%.2f", c }'
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

if [ -n "$session_tokens" ] && [ "$session_tokens" -gt 0 ] 2>/dev/null; then
  seg="${DIM}session${RESET}"
  # Price first, threshold-colored (green / yellow above WARN / red above CRIT).
  # Shown only when enabled, priceable, and every model was recognized — an
  # unknown future model suppresses the price (tokens still show), never breaks.
  if [ "$STATUSLINE_SHOW_COST" = "1" ] && [ -n "$session_cost" ] && [ "${session_unknown:-0}" != "1" ]; then
    cost_int=$(printf '%.0f' "$session_cost" 2>/dev/null)
    if   [ "$cost_int" -gt "$STATUSLINE_COST_CRIT" ] 2>/dev/null; then pcolor=$RED
    elif [ "$cost_int" -gt "$STATUSLINE_COST_WARN" ] 2>/dev/null; then pcolor=$YELLOW
    else                                                              pcolor=$GREEN
    fi
    seg="${seg} ${pcolor}$(format_cost "$session_cost")${RESET}"
    seg="${seg} ${DIM}·${RESET}"
  fi
  seg="${seg} $(format_tokens "$session_tokens") total ${DIM}·${RESET} $(format_tokens "$session_cache_reads") cache reads"
  parts+=("$seg")
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
