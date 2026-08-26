#!/usr/bin/env python3
"""Fail-fast audit for Neloa's frozen study and submission package."""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
import tempfile
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PAPER_DIR = ROOT / "paper"
SUBMISSION = PAPER_DIR / "submission"
RESULTS = PAPER_DIR / "results"
RAW = RESULTS / "raw" / "frozen-2026-08-25"
ANONYMOUS_ZIP = ROOT / "output" / "submission" / "neloa-anonymous-evaluation-artifact.zip"
SUBMISSION_OUTPUT = ROOT / "output" / "submission"


def words(text: str) -> list[str]:
    return re.findall(r"\b[\w’'-]+\b", text)


def without_front_matter(text: str) -> str:
    return re.sub(r"^---\n.*?\n---\n", "", text, flags=re.DOTALL)


def without_comments(text: str) -> str:
    return re.sub(r"<!--.*?-->", "", text, flags=re.DOTALL)


def check_manuscripts() -> list[str]:
    paper_path = SUBMISSION / "short-paper.md"
    proposal_path = SUBMISSION / "hcii-2027-proposal.md"
    paper = paper_path.read_text(encoding="utf-8")
    proposal = proposal_path.read_text(encoding="utf-8")

    abstract = paper.split("# Abstract", 1)[1].split("**Keywords:**", 1)[0]
    abstract_count = len(words(without_comments(abstract)))
    assert 150 <= abstract_count <= 200, f"Abstract is {abstract_count} words"

    keyword_line = paper.split("**Keywords:**", 1)[1].splitlines()[0]
    keyword_count = len([item for item in keyword_line.split(";") if item.strip()])
    assert keyword_count <= 6, f"Manuscript has {keyword_count} keywords"

    body = without_front_matter(paper).split("# References", 1)[0]
    body = body.split("**Keywords:**", 1)[1]
    body_word_count = len(words(without_comments(body)))
    assert 3_000 <= body_word_count <= 5_000, f"Main text is {body_word_count} words"

    proposal_body = without_front_matter(proposal).split("## References", 1)[0]
    proposal_word_count = len(words(without_comments(proposal_body)))
    assert proposal_word_count <= 800, f"HCII proposal is {proposal_word_count} words"

    unresolved = ("will be inserted", "[Final", "trials are still being collected")
    assert not any(token in paper or token in proposal for token in unresolved), "Result placeholder remains"
    assert "github.com/akshat12" not in paper, "Anonymous manuscript reveals repository identity"

    citation_keys = set(re.findall(r"@([A-Za-z0-9:_-]+)", paper))
    bibliography = (PAPER_DIR / "references.bib").read_text(encoding="utf-8")
    bibliography_keys = set(re.findall(r"^@[A-Za-z]+\{([^,]+),", bibliography, flags=re.MULTILINE))
    assert citation_keys == bibliography_keys, (
        f"Citation mismatch: missing={sorted(citation_keys - bibliography_keys)}, "
        f"unused={sorted(bibliography_keys - citation_keys)}"
    )

    return [
        f"abstract {abstract_count} words",
        f"keywords {keyword_count}",
        f"main text {body_word_count} words",
        f"HCII proposal {proposal_word_count} words",
        f"citations {len(citation_keys)} resolved",
    ]


def check_results() -> list[str]:
    manifest = json.loads((PAPER_DIR / "evaluation-manifest.json").read_text(encoding="utf-8"))
    summary = json.loads((RESULTS / "summary.json").read_text(encoding="utf-8"))
    reports = sorted(RAW.glob("*.json"))
    assert len(reports) == 6, f"Expected six raw reports, found {len(reports)}"
    assert summary["reportCount"] == 6
    assert len(manifest["cases"]) == 15
    assert all(tier["trials"] == 3 for tier in summary["tiers"])
    assert all(tier["reportsPassed"] == 3 for tier in summary["tiers"])
    assert all(tier["criticalFailureCount"] == 0 for tier in summary["tiers"])

    with tempfile.TemporaryDirectory(prefix="neloa-analysis-") as temporary:
        regenerated = Path(temporary)
        subprocess.run(
            [
                "python3",
                str(PAPER_DIR / "analyze_results.py"),
                "--input",
                str(RAW),
                "--output",
                str(regenerated),
                "--manifest",
                str(PAPER_DIR / "evaluation-manifest.json"),
            ],
            check=True,
        )
        for name in ("summary.json", "summary.csv", "case-results.csv", "results-table.md"):
            assert (regenerated / name).read_bytes() == (RESULTS / name).read_bytes(), (
                f"Committed {name} does not match regenerated analysis"
            )

    return ["six raw reports", "three passing trials per tier", "zero critical failures", "analysis reproducible"]


