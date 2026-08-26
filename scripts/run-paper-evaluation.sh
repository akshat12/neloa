#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
output_dir=${NELOA_PAPER_RESULTS_DIR:-"$repo_root/paper/results/raw/frozen-2026-08-25"}
app_path="$repo_root/.build/model-eval/Neloa.app"
executable_path="$app_path/Contents/MacOS/Neloa"

if [ -n "$(git -C "$repo_root" status --porcelain --untracked-files=no)" ]; then
    echo "Tracked files must be clean before collecting paper results." >&2
    exit 1
fi

mkdir -p "$output_dir"
for precision in 4bit 8bit; do
    for trial in 1 2 3; do
        report="$output_dir/qwen3-vl-4b-${precision}-trial-${trial}.json"
        if [ -e "$report" ]; then
            echo "Refusing to overwrite existing report: $report" >&2
            exit 1
        fi
    done
done

NELOA_MLX_CONFIGURATION=Debug sh "$repo_root/scripts/build-mlx.sh"
NELOA_EXECUTABLE_PATH="$repo_root/.build/arm64-apple-macosx/debug/Neloa" \
NELOA_APP_OUTPUT_PATH="$app_path" \
NELOA_FORCE_ADHOC=1 \
NELOA_EXPECT_MLX_RESOURCES=1 \
sh "$repo_root/scripts/package-app.sh"

commit=$(git -C "$repo_root" rev-parse HEAD)
run_trial() {
    precision=$1
    trial=$2
    report="$output_dir/qwen3-vl-4b-${precision}-trial-${trial}.json"
    flag=--model-eval
    if [ "$precision" = "8bit" ]; then flag=--model-eval-8bit; fi

    echo "Running ${precision} trial ${trial}..."
    if ! NELOA_EVAL_COMMIT="$commit" \
        NELOA_EVAL_TRIAL="${precision}-trial-${trial}" \
        NELOA_MODEL_EVAL_REPORT="$report" \
        "$executable_path" "$flag"; then
        echo "Trial did not meet the benchmark pass threshold; retaining its report." >&2
    fi
    if [ ! -s "$report" ]; then
        echo "Trial did not produce a report: $report" >&2
        exit 1
    fi
}

for trial in 1 2 3; do run_trial 4bit "$trial"; done
for trial in 1 2 3; do run_trial 8bit "$trial"; done

python3 "$repo_root/paper/analyze_results.py" \
    --input "$output_dir" \
    --output "$repo_root/paper/results"
