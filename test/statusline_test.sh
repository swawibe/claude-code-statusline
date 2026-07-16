#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

transcript="$tmpdir/session.jsonl"
cat > "$transcript" <<'EOF'
{"type":"assistant","message":{"id":"first","usage":{"input_tokens":1200000,"output_tokens":900000,"cache_read_input_tokens":34120000,"cache_creation_input_tokens":320000}}}
EOF

payload=$(jq -n --arg transcript "$transcript" '{
  workspace: { current_dir: "/tmp" },
  model: { display_name: "Claude" },
  transcript_path: $transcript
}')

output=$(printf '%s' "$payload" | bash "$root/statusline.sh")
clean=$(printf '%s' "$output" | sed $'s/\033\\[[0-9;]*m//g')

case "$clean" in
  *"36.54M total · 34.12M cache reads"*) ;;
  *)
    printf 'expected total and cache-read session label, got: %s\n' "$clean" >&2
    exit 1
    ;;
esac
