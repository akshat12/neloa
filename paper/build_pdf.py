#!/usr/bin/env python3
"""Build visually polished submission PDFs from Neloa's Markdown manuscripts.

The converter intentionally supports the small Markdown subset used by the paper. It
keeps the Markdown as the source of truth while using XeLaTeX and BibTeX for typography,
citations, and a human-readable reference list.
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PAPER = ROOT / "paper"
TEMP = ROOT / "tmp" / "pdfs"
OUTPUT = ROOT / "output" / "pdf"
XELATEX = Path("/Library/TeX/texbin/xelatex")
BIBTEX = Path("/Library/TeX/texbin/bibtex")


def run(command: list[str], cwd: Path) -> None:
    result = subprocess.run(command, cwd=cwd, text=True, capture_output=True)
    if result.returncode:
        tail = "\n".join((result.stdout + result.stderr).splitlines()[-80:])
        raise SystemExit(f"Command failed: {' '.join(command)}\n{tail}")


def parse_front_matter(text: str) -> tuple[dict[str, str], str]:
    if not text.startswith("---\n"):
        return {}, text
    _, front, body = text.split("---\n", 2)
    metadata: dict[str, str] = {}
    for line in front.splitlines():
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        metadata[key.strip()] = value.strip().strip('"')
    return metadata, body


def escape_tex(text: str) -> str:
    text = text.replace("—", "---").replace("–", "--").replace("‑", "-")
    replacements = {
        "\\": r"\textbackslash{}",
        "{": r"\{",
        "}": r"\}",
        "#": r"\#",
        "$": r"\$",
        "%": r"\%",
        "&": r"\&",
        "_": r"\_",
        "~": r"\textasciitilde{}",
        "^": r"\textasciicircum{}",
    }
    return "".join(replacements.get(character, character) for character in text)


def inline_tex(text: str) -> str:
    placeholders: list[str] = []

    def hold(value: str) -> str:
        token = f"@@TOKEN{len(placeholders)}@@"
        placeholders.append(value)
        return token

    text = re.sub(
        r"\[([^\]]*@[A-Za-z0-9:_-]+[^\]]*)\]",
        lambda match: hold(
            r"\citep{" + ",".join(re.findall(r"@([A-Za-z0-9:_-]+)", match.group(1))) + "}"
        ),
        text,
    )
    text = re.sub(r"<((?:https?|mailto):[^>]+)>", lambda match: hold(r"\url{" + match.group(1) + "}"), text)
    text = re.sub(r"`([^`]+)`", lambda match: hold(r"\texttt{" + escape_tex(match.group(1)) + "}"), text)
    text = re.sub(r"\*\*([^*]+)\*\*", lambda match: hold(r"\textbf{" + escape_tex(match.group(1)) + "}"), text)
    text = re.sub(r"\*([^*]+)\*", lambda match: hold(r"\emph{" + escape_tex(match.group(1)) + "}"), text)
    text = escape_tex(text)
    for index, value in enumerate(placeholders):
        text = text.replace(f"@@TOKEN{index}@@", value)
    return text


def flush_paragraph(lines: list[str], output: list[str]) -> None:
    if lines:
        output.append(inline_tex(" ".join(line.strip() for line in lines)))
        output.append("")
        lines.clear()


def convert_table(rows: list[str]) -> str:
    parsed = [[cell.strip() for cell in row.strip().strip("|").split("|")] for row in rows]
    parsed = [row for row in parsed if not all(re.fullmatch(r":?-{3,}:?", cell) for cell in row)]
    columns = len(parsed[0])
    if any(len(row) != columns for row in parsed):
        raise ValueError("Inconsistent Markdown table")
    alignment = "l" + "r" * (columns - 1)
    lines = [r"\begin{center}", r"\begin{minipage}{\textwidth}", r"\centering", r"\small", r"\resizebox{\textwidth}{!}{%", rf"\begin{{tabular}}{{{alignment}}}", r"\toprule"]
    for index, row in enumerate(parsed):
        lines.append(" & ".join(inline_tex(cell) for cell in row) + r" \\")
        if index == 0:
            lines.append(r"\midrule")
    lines.extend([r"\bottomrule", r"\end{tabular}%", "}", r"\captionof{table}{Frozen benchmark outcomes and local resource measurements. RSS is the whole-process high-water mark.}", r"\label{tab:results}", r"\end{minipage}", r"\end{center}"])
    return "\n".join(lines)


def markdown_to_latex(body: str, *, proposal: bool) -> str:
    body = re.sub(r"<!--.*?-->", "", body, flags=re.DOTALL)
    lines = body.splitlines()
    output: list[str] = []
    paragraph: list[str] = []
    index = 0
    in_abstract = False
    while index < len(lines):
        line = lines[index]
        stripped = line.strip()
        if not stripped or stripped.startswith("<!--"):
            flush_paragraph(paragraph, output)
            index += 1
            continue
        if stripped == "# References" or (proposal and stripped == "## References"):
            flush_paragraph(paragraph, output)
            if in_abstract:
                output.append(r"\end{abstract}")
                in_abstract = False
            break
        if stripped == "# Abstract":
            flush_paragraph(paragraph, output)
            output.append(r"\begin{abstract}")
            in_abstract = True
            index += 1
            continue
        heading = re.match(r"^(#{1,3})\s+(.+)$", stripped)
        if heading:
            flush_paragraph(paragraph, output)
            if in_abstract:
                output.append(r"\end{abstract}")
                in_abstract = False
            level = len(heading.group(1)) - (1 if proposal else 0)
            command = {1: "section", 2: "subsection", 3: "subsubsection"}.get(max(level, 1), "paragraph")
            title = re.sub(r"^\d+(?:\.\d+)*(?:\.)?\s+", "", heading.group(2))
            output.append(rf"\{command}{{{inline_tex(title)}}}")
            index += 1
            continue
        image = re.match(r"^!\[(.+)\]\(([^)]+)\)(?:\{[^}]+\})?$", stripped)
        if image:
            flush_paragraph(paragraph, output)
            caption = inline_tex(image.group(1))
            output.extend([
                r"\begin{figure}[tb]",
                r"\centering",
                r"\includegraphics[width=\textwidth]{architecture.png}",
                rf"\caption{{{caption}}}",
                r"\label{fig:architecture}",
                r"\end{figure}",
            ])
            index += 1
            continue
        if stripped.startswith("|"):
            flush_paragraph(paragraph, output)
            table_rows: list[str] = []
            while index < len(lines) and lines[index].strip().startswith("|"):
                table_rows.append(lines[index])
                index += 1
            output.append(convert_table(table_rows))
            continue
        if re.match(r"^\d+\.\s+", stripped):
            flush_paragraph(paragraph, output)
            items: list[str] = []
            while index < len(lines) and re.match(r"^\d+\.\s+", lines[index].strip()):
                items.append(re.sub(r"^\d+\.\s+", "", lines[index].strip()))
                index += 1
            output.append(r"\begin{enumerate}")
            output.extend(rf"\item {inline_tex(item)}\par" for item in items)
            output.append(r"\end{enumerate}")
            continue
        if stripped.startswith("- "):
            flush_paragraph(paragraph, output)
            items = []
            while index < len(lines) and lines[index].strip().startswith("- "):
                items.append(lines[index].strip()[2:])
                index += 1
            output.append(r"\begin{itemize}")
            output.extend(rf"\item {inline_tex(item)}\par" for item in items)
            output.append(r"\end{itemize}")
            continue
        if stripped.startswith("> "):
            flush_paragraph(paragraph, output)
            output.extend([r"\begin{quote}\itshape", inline_tex(stripped[2:]), r"\end{quote}"])
            index += 1
            continue
        paragraph.append(stripped)
        index += 1
    flush_paragraph(paragraph, output)
    if in_abstract:
        output.append(r"\end{abstract}")
    return "\n".join(output)


def preamble(title: str, subtitle: str | None, *, proposal: bool) -> str:
    subtitle_tex = inline_tex(subtitle) if subtitle else ""
    header_label = "HCII 2027 proposal" if proposal else "anonymized short paper"
    return rf"""\documentclass[10pt]{{article}}
