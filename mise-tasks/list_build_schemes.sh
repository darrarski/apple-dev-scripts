#!/usr/bin/env -S usage bash
#MISE description="Lists all build schemes defined in the workspace."
#USAGE

set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"

while IFS= read -r scheme_path; do
  scheme_filename="${scheme_path##*/}"
  scheme_name="${scheme_filename%.xcscheme}"
  if [[ "${scheme_name}" == "Generate Project" ]]; then
    continue
  fi
  printf '%s\n' "${scheme_name}"
done < <(
  find "${root_dir}" \
    -path "${root_dir}/build" -prune -o \
    -path "${root_dir}/Tuist/.build" -prune -o \
    -type f -path '*/xcshareddata/xcschemes/*.xcscheme' -print \
    | sort
)
