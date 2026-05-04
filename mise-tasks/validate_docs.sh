#!/usr/bin/env -S usage bash
#MISE description="Verify internal markdown links, referenced mise tasks, and paths used in docs."
#USAGE

set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root_dir"

docs_files=(
  "README.md"
  docs/*.md
)

mise_tasks_doc_file="README.md"

failures=0

echo "Checking internal Markdown links..."
while IFS= read -r line; do
  file="${line%%:*}"
  link="${line#*:}"
  target="${link##*\(}"
  target="${target%\)}"
  target="${target%%#*}"

  if [[ "$target" =~ ^https?:// ]] || [[ "$target" =~ ^mailto: ]] || [[ "$target" =~ ^# ]]; then
    continue
  fi

  target="${target#<}"
  target="${target%>}"

  # Ignore image badges and other non-file targets.
  if [[ "$target" == *"://"* ]]; then
    continue
  fi

  resolved="$(cd "$(dirname "$file")" && printf '%s/%s' "$PWD" "$target")"
  if [[ ! -e "$resolved" ]]; then
    echo "  [FAIL] $file -> $target (missing)"
    failures=1
  fi
done < <(grep -nH -E -o '\]\(([^)]+)\)' "${docs_files[@]}" || true)

echo "Checking documented Mise tasks..."
while IFS= read -r task; do
  [[ -z "$task" ]] && continue
  escaped_task="$(printf '%s\n' "$task" | sed 's/[][(){}.^$*+?|\\/]/\\&/g')"
  if ! grep -q -E "(^|[^A-Za-z0-9_-])${escaped_task}([^A-Za-z0-9_-]|$)" "${mise_tasks_doc_file}"; then
    echo "  [FAIL] Missing task docs entry in ${mise_tasks_doc_file}: $task"
    failures=1
  fi
done < <(mise tasks -l | awk '{print $1}' | sort -u)

if [[ "$failures" -ne 0 ]]; then
  echo "Documentation validation failed."
  exit 1
fi

echo "Documentation validation passed."
