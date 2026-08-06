#!/bin/sh
set -eu

if ! xcrun --find metal >/dev/null 2>&1; then
    cat >&2 <<'EOF'
error: building Neloa's local Qwen runtime needs the Metal compiler from full Xcode.

Install the free Xcode app, open it once so setup can finish, then run this command again.
An Apple Developer Program membership is not required. People installing Neloa's ZIP do not need Xcode.

To build Neloa without Qwen for UI work, run: make basic-app
EOF
    exit 1
fi
