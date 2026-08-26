#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
output_dir="$repo_root/output/submission"
output_zip="$output_dir/neloa-anonymous-evaluation-artifact.zip"
stage_root=$(mktemp -d "${TMPDIR:-/tmp}/neloa-paper-artifact.XXXXXX")
artifact_root="$stage_root/neloa-anonymous-evaluation-artifact"
trap 'find "$stage_root" -type f -delete 2>/dev/null || true; find "$stage_root" -depth -type d -empty -delete 2>/dev/null || true' EXIT

mkdir -p "$artifact_root/paper/results" "$artifact_root/scripts"

cp "$repo_root/LICENSE" "$artifact_root/LICENSE"
cp "$repo_root/Package.swift" "$repo_root/Package.resolved" "$artifact_root/"
cp "$repo_root/paper/artifact/README.md" "$artifact_root/README.md"
cp "$repo_root/paper/evaluation-manifest.json" "$repo_root/paper/analyze_results.py" "$artifact_root/paper/"
cp "$repo_root/paper/results/summary.json" "$repo_root/paper/results/summary.csv" \
   "$repo_root/paper/results/case-results.csv" "$repo_root/paper/results/results-table.md" \
   "$artifact_root/paper/results/"
cp "$repo_root/scripts/build-mlx.sh" "$repo_root/scripts/check-mlx-toolchain.sh" \
   "$repo_root/scripts/fetch-mlx-metallib.sh" "$repo_root/scripts/package-app.sh" \
   "$repo_root/scripts/run-paper-evaluation.sh" "$artifact_root/scripts/"

/usr/bin/ditto "$repo_root/Sources" "$artifact_root/Sources"
/usr/bin/ditto "$repo_root/Tests" "$artifact_root/Tests"
/usr/bin/ditto "$repo_root/Resources" "$artifact_root/Resources"
/usr/bin/ditto "$repo_root/paper/results/raw" "$artifact_root/paper/results/raw"

if rg -n 'akshat12|divekar|@live\.com' "$artifact_root" >/dev/null; then
    echo "Author-identifying text found in staged artifact." >&2
    exit 1
fi

mkdir -p "$output_dir"
if [ -f "$output_zip" ]; then
    unlink "$output_zip"
fi
/usr/bin/ditto -c -k --norsrc --keepParent "$artifact_root" "$output_zip"
echo "$output_zip"
