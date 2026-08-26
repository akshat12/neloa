#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
output_dir="$repo_root/output/submission"
stage_root=$(mktemp -d "${TMPDIR:-/tmp}/neloa-submission-packages.XXXXXX")
trap 'find "$stage_root" -type f -delete 2>/dev/null || true; find "$stage_root" -type l -delete 2>/dev/null || true; find "$stage_root" -depth -type d -empty -delete 2>/dev/null || true' EXIT

(cd "$repo_root" && python3 paper/finalize_submission.py)
python3 "$repo_root/paper/build_pdf.py"
"$repo_root/scripts/build-anonymous-paper-artifact.sh" >/dev/null

mkdir -p "$output_dir"

build_bundle() {
    bundle_name=$1
    shift
    bundle_root="$stage_root/$bundle_name"
    output_zip="$output_dir/$bundle_name.zip"
    mkdir -p "$bundle_root"
    for source in "$@"; do
        cp "$source" "$bundle_root/"
    done
    if [ -f "$output_zip" ]; then
        unlink "$output_zip"
    fi
    /usr/bin/ditto -c -k --norsrc --keepParent "$bundle_root" "$output_zip"
    unzip -t "$output_zip" >/dev/null
    echo "$output_zip"
}

build_bundle "neloa-iwc-review-bundle" \
    "$repo_root/output/pdf/neloa-short-paper.pdf" \
    "$output_dir/neloa-anonymous-evaluation-artifact.zip" \
    "$repo_root/paper/submission/iwc-upload-readme.md"

build_bundle "neloa-hcii-2027-proposal-bundle" \
    "$repo_root/output/pdf/neloa-hcii-2027-proposal.pdf" \
    "$repo_root/paper/submission/hcii-upload-readme.md"

(cd "$repo_root" && shasum -a 256 output/pdf/*.pdf output/submission/*.zip > output/submission/SHA256SUMS)
python3 "$repo_root/paper/audit_submission.py"

author_metadata="$repo_root/paper/submission/author-metadata.json"
if [ -f "$author_metadata" ]; then
    python3 "$repo_root/paper/render_submission_metadata.py" --metadata "$author_metadata"
else
    echo "Author metadata not present; built anonymous submission files only."
fi
