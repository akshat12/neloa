#!/usr/bin/env python3
"""Render identifying submission files from one locally stored metadata record."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import tempfile
from datetime import date
from pathlib import Path
from typing import Any

from build_pdf import XELATEX, escape_tex, parse_front_matter


ROOT = Path(__file__).resolve().parents[1]
SUBMISSION = ROOT / "paper" / "submission"
DEFAULT_OUTPUT = ROOT / "output" / "submission" / "identifying"
PAPER_TITLE = (
    "Separating Interpretation from Authority: Bounded Local Adaptation for "
    "Desktop Automation by Demonstration"
)
PUBLIC_REPOSITORY = "https://github.com/akshat12/neloa"


class MetadataError(ValueError):
    """Raised when identifying metadata is missing, invalid, or still illustrative."""


def required_string(container: dict[str, Any], key: str, location: str) -> str:
    value = container.get(key)
    if not isinstance(value, str) or not value.strip():
        raise MetadataError(f"{location}.{key} must be a non-empty string")
    value = value.strip()
    if "[" in value or "]" in value:
        raise MetadataError(f"{location}.{key} still contains a placeholder")
    return value


def validate_orcid(value: str) -> bool:
    compact = value.replace("-", "").upper()
    if not re.fullmatch(r"\d{15}[\dX]", compact):
        return False
    total = 0
    for character in compact[:15]:
        total = (total + int(character)) * 2
    remainder = (12 - total % 11) % 11
    expected = "X" if remainder == 10 else str(remainder)
    return compact[-1] == expected


def validate_metadata(raw: Any, *, allow_example: bool = False) -> dict[str, Any]:
    if not isinstance(raw, dict):
        raise MetadataError("metadata root must be an object")
    serialized = json.dumps(raw, sort_keys=True)
    if not allow_example and (
        raw.get("is_example") is not False
        or re.search(r"\bExample\b|example\.com", serialized, re.IGNORECASE)
    ):
        raise MetadataError(
            "Refusing example metadata. Copy it to paper/submission/author-metadata.json, "
            "replace every example value, and set is_example to false."
        )

    submission_date = required_string(raw, "submission_date", "metadata")
    try:
        date.fromisoformat(submission_date)
    except ValueError as error:
        raise MetadataError("metadata.submission_date must use YYYY-MM-DD") from error

    authors = raw.get("authors")
    if not isinstance(authors, list) or not authors:
        raise MetadataError("metadata.authors must contain at least one author")
    normalized_authors: list[dict[str, str]] = []
    for index, author in enumerate(authors):
        location = f"metadata.authors[{index}]"
        if not isinstance(author, dict):
            raise MetadataError(f"{location} must be an object")
        full_name = required_string(author, "full_name", location)
        institution = required_string(author, "institution", location)
        city_country = required_string(author, "city_country", location)
        department = author.get("department", "")
        if not isinstance(department, str):
            raise MetadataError(f"{location}.department must be a string")
        orcid = author.get("orcid", "")
        if not isinstance(orcid, str):
            raise MetadataError(f"{location}.orcid must be a string")
        if orcid and not validate_orcid(orcid):
            raise MetadataError(f"{location}.orcid has an invalid checksum")
        normalized_authors.append(
            {
                "full_name": full_name,
                "department": department.strip(),
                "institution": institution,
                "city_country": city_country,
                "orcid": orcid.strip(),
            }
        )

    corresponding_index = raw.get("corresponding_author_index")
    if not isinstance(corresponding_index, int) or not 0 <= corresponding_index < len(authors):
        raise MetadataError("metadata.corresponding_author_index is out of range")
    if not normalized_authors[corresponding_index]["orcid"]:
        raise MetadataError("The corresponding author must provide a validated ORCID")

    correspondence = raw.get("correspondence")
    if not isinstance(correspondence, dict):
        raise MetadataError("metadata.correspondence must be an object")
    normalized_correspondence = {
        field: required_string(correspondence, field, "metadata.correspondence")
        for field in ("postal_address", "email", "telephone")
    }
    if not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", normalized_correspondence["email"]):
        raise MetadataError("metadata.correspondence.email is invalid")

    declarations = raw.get("declarations")
    if not isinstance(declarations, dict):
        raise MetadataError("metadata.declarations must be an object")
    normalized_declarations = {
        field: required_string(declarations, field, "metadata.declarations")
        for field in ("funding", "competing_interests", "acknowledgements")
    }

    confirmations = raw.get("confirmations")
    required_confirmations = (
        "original_work",
        "not_under_consideration_elsewhere",
        "human_reviewed_ai_assistance",
    )
    if not isinstance(confirmations, dict) or any(
        confirmations.get(field) is not True for field in required_confirmations
    ):
        raise MetadataError(
            "All originality, exclusive-consideration, and human-review confirmations must be true"
        )

    return {
        "submission_date": submission_date,
        "authors": normalized_authors,
        "corresponding_author_index": corresponding_index,
        "correspondence": normalized_correspondence,
        "declarations": normalized_declarations,
    }


def manuscript_word_count() -> int:
    manuscript = (SUBMISSION / "short-paper.md").read_text(encoding="utf-8")
    manuscript = re.sub(r"^---\n.*?\n---\n", "", manuscript, flags=re.DOTALL)
    manuscript = manuscript.split("# References", 1)[0]
    manuscript = manuscript.split("**Keywords:**", 1)[1]
    manuscript = re.sub(r"<!--.*?-->", "", manuscript, flags=re.DOTALL)
    return len(re.findall(r"\b[\w’'-]+\b", manuscript))


def proposal_word_count() -> int:
    proposal = (SUBMISSION / "hcii-2027-proposal.md").read_text(encoding="utf-8")
    _, body = parse_front_matter(proposal)
    body = body.split("## References", 1)[0]
    body = re.sub(r"<!--.*?-->", "", body, flags=re.DOTALL)
    return len(re.findall(r"\b[\w’'-]+\b", body))


def display_date(value: str) -> str:
    parsed = date.fromisoformat(value)
    return f"{parsed.strftime('%B')} {parsed.day}, {parsed.year}"


def affiliation(author: dict[str, str]) -> str:
    parts = [author["department"], author["institution"], author["city_country"]]
    return ", ".join(part for part in parts if part)


def render_title_page_markdown(metadata: dict[str, Any]) -> str:
    author_lines = []
    for index, author in enumerate(metadata["authors"], 1):
        author_lines.extend(
            [
                f"{index}. **{author['full_name']}**  ",
                f"   {affiliation(author)}  ",
                f"   ORCID: {author['orcid'] or 'Not supplied'}",
                "",
            ]
        )
    corresponding = metadata["authors"][metadata["corresponding_author_index"]]
    correspondence = metadata["correspondence"]
    declarations = metadata["declarations"]
    return "\n".join(
        [
            "# Title Page - Interacting with Computers",
            "",
            f"**Title:** {PAPER_TITLE}",
            "",
            "**Article type:** Short Research Paper",
            "",
            f"**Main-manuscript word count:** {manuscript_word_count():,}",
            "",
            "## Authors",
            "",
            *author_lines,
            "## Corresponding author",
            "",
            f"{corresponding['full_name']}  ",
            f"{correspondence['postal_address']}  ",
            f"{correspondence['email']}  ",
            correspondence["telephone"],
            "",
            "## Declarations",
            "",
            f"**Funding:** {declarations['funding']}",
            "",
            f"**Competing interests:** {declarations['competing_interests']}",
            "",
            f"**Acknowledgements:** {declarations['acknowledgements']}",
            "",
            "**Data and software:** Source code, the frozen evaluation manifest, synthetic fixtures, "
            f"raw machine-readable reports, and analysis scripts are available at {PUBLIC_REPOSITORY}. "
            "No personal recordings, human-participant data, or live third-party account data are included.",
            "",
            "**Human participants:** The reported study used synthetic, account-free cases and did not "
            "involve human participants.",
            "",
            "**Generative-AI assistance:** OpenAI Codex assisted with software development, test "
            "scaffolding, literature discovery, drafting, copy-editing, and preparation of figures and "
            "analysis scripts. The human author directed and reviewed the work and accepts full "
            "responsibility for its accuracy, originality, citations, licensing, and conclusions.",
            "",
        ]
    )


def render_cover_letter(metadata: dict[str, Any]) -> str:
    corresponding = metadata["authors"][metadata["corresponding_author_index"]]
    correspondence = metadata["correspondence"]
    possessive = "my" if len(metadata["authors"]) == 1 else "our"
    return "\n".join(
        [
            display_date(metadata["submission_date"]),
            "",
            "Dear Editors,",
            "",
            f'Please consider {possessive} Short Research Paper, "{PAPER_TITLE}," for publication in '
            "Interacting with Computers.",
            "",
            "The paper presents Neloa, an open-source macOS system that lets a person demonstrate "
            "a workflow and later change bounded details such as dates, amounts, files, and form "
            "values. A local multimodal model supports interpretation, while deterministic software "
            "limits execution to a reviewed action graph and preserves approval gates. We report a "
            "frozen, reproducible 15-case formative benchmark of two quantization tiers, with all six "
            "fresh-process trials retained alongside local resource measurements.",
            "",
            "The work is relevant to the journal's readership because it examines human-centred AI, "
            "mixed-initiative interaction, end-user automation, privacy, and legible agent authority. "
            "The evaluation boundary is explicit: the study uses synthetic cases and executable "
            "assertions and does not claim arbitrary desktop reliability or end-user usability.",
            "",
            "The manuscript is original and is not under consideration elsewhere. It contains no "
            "human-participant or personal-recording data. Source, protocol, fixtures, raw reports, "
            "and analysis code are supplied in an anonymized review artifact. Generative-AI assistance "
            "is disclosed in the manuscript; the named author or authors reviewed the work and accept "
            "responsibility for its accuracy and originality.",
            "",
            "Sincerely,",
            "",
            corresponding["full_name"],
            affiliation(corresponding),
            correspondence["email"],
            f"ORCID: {corresponding['orcid']}",
            "",
        ]
    )


def render_hcii_metadata(metadata: dict[str, Any]) -> str:
    author_lines = [
        f"{index}. {author['full_name']} - {affiliation(author)} - ORCID {author['orcid'] or 'not supplied'}"
        for index, author in enumerate(metadata["authors"], 1)
    ]
    corresponding = metadata["authors"][metadata["corresponding_author_index"]]
    correspondence = metadata["correspondence"]
    return "\n".join(
        [
            "# HCII 2027 CMS entry",
            "",
            f"**Title:** {PAPER_TITLE}",
            "",
            "**Submission type:** Regular Paper proposal",
            "",
            "**Thematic area:** AI-HCI - Artificial Intelligence in HCI",
            "",
            f"**Proposal file:** neloa-hcii-2027-proposal.pdf ({proposal_word_count()} words excluding references)",
            "",
            "**Authors:**",
            "",
            *author_lines,
            "",
            f"**Corresponding author:** {corresponding['full_name']}",
            "",
            f"**Email:** {correspondence['email']}",
            "",
            "**Proposal deadline:** October 9, 2026 (Anywhere on Earth)",
            "",
            "**Remote-presentation status:** Confirm with the program office before paying registration; "
            "the public site advertises online participation but does not explicitly bind that option "
            "to an accepted regular paper's required presentation.",
            "",
        ]
    )


def render_remote_inquiry(metadata: dict[str, Any]) -> str:
    corresponding = metadata["authors"][metadata["corresponding_author_index"]]
    return "\n".join(
        [
            "To: program@2027.hci.international",
            "Subject: Remote presentation eligibility for an accepted AI-HCI regular paper",
            "",
            "Dear HCII 2027 Program Team,",
            "",
            "I am preparing an 800-word proposal for the AI-HCI thematic area. The conference website "
            "states that HCII 2027 will be held on site with an additional option for online "
            "participation. Before submitting, could you please confirm whether the registered author "
            "of an accepted regular paper may deliver the required presentation remotely and still "
            "satisfy the conference's publication and presentation requirements?",
            "",
            "Thank you,",
            "",
            corresponding["full_name"],
            "",
        ]
    )


def render_title_page_pdf(metadata: dict[str, Any], destination: Path) -> None:
    if not XELATEX.exists():
        raise MetadataError("MacTeX with XeLaTeX is required to render the title-page PDF")
    authors = metadata["authors"]
    corresponding = authors[metadata["corresponding_author_index"]]
    correspondence = metadata["correspondence"]
    declarations = metadata["declarations"]
    author_rows = []
    for index, author in enumerate(authors, 1):
        orcid = f"ORCID: {author['orcid']}" if author["orcid"] else "ORCID not supplied"
        author_rows.append(
            rf"\textbf{{{index}. {escape_tex(author['full_name'])}}}\\"
            rf"{escape_tex(affiliation(author))}\\{escape_tex(orcid)}\par\vspace{{0.65em}}"
        )
    document = rf"""\documentclass[11pt]{{article}}
