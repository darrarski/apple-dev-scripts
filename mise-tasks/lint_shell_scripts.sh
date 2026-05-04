#!/usr/bin/env -S usage bash
# shellcheck shell=bash
#MISE description="Lint all shell scripts in the repository using shellcheck."
#USAGE

set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "${root_dir}"

shell_scripts=()
while IFS= read -r shell_script; do
  [[ -n "${shell_script}" ]] && shell_scripts+=("${shell_script}")
done < <(
  find . \
    -path './Tuist/.build' -prune -o \
    -type f -name '*.sh' -print \
    | sort \
    | sed 's|^\./||'
)

if (( ${#shell_scripts[@]} == 0 )); then
  echo "No shell scripts found."
  exit 0
fi

mise x -- shellcheck --shell=bash "${shell_scripts[@]}"
