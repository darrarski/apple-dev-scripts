#!/usr/bin/env -S usage bash
# shellcheck shell=bash disable=SC1091
#MISE description="Adds git release tag with current marketing version and build number (i.e., v1.2.3-456)"
#USAGE

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./_shared.sh
source "${script_dir}/_shared.sh"

build_tag="$(get_build_tag)"

if git rev-parse -q --verify "refs/tags/${build_tag}" >/dev/null; then
  echo "Error: Git tag already exists: ${build_tag}" >&2
  exit 1
fi

echo "${build_tag}"
git tag -a -m "" "${build_tag}"