\usepackage[letterpaper,margin=0.78in,top=0.72in,bottom=0.72in]{{geometry}}
\usepackage{{fontspec}}
\setmainfont{{Charter}}
\setsansfont{{Avenir Next}}
\usepackage{{microtype}}
\usepackage{{graphicx}}
\usepackage{{booktabs}}
\usepackage{{tabularx}}
\usepackage{{natbib}}
\usepackage{{caption}}
\usepackage{{fancyhdr}}
\usepackage{{xcolor}}
\usepackage[hidelinks]{{hyperref}}
\definecolor{{lagoon}}{{HTML}}{{087F8C}}
\definecolor{{ink}}{{HTML}}{{15343A}}
\definecolor{{muted}}{{HTML}}{{567078}}
\definecolor{{mist}}{{HTML}}{{F1F7F7}}
\hypersetup{{colorlinks=true,linkcolor=lagoon,citecolor=lagoon,urlcolor=lagoon,pdftitle={{{escape_tex(title)}}},pdfauthor={{Anonymous}}}}
\makeatletter
\renewcommand\section{{\@startsection{{section}}{{1}}{{0pt}}{{1.15em}}{{0.45em}}{{\sffamily\Large\bfseries\color{{ink}}}}}}
\renewcommand\subsection{{\@startsection{{subsection}}{{2}}{{0pt}}{{0.9em}}{{0.35em}}{{\sffamily\large\bfseries\color{{ink}}}}}}
\renewcommand\subsubsection{{\@startsection{{subsubsection}}{{3}}{{0pt}}{{0.75em}}{{0.3em}}{{\sffamily\normalsize\bfseries\color{{ink}}}}}}
\makeatother
\setlength{{\leftmargini}}{{1.5em}}
\setlength{{\parindent}}{{0pt}}
\setlength{{\parskip}}{{0.52em}}
\setlength{{\emergencystretch}}{{2em}}
\renewenvironment{{abstract}}{{\begin{{center}}\begin{{minipage}}{{0.92\textwidth}}\sffamily\small\color{{ink}}\textbf{{Abstract}}\par\vspace{{0.35em}}}}{{\end{{minipage}}\end{{center}}}}
\captionsetup{{font=small,labelfont={{sf,bf}},textfont=it,skip=6pt}}
\pagestyle{{fancy}}
\fancyhf{{}}
\fancyhead[L]{{\sffamily\footnotesize\color{{muted}} Neloa -- {header_label}}}
\fancyhead[R]{{\sffamily\footnotesize\color{{muted}} Bounded local desktop automation}}
\fancyfoot[C]{{\sffamily\footnotesize\color{{muted}}\thepage}}
\renewcommand{{\headrulewidth}}{{0.3pt}}
\title{{\sffamily\bfseries\color{{ink}}\fontsize{{23}}{{27}}\selectfont {inline_tex(title)}\\[0.45em]\large\color{{muted}} {subtitle_tex}}}
\author{{\sffamily Anonymous author}}
\date{{}}
\begin{{document}}
\maketitle
\vspace{{-1.4em}}
"""


def build(source: Path, stem: str, *, proposal: bool) -> Path:
    metadata, body = parse_front_matter(source.read_text(encoding="utf-8"))
    latex = preamble(metadata["title"], metadata.get("subtitle"), proposal=proposal)
    latex += markdown_to_latex(body, proposal=proposal)
    latex += "\n\\bibliographystyle{plainnat}\n\\bibliography{references}\n\\end{document}\n"

    build_dir = TEMP / stem
    build_dir.mkdir(parents=True, exist_ok=True)
    (build_dir / f"{stem}.tex").write_text(latex, encoding="utf-8")
    shutil.copy2(PAPER / "references.bib", build_dir / "references.bib")
    shutil.copy2(TEMP / "architecture.png", build_dir / "architecture.png")

    command = [str(XELATEX), "-interaction=nonstopmode", "-halt-on-error", f"{stem}.tex"]
    run(command, build_dir)
    run([str(BIBTEX), stem], build_dir)
    run(command, build_dir)
    run(command, build_dir)

    OUTPUT.mkdir(parents=True, exist_ok=True)
    destination = OUTPUT / f"{stem}.pdf"
    shutil.copy2(build_dir / f"{stem}.pdf", destination)
    return destination


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--paper-only", action="store_true")
    args = parser.parse_args()
    if not XELATEX.exists() or not BIBTEX.exists():
        raise SystemExit("MacTeX with XeLaTeX and BibTeX is required")
    TEMP.mkdir(parents=True, exist_ok=True)
    run(["sips", "-s", "format", "png", str(PAPER / "figures" / "architecture.svg"), "--out", str(TEMP / "architecture.png")], ROOT)
    outputs = [build(PAPER / "submission" / "short-paper.md", "neloa-short-paper", proposal=False)]
    if not args.paper_only:
        outputs.append(build(PAPER / "submission" / "hcii-2027-proposal.md", "neloa-hcii-2027-proposal", proposal=True))
    for output in outputs:
        print(output)


if __name__ == "__main__":
    main()
