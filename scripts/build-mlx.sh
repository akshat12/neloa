#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CONFIGURATION=${NELOA_MLX_CONFIGURATION:-Debug}
SCRATCH_PATH=${NELOA_MLX_SCRATCH_PATH:-$PROJECT_DIR/.build}

case "$CONFIGURATION" in
    Debug|Release) ;;
    *)
        echo "error: NELOA_MLX_CONFIGURATION must be Debug or Release" >&2
        exit 1
        ;;
esac

sh "$PROJECT_DIR/scripts/check-mlx-toolchain.sh"

cd "$PROJECT_DIR"
case "$CONFIGURATION" in
    Debug) SWIFT_CONFIGURATION=debug ;;
    Release) SWIFT_CONFIGURATION=release ;;
esac

set -- swift build -c "$SWIFT_CONFIGURATION" --scratch-path "$SCRATCH_PATH" --product Neloa
if [ -n "${NELOA_MLX_TRIPLE:-}" ]; then
    set -- "$@" --triple "$NELOA_MLX_TRIPLE"
fi
NELOA_ENABLE_MLX=1 "$@"

set -- swift build -c "$SWIFT_CONFIGURATION" --scratch-path "$SCRATCH_PATH" --show-bin-path
if [ -n "${NELOA_MLX_TRIPLE:-}" ]; then
    set -- "$@" --triple "$NELOA_MLX_TRIPLE"
fi
BIN_DIRECTORY=$(NELOA_ENABLE_MLX=1 "$@")
EXECUTABLE_PATH="$BIN_DIRECTORY/Neloa"
if [ ! -f "$EXECUTABLE_PATH" ]; then
    echo "error: Swift did not produce Neloa at $EXECUTABLE_PATH" >&2
    exit 1
fi

METALLIB=$(sh "$PROJECT_DIR/scripts/fetch-mlx-metallib.sh")
cp "$METALLIB" "$BIN_DIRECTORY/mlx.metallib"

echo "$EXECUTABLE_PATH"