\usepackage[letterpaper,margin=0.9in]{{geometry}}
\usepackage{{fontspec}}
\setmainfont{{Charter}}
\setsansfont{{Avenir Next}}
\usepackage{{microtype}}
\usepackage{{xcolor}}
\usepackage[hidelinks]{{hyperref}}
\definecolor{{lagoon}}{{HTML}}{{087F8C}}
\definecolor{{ink}}{{HTML}}{{15343A}}
\hypersetup{{pdftitle={{Neloa - Interacting with Computers title page}},pdfauthor={{{escape_tex(', '.join(author['full_name'] for author in authors))}}}}}
\setlength{{\parindent}}{{0pt}}
\setlength{{\parskip}}{{0.55em}}
\setlength{{\emergencystretch}}{{2em}}
\newcommand{{\submissionsection}}[1]{{\vspace{{0.7em}}{{\sffamily\large\bfseries\color{{ink}} #1}}\par\vspace{{0.15em}}}}
\begin{{document}}
\begin{{center}}
{{\sffamily\bfseries\color{{ink}}\fontsize{{22}}{{26}}\selectfont Interacting with Computers\par}}
\vspace{{0.35em}}{{\sffamily\large Title Page\par}}
\end{{center}}
\submissionsection{{Manuscript}}
\textbf{{Title:}} {escape_tex(PAPER_TITLE)}\par
\textbf{{Article type:}} Short Research Paper\par
\textbf{{Main-manuscript word count:}} {manuscript_word_count():,}\par
\submissionsection{{Authors}}
{''.join(author_rows)}
\submissionsection{{Corresponding author}}
\textbf{{{escape_tex(corresponding['full_name'])}}}\\
{escape_tex(correspondence['postal_address'])}\\
{escape_tex(correspondence['email'])}\\
{escape_tex(correspondence['telephone'])}\par
\submissionsection{{Declarations}}
\textbf{{Funding:}} {escape_tex(declarations['funding'])}\par
\textbf{{Competing interests:}} {escape_tex(declarations['competing_interests'])}\par
\textbf{{Acknowledgements:}} {escape_tex(declarations['acknowledgements'])}\par
\textbf{{Data and software:}} Source code, the frozen evaluation manifest, synthetic fixtures, raw machine-readable reports, and analysis scripts are available at \url{{{PUBLIC_REPOSITORY}}}. No personal recordings, human-participant data, or live third-party account data are included.\par
\textbf{{Human participants:}} The reported study used synthetic, account-free cases and did not involve human participants.\par
\textbf{{Generative-AI assistance:}} OpenAI Codex assisted with software development, test scaffolding, literature discovery, drafting, copy-editing, and preparation of figures and analysis scripts. The named author or authors directed and reviewed the work and accept full responsibility for its accuracy, originality, citations, licensing, and conclusions.\par
\end{{document}}
"""
    temporary_parent = ROOT / "tmp" / "pdfs"
    temporary_parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="identifying-title-page-", dir=temporary_parent) as temporary:
        build_dir = Path(temporary)
        source = build_dir / "iwc-title-page.tex"
        source.write_text(document, encoding="utf-8")
        result = subprocess.run(
            [str(XELATEX), "-interaction=nonstopmode", "-halt-on-error", source.name],
            cwd=build_dir,
            text=True,
            capture_output=True,
        )
        if result.returncode:
            tail = "\n".join((result.stdout + result.stderr).splitlines()[-60:])
            raise MetadataError(f"Title-page PDF rendering failed:\n{tail}")
        shutil.copy2(build_dir / "iwc-title-page.pdf", destination)
        destination.chmod(0o600)


def write_outputs(metadata: dict[str, Any], output: Path, *, render_pdf: bool) -> list[Path]:
    output.mkdir(parents=True, exist_ok=True)
    output.chmod(0o700)
    known_outputs = {
        "iwc-title-page.md",
        "iwc-title-page.pdf",
        "iwc-cover-letter.txt",
        "hcii-cms-metadata.md",
        "hcii-remote-presentation-inquiry.txt",
        "SHA256SUMS",
    }
    for filename in known_outputs:
        (output / filename).unlink(missing_ok=True)
    contents = {
        "iwc-title-page.md": render_title_page_markdown(metadata),
        "iwc-cover-letter.txt": render_cover_letter(metadata),
        "hcii-cms-metadata.md": render_hcii_metadata(metadata),
        "hcii-remote-presentation-inquiry.txt": render_remote_inquiry(metadata),
    }
    generated = []
    for filename, content in contents.items():
        destination = output / filename
        destination.write_text(content, encoding="utf-8")
        destination.chmod(0o600)
        generated.append(destination)
    if render_pdf:
        destination = output / "iwc-title-page.pdf"
        render_title_page_pdf(metadata, destination)
        generated.append(destination)
    checksum = output / "SHA256SUMS"
    checksum.write_text(
        "".join(
            f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n"
            for path in sorted(generated)
        ),
        encoding="utf-8",
    )
    checksum.chmod(0o600)
    generated.append(checksum)
    return generated


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--metadata", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--no-pdf", action="store_true")
    parser.add_argument("--allow-example", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    try:
        raw = json.loads(args.metadata.read_text(encoding="utf-8"))
        metadata = validate_metadata(raw, allow_example=args.allow_example)
        outputs = write_outputs(metadata, args.output, render_pdf=not args.no_pdf)
    except (OSError, json.JSONDecodeError, MetadataError) as error:
        raise SystemExit(f"Submission metadata error: {error}") from error
    for output in outputs:
        print(output)


if __name__ == "__main__":
    main()
