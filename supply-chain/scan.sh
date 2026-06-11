#!/usr/bin/env bash
# scan.sh
# ─────────────────────────────────────────────────────────────────────────────
# Vulnerability scanning for the platform release.
#
# Two complementary scanners are used — each with a distinct role:
#
#   Grype  — scans the SBOM (sbom.json).
#             Provides SBOM-aware, dependency-level vulnerability detection.
#             Fast and CI-friendly.  Treats the SBOM as the authoritative
#             manifest of what is in the platform.
#
#   Trivy  — scans each container image directly from the registry.
#             Provides a second opinion using a different vulnerability
#             database and can detect OS-level issues missed by SBOM analysis.
#
# Severity thresholds:
#   CRITICAL  → always fails the pipeline (non-negotiable).
#   HIGH      → controlled by FAIL_ON_HIGH env var (default: false).
#
# Usage:
#   ./supply-chain/scan.sh [images.txt] [sbom.json]
#
# Prerequisites: grype, trivy
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

IMAGES_FILE="${1:-images.txt}"
SBOM_FILE="${2:-sbom.json}"
FAIL_ON_HIGH="${FAIL_ON_HIGH:-false}"

command -v grype >/dev/null 2>&1 || { echo "ERROR: grype not installed. See https://github.com/anchore/grype" >&2; exit 1; }
command -v trivy >/dev/null 2>&1 || { echo "ERROR: trivy not installed. See https://github.com/aquasecurity/trivy" >&2; exit 1; }

if [[ ! -f "$SBOM_FILE" ]]; then
  echo "ERROR: SBOM file '$SBOM_FILE' not found. Run sbom.sh first." >&2
  exit 1
fi

if [[ ! -f "$IMAGES_FILE" ]]; then
  echo "ERROR: images file '$IMAGES_FILE' not found. Run extract-images.sh first." >&2
  exit 1
fi

GRYPE_FAIL_ON="critical"
TRIVY_SEVERITY="CRITICAL"
if [[ "$FAIL_ON_HIGH" == "true" ]]; then
  GRYPE_FAIL_ON="high"
  TRIVY_SEVERITY="CRITICAL,HIGH"
fi

EXIT_CODE=0

# ─── Grype: SBOM-based scan ───────────────────────────────────────────────────
echo "════════════════════════════════════════"
echo " Grype — scanning SBOM: $SBOM_FILE"
echo "════════════════════════════════════════"
if ! grype "sbom:${SBOM_FILE}" --fail-on "$GRYPE_FAIL_ON"; then
  echo "ERROR: Grype found $GRYPE_FAIL_ON+ severity vulnerabilities." >&2
  EXIT_CODE=1
fi

# ─── Trivy: image-based scan ──────────────────────────────────────────────────
echo
echo "════════════════════════════════════════"
echo " Trivy — scanning container images"
echo "════════════════════════════════════════"
while IFS= read -r image; do
  [[ -z "$image" ]] && continue
  echo
  echo "── $image"
  if ! trivy image \
        --exit-code 1 \
        --severity "$TRIVY_SEVERITY" \
        --no-progress \
        "$image"; then
    echo "ERROR: Trivy found $TRIVY_SEVERITY severity vulnerabilities in $image." >&2
    EXIT_CODE=1
  fi
done < "$IMAGES_FILE"

if [[ $EXIT_CODE -ne 0 ]]; then
  echo
  echo "Vulnerability scan FAILED. Review findings above." >&2
fi

exit $EXIT_CODE
