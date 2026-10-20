#!/bin/bash
# KP_SIGN_CMD shim for local iteration: sign with the Developer ID identity in
# the (unlocked) login keychain, so a locked secondary keychain holding the same
# identity cannot stall the build behind a password prompt.
exec /usr/bin/codesign --keychain "$HOME/Library/Keychains/login.keychain-db" "$@"
