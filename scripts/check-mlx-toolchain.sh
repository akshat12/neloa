#!/bin/sh
set -eu

if ! xcrun --find metal >/dev/null 2>&1; then
    cat >&2 <<'EOF'
error: Neloa's local Qwen model needs the Metal compiler from full Xcode.

Install the free Xcode app, open it once so it can finish setup, then run this command again.
An Apple Developer Program membership is not required.

To build Neloa without Qwen for UI work, run: make basic-app
EOF
    exit 1
fi
