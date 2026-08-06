#!/bin/bash
# Fast installed-app UI iteration. Builds only the KeyPath app product, deploys it
# into /Applications/KeyPath.app, signs locally, and restarts KeyPath if it was
# already running. This lane intentionally does not notarize.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" >/dev/null && pwd)

export KEYPATH_QUICK_DEPLOY_BUILD_SCOPE="${KEYPATH_QUICK_DEPLOY_BUILD_SCOPE:-app}"
export KEYPATH_QUICK_DEPLOY_HOST_BRIDGE="${KEYPATH_QUICK_DEPLOY_HOST_BRIDGE:-0}"

exec "$SCRIPT_DIR/quick-deploy.sh"
