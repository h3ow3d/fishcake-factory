#!/usr/bin/env bash
# sbom.sh
# ─────────────────────────────────────────────────────────────────────────────
# Generate a combined SPDX-JSON Software Bill of Materials (SBOM) for all
# container images that make up the platform release.
#
# Usage:
#   ./supply-chain/sbom.sh [images.txt] [sbom.json]
#
# Strategy:
#   • Syft scans each image from the OCI registry and outputs an SPDX-JSON doc.
#   • jq merges all per-image documents into a single platform-level SBOM by
#     combining the packages and relationships arrays.
#   • The resulting sbom.json can be scanned directly with Grype
#     (grype sbom:sbom.json) and attached to the release as an attestation.
#
# Prerequisites: syft, jq
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

IMAGES_FILE="${1:-images.txt}"
OUTPUT_FILE="${2:-sbom.json}"

command -v syft >/dev/null 2>&1 || { echo "ERROR: syft is not installed. See https://github.com/anchore/syft" >&2; exit 1; }
command -v jq   >/dev/null 2>&1 || { echo "ERROR: jq is not installed." >&2; exit 1; }

if [[ ! -f "$IMAGES_FILE" ]]; then
  echo "ERROR: images file '$IMAGES_FILE' not found." >&2
  echo "       Run extract-images.sh first." >&2
  exit 1
fi

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

index=0
while IFS= read -r image; do
  [[ -z "$image" ]] && continue
  echo "Generating SBOM for: $image"
  syft "$image" -o spdx-json > "$TEMP_DIR/sbom-${index}.json"
  ((index++))
done < "$IMAGES_FILE"

if [[ $index -eq 0 ]]; then
  echo "ERROR: no images found in $IMAGES_FILE" >&2
  exit 1
fi

echo "Merging $index SBOM document(s) into $OUTPUT_FILE ..."

# Combine all packages and relationships into the first document's envelope.
# SPDX document-level fields (namespace, SPDXID, etc.) are taken from the
# first image; packages from all images are aggregated.
jq -s '
  (.[0]) |
  .name        = "demo-platform" |
  .packages    = ([.[].packages    // []] | add) |
  .relationships = ([.[].relationships // []] | add)
' "$TEMP_DIR"/sbom-*.json > "$OUTPUT_FILE"

echo "Platform SBOM written to $OUTPUT_FILE ($index image(s) included)"
