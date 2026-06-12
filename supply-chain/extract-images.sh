#!/usr/bin/env bash
# extract-images.sh
# ─────────────────────────────────────────────────────────────────────────────
# Extract every unique container image reference from a rendered Helm manifest.
#
# Usage:
#   ./supply-chain/extract-images.sh [rendered.yaml] [images.txt]
#
# Why rendered manifests are the source of truth:
#   Values files may reference images indirectly via aliases or overrides that
#   are resolved only at render time.  By inspecting the fully rendered YAML
#   we capture exactly what Kubernetes would pull — no guessing.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

RENDERED_FILE="${1:-rendered.yaml}"
OUTPUT_FILE="${2:-images.txt}"

if [[ ! -f "$RENDERED_FILE" ]]; then
  echo "ERROR: rendered manifest '$RENDERED_FILE' not found." >&2
  echo "       Run 'helm template' first to produce the rendered manifest." >&2
  exit 1
fi

command -v yq >/dev/null 2>&1 || { echo "ERROR: yq is not installed." >&2; exit 1; }

echo "Extracting container images from $RENDERED_FILE ..."

# Walk every node in the YAML and collect any field named 'image'.
# The result is sorted and de-duplicated so the file is stable across runs.
yq --no-doc '.. | .image? | select(tag == "!!str")' "$RENDERED_FILE" \
  | grep -v '^null$' \
  | sort -u \
  > "$OUTPUT_FILE"

count=$(wc -l < "$OUTPUT_FILE" | tr -d ' ')
echo "Found $count unique image(s):"
sed 's/^/  /' "$OUTPUT_FILE"
echo
echo "Written to: $OUTPUT_FILE"
