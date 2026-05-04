#!/usr/bin/env -S usage bash
# shellcheck shell=bash disable=SC1091
#MISE description="Generate WhatToTest file with changes from commits history since previous release tag."
#USAGE

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./_shared.sh
source "${script_dir}/_shared.sh"

root_dir="$(get_root_dir)"

testflight_dir_name="TestFlight"
testflight_dir_path="${root_dir}/${testflight_dir_name}"
whattotest_file_name="WhatToTest.en-US.txt"
whattotest_file_path="${testflight_dir_path}/${whattotest_file_name}"

build_tag="$(get_build_tag)"

git_branch=$(git -C "${root_dir}" rev-parse --abbrev-ref HEAD)
git_remote_url=$(git -C "${root_dir}" config --get remote.origin.url)

if [[ "$git_remote_url" =~ github.com[:/]([^/]+)/([^/]+)(\.git)?$ ]]; then
  github_user="${BASH_REMATCH[1]}"
  github_repo_name="${BASH_REMATCH[2]%.git}"
  github_repo="${github_user}/${github_repo_name}"
else
  echo "Could not determine GitHub user/repo from remote URL." >&2
  exit 1
fi

mkdir -p "${testflight_dir_path}"

if [[ "$(git -C "${root_dir}" rev-parse --is-shallow-repository)" == "true" ]]; then
  git -C "${root_dir}" fetch --unshallow --tags
else
  git -C "${root_dir}" fetch --tags
fi

previous_tag="$(git -C "${root_dir}" describe --tags --abbrev=0 HEAD~1 2>/dev/null || true)"

{
  git -C "${root_dir}" log \
    "${previous_tag:+${previous_tag}..}HEAD" \
    --pretty=format:'- %s' \
    --first-parent
  echo ""
  echo "- Build branch: \"${git_branch}\""
  echo "- More info: https://github.com/${github_repo}/releases/tag/${build_tag}"
} > "${whattotest_file_path}"

echo "What To Test (${testflight_dir_name}/${whattotest_file_name}):"
cat "${whattotest_file_path}"