def check_outputs() -> list[str]:
    pdfs = [
        ROOT / "output" / "pdf" / "neloa-short-paper.pdf",
        ROOT / "output" / "pdf" / "neloa-hcii-2027-proposal.pdf",
    ]
    for path in pdfs:
        assert path.read_bytes().startswith(b"%PDF-"), f"Missing or invalid PDF: {path}"

    assert ANONYMOUS_ZIP.exists(), "Anonymous evaluation artifact is missing"
    forbidden = re.compile(r"akshat12|divekar|@live\.com", re.IGNORECASE)
    with zipfile.ZipFile(ANONYMOUS_ZIP) as archive:
        names = archive.namelist()
        assert not any("__MACOSX" in name or "/._" in name for name in names), "macOS metadata in artifact"
        json_reports = [name for name in names if name.endswith(".json") and "results/raw/" in name]
        assert len(json_reports) == 6, f"Artifact contains {len(json_reports)} JSON reports"
        for info in archive.infolist():
            if Path(info.filename).suffix.lower() not in {
                ".swift", ".md", ".json", ".csv", ".sh", ".plist", ".entitlements", ".txt"
            }:
                continue
            content = archive.read(info).decode("utf-8", errors="ignore")
            assert not forbidden.search(content), f"Identity leaked in artifact: {info.filename}"

    bundles = {
        SUBMISSION_OUTPUT / "neloa-iwc-review-bundle.zip": {
            "neloa-short-paper.pdf": pdfs[0],
            "neloa-anonymous-evaluation-artifact.zip": ANONYMOUS_ZIP,
            "iwc-upload-readme.md": SUBMISSION / "iwc-upload-readme.md",
        },
        SUBMISSION_OUTPUT / "neloa-hcii-2027-proposal-bundle.zip": {
            "neloa-hcii-2027-proposal.pdf": pdfs[1],
            "hcii-upload-readme.md": SUBMISSION / "hcii-upload-readme.md",
        },
    }
    for bundle, expected_files in bundles.items():
        assert bundle.exists(), f"Submission bundle is missing: {bundle}"
        with zipfile.ZipFile(bundle) as archive:
            names = archive.namelist()
            assert not any("__MACOSX" in name or "/._" in name for name in names), (
                f"macOS metadata in bundle: {bundle.name}"
            )
            included_files = {
                Path(name).name: name for name in names if not name.endswith("/")
            }
            assert set(included_files) == set(expected_files), (
                f"Unexpected contents in {bundle.name}: {sorted(included_files)}"
            )
            for filename, source in expected_files.items():
                assert archive.read(included_files[filename]) == source.read_bytes(), (
                    f"Stale file in {bundle.name}: {filename}"
                )

    checksum_path = SUBMISSION_OUTPUT / "SHA256SUMS"
    assert checksum_path.exists(), "Submission checksums are missing"
    expected_checksums = {
        *pdfs,
        ANONYMOUS_ZIP,
        *bundles.keys(),
    }
    recorded_checksums: dict[Path, str] = {}
    for line in checksum_path.read_text(encoding="utf-8").splitlines():
        digest, relative_path = line.split(maxsplit=1)
        recorded_checksums[(ROOT / relative_path.lstrip("*"))] = digest
    assert set(recorded_checksums) == expected_checksums, "Checksum manifest has missing or extra files"
    for path, expected_digest in recorded_checksums.items():
        actual_digest = hashlib.sha256(path.read_bytes()).hexdigest()
        assert actual_digest == expected_digest, f"Checksum mismatch: {path}"

    return [
        "two valid PDFs",
        "anonymous artifact has six reports",
        "no artifact identity leak",
        "two clean submission bundles",
        "submission checksums verified",
    ]


def check_metadata_renderer() -> list[str]:
    with tempfile.TemporaryDirectory(prefix="neloa-metadata-render-") as temporary:
        temporary_path = Path(temporary)
        output = temporary_path / "identifying"
        refusal = subprocess.run(
            [
                "python3",
                str(PAPER_DIR / "render_submission_metadata.py"),
                "--metadata",
                str(SUBMISSION / "author-metadata.example.json"),
                "--output",
                str(output),
                "--no-pdf",
            ],
            capture_output=True,
            text=True,
        )
        assert refusal.returncode != 0
        assert "Refusing example metadata" in refusal.stderr

        invalid = json.loads(
            (SUBMISSION / "author-metadata.example.json").read_text(encoding="utf-8")
        )
        invalid["authors"][0]["orcid"] = "0000-0002-1825-0098"
        invalid_path = temporary_path / "invalid-orcid.json"
        invalid_path.write_text(json.dumps(invalid), encoding="utf-8")
        invalid_result = subprocess.run(
            [
                "python3",
                str(PAPER_DIR / "render_submission_metadata.py"),
                "--metadata",
                str(invalid_path),
                "--output",
                str(output),
                "--no-pdf",
                "--allow-example",
            ],
            capture_output=True,
            text=True,
        )
        assert invalid_result.returncode != 0
        assert "invalid checksum" in invalid_result.stderr

        subprocess.run(
            [
                "python3",
                str(PAPER_DIR / "render_submission_metadata.py"),
                "--metadata",
                str(SUBMISSION / "author-metadata.example.json"),
                "--output",
                str(output),
                "--no-pdf",
                "--allow-example",
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        expected = {
            "iwc-title-page.md",
            "iwc-cover-letter.txt",
            "hcii-cms-metadata.md",
            "hcii-remote-presentation-inquiry.txt",
            "SHA256SUMS",
        }
        assert {path.name for path in output.iterdir()} == expected
        title_page = (output / "iwc-title-page.md").read_text(encoding="utf-8")
        assert "3,480" in title_page
        assert "[" not in title_page and "]" not in title_page
        recorded = (output / "SHA256SUMS").read_text(encoding="utf-8").splitlines()
        assert len(recorded) == 4
        for line in recorded:
            digest, filename = line.split(maxsplit=1)
            assert hashlib.sha256((output / filename).read_bytes()).hexdigest() == digest

    return ["identifying-metadata renderer validated"]


def main() -> None:
    checks = [
        *check_manuscripts(),
        *check_results(),
        *check_outputs(),
        *check_metadata_renderer(),
    ]
    print("Neloa submission audit PASSED")
    for check in checks:
        print(f"PASS  {check}")


if __name__ == "__main__":
    main()
