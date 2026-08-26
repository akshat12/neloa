# Neloa anonymous evaluation artifact

This archive accompanies the anonymized short paper “Separating Interpretation from
Authority: Bounded Local Adaptation for Desktop Automation by Demonstration.” It omits
repository history, project marketing material, and author-identifying metadata.

## Contents

- `Sources/Neloa/` — macOS application and executable benchmark implementation
- `Tests/Fixtures/` — account-free synthetic visual fixtures
- `paper/evaluation-manifest.json` — frozen cases, model revisions, and claim boundary
- `paper/results/raw/frozen-2026-08-25/` — all six retained trial reports
- `paper/analyze_results.py` — report validation and aggregate analysis
- `paper/results/` — regenerated summary and case-level tables
- `scripts/run-paper-evaluation.sh` — fresh-process collection runner

No model weights, private recordings, credentials, live-account data, or participant data
are included. The model weights are downloaded from the pinned repositories named in the
manifest and retain their upstream licenses.

## Validate the committed results

Requires Python 3. From the unpacked archive root:

```sh
python3 paper/analyze_results.py \
  --input paper/results/raw/frozen-2026-08-25 \
  --output paper/results
```

The command validates the number of reports, model IDs and revisions, case set, and
trial count before regenerating `summary.json`, `summary.csv`, `case-results.csv`, and
`results-table.md`.

## Build and run deterministic self-tests

Requires macOS 15 or later and the Xcode command-line tools:

```sh
swift build
swift run Neloa --self-test
```

These checks do not download or load Qwen.

## Recollect all six model trials

Recollection requires an Apple-silicon Mac, network access for the first model download,
and enough free disk and memory for the selected tier. The reported study used an Apple
M4 Pro Mac with 48 GB memory; it does not establish 16 GB compatibility.

Choose a new output directory so the frozen reports remain untouched:

```sh
NELOA_PAPER_RESULTS_DIR="$PWD/paper/results/raw/reproduction" \
NELOA_EVAL_COMMIT="anonymous-artifact" \
./scripts/run-paper-evaluation.sh
```

The runner builds the MLX-enabled application once, then launches three fresh processes
per tier. It retains failed reports and refuses to overwrite an existing trial file.

## Interpretation boundary

The 15 designed cases test executable assertions for implemented constructs. They do not
measure arbitrary live-application reliability, user usability, indirect prompt
injection from screen content, or performance on a 16 GB Mac. The deterministic and
model-dependent case classes are reported separately.
