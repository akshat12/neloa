#!/bin/sh
set -eu

for COMMAND in swift curl unzip shasum; do
    if ! command -v "$COMMAND" >/dev/null 2>&1; then
        echo "error: building Neloa with Qwen requires $COMMAND" >&2
        exit 1
    fi
done
