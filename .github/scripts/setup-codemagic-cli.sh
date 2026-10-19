#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ci-env.sh
source "$SCRIPT_DIR/ci-env.sh"
ci_install_cli_tools
if [ -n "${GITHUB_PATH:-}" ]; then
  echo "$CI_VENV/bin" >> "$GITHUB_PATH"
fi
echo "PATH includes: $CI_VENV/bin"
