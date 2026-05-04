#!/usr/bin/env -S usage bash
# shellcheck shell=bash
#MISE description="Sets the next build number based on the latest App Store Connect builds."
#USAGE

set -euo pipefail

latest_ios_build_number="$(mise run --output quiet get_latest_app_store_build_number --platform iOS)"
latest_macos_build_number="$(mise run --output quiet get_latest_app_store_build_number --platform macOS)"

if (( latest_ios_build_number > latest_macos_build_number )); then
  new_build_number=$((latest_ios_build_number + 1))
else
  new_build_number=$((latest_macos_build_number + 1))
fi

echo "Resolved build number: ${new_build_number}"
mise run set_build_number "${new_build_number}"
