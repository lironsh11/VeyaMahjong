#!/usr/bin/env bash
set -euxo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ci-env.sh
source "$SCRIPT_DIR/ci-env.sh"

ci_install_cli_tools
ci_verify_asc_secrets

IPA=$(find "$BUILD_DIR/ios/ipa" -name '*.ipa' -print -quit)
test -n "$IPA"

# Upload to App Store Connect. --testflight also submits external beta review
# and needs Beta App Information (feedback email + contact) filled in first.
SUBMIT_TESTFLIGHT_BETA_REVIEW="${SUBMIT_TESTFLIGHT_BETA_REVIEW:-false}"

PUBLISH_ARGS=(publish --path "$IPA")
if [ "$SUBMIT_TESTFLIGHT_BETA_REVIEW" = "true" ]; then
  PUBLISH_ARGS+=(--testflight)
  echo "Submitting $IPA to TestFlight external beta review..."
else
  echo "Uploading $IPA to App Store Connect (no external beta review submission)..."
fi

app-store-connect "${PUBLISH_ARGS[@]}" \
  --issuer-id "$APP_STORE_CONNECT_ISSUER_ID" \
  --key-id "$APP_STORE_CONNECT_KEY_IDENTIFIER" \
  --private-key "@file:${ASC_KEY_FILE}"

echo "App Store Connect upload finished."
