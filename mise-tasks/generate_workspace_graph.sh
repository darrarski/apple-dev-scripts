#!/usr/bin/env -S usage bash
#MISE description="Generates workspace dependency graph."
#USAGE

set -e

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="$root_dir/docs"
output_path="$output_dir/graph.png"
workspace_graph_path="$output_dir/workspace_graph.png"

# Generates a graph from the workspace, excluding external dependencies.
mise x -- tuist graph \
  --skip-external-dependencies \
  --skip-test-targets \
  --format png \
  --algorithm dot \
  --path "$root_dir" \
  --output-path "$output_dir" \
  --no-open

echo "Moving file to $workspace_graph_path"
mv "$output_path" "$workspace_graph_path"
