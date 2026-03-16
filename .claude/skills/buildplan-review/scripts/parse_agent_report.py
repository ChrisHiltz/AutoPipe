#!/usr/bin/env python3
"""Parse a markdown audit report from a review agent and extract structured scores into JSON."""

import argparse
import json
import re
import sys
from pathlib import Path

CATEGORY_MAP = {
    "task_decomposition": ["task decomposition"],
    "parallelization_safety": ["parallelization safety"],
    "dependency_sequencing": ["dependency sequencing"],
    "instruction_clarity": ["instruction clarity"],
    "setup_determinism": ["determinism of setup", "setup determinism"],
    "worktree_pr_friendliness": ["worktree", "branch", "pr friendliness"],
    "cicd_readiness": ["ci/cd", "ci readiness"],
    "test_strategy": ["test strategy"],
    "merge_conflict_risk": ["merge-conflict", "merge conflict"],
    "human_loop_burden": ["human-in-the-loop", "human in the loop"],
    "secrets_config_env": ["secrets", "config", "environment"],
    "data_migration_safety": ["data migration", "state transition"],
    "failure_recovery": ["failure recovery", "rollback"],
    "observability": ["observability", "debugging"],
    "one_pass_likelihood": ["one-pass", "one pass", "likelihood"],
}


def match_category(text: str) -> str | None:
    """Fuzzy-match a table cell's text to a canonical category key."""
    lowered = text.lower().strip()
    # Try longest substring matches first for specificity
    best_key = None
    best_len = 0
    for key, aliases in CATEGORY_MAP.items():
        for alias in aliases:
            if alias in lowered and len(alias) > best_len:
                best_key = key
                best_len = len(alias)
    return best_key


def extract_score(cell: str) -> int | None:
    """Extract a numeric score from a table cell like '8/10' or '8'."""
    # Try X/10 pattern first
    m = re.search(r'\b(\d{1,2})\s*/\s*10\b', cell)
    if m:
        return int(m.group(1))
    # Try standalone number (1-10 range)
    m = re.search(r'\b(\d{1,2})\b', cell)
    if m:
        val = int(m.group(1))
        if 0 <= val <= 10:
            return val
    return None


def parse_scorecard(content: str) -> tuple[dict[str, int | None], list[str]]:
    """Parse markdown tables to extract category scores."""
    scores: dict[str, int | None] = {k: None for k in CATEGORY_MAP}
    warnings: list[str] = []
    matched_keys: set[str] = set()

    # Find all markdown table rows: lines starting with |
    table_rows = re.findall(r'^\|(.+)\|$', content, re.MULTILINE)

    for row in table_rows:
        cells = [c.strip() for c in row.split('|')]
        # Skip separator rows
        if all(re.match(r'^[-:]+$', c) or c == '' for c in cells):
            continue
        # Skip header rows that literally say "Category" and "Score"
        if any(c.lower() in ('category', 'score', 'weight', 'notes', 'comments', 'justification') for c in cells):
            # But only skip if it looks like a header (contains "category" or "score")
            cell_text = ' '.join(cells).lower()
            if 'category' in cell_text and 'score' in cell_text:
                continue

        # Try to match a category from any cell
        for i, cell in enumerate(cells):
            key = match_category(cell)
            if key and key not in matched_keys:
                # Look for score in remaining cells
                score = None
                for j, other_cell in enumerate(cells):
                    if j != i:
                        score = extract_score(other_cell)
                        if score is not None:
                            break
                scores[key] = score
                matched_keys.add(key)
                if score is None:
                    warnings.append(f"Could not extract score for category {key}")
                break

    # Warn about categories never found
    for key in CATEGORY_MAP:
        if key not in matched_keys:
            warnings.append(f"Could not extract score for category {key}")

    return scores, warnings


def extract_findings(content: str) -> list[dict]:
    """Extract findings from sections like Critical Findings, Blockers, High Risk, Top 10."""
    findings: list[dict] = []

    # Find relevant sections
    section_pattern = re.compile(
        r'^#{2,3}\s*(?:Critical\s+Findings|Findings|Top\s+\d+|Blockers|High\s+Risk|Issues).*$',
        re.MULTILINE | re.IGNORECASE
    )
    matches = list(section_pattern.finditer(content))

    if not matches:
        return findings

    for idx, match in enumerate(matches):
        start = match.end()
        # Section ends at next heading of same or higher level, or EOF
        end = matches[idx + 1].start() if idx + 1 < len(matches) else len(content)
        section = content[start:end]

        # Split into individual findings by numbered items, bullet items, or sub-headers
        # Pattern: lines starting with a number, dash/bullet, or ### sub-header
        finding_blocks = re.split(r'\n(?=\d+[\.\)]\s|[-*]\s+\*\*|###\s)', section)

        for block in finding_blocks:
            block = block.strip()
            if not block or len(block) < 10:
                continue

            finding: dict = {
                "id": None,
                "severity": None,
                "fix_location": [],
                "summary": None,
            }

            # Extract ID: patterns like "1-1", "1-2", or "Issue ID: 1-1"
            id_match = re.search(r'(?:Issue\s*ID\s*:\s*)?(\d+-\d+)', block)
            if id_match:
                finding["id"] = id_match.group(1)

            # Extract severity
            sev_match = re.search(
                r'\b(blocker|critical|high|medium|low|info)\b', block, re.IGNORECASE
            )
            if sev_match:
                finding["severity"] = sev_match.group(1).lower()

            # Extract file paths (common patterns)
            path_matches = re.findall(
                r'(?:^|\s|`)((?:[\w./-]+/)+[\w.-]+(?:\.\w+)?)`?', block
            )
            finding["fix_location"] = list(dict.fromkeys(path_matches))  # dedupe, preserve order

            # Extract summary: first line after "What's broken:" or first meaningful line
            summary_match = re.search(
                r"(?:What'?s\s+broken|Summary|Description)\s*:\s*(.+)", block, re.IGNORECASE
            )
            if summary_match:
                finding["summary"] = summary_match.group(1).strip()
            else:
                # Use the first non-empty line as summary
                for line in block.split('\n'):
                    line = line.strip().lstrip('0123456789.)- *#')
                    line = re.sub(r'\*\*', '', line).strip()
                    if line and len(line) > 5:
                        finding["summary"] = line[:200]
                        break

            if finding["id"] or finding["summary"]:
                findings.append(finding)

    return findings


def extract_agent_number(filepath: str) -> int | None:
    """Try to extract the agent number from the filename."""
    m = re.search(r'agent[_-]?report[_-]?(\d+)', Path(filepath).stem, re.IGNORECASE)
    if m:
        return int(m.group(1))
    m = re.search(r'(\d+)', Path(filepath).stem)
    if m:
        return int(m.group(1))
    return None


def parse_report(input_path: str) -> dict:
    """Main parsing logic. Returns structured JSON-ready dict."""
    path = Path(input_path)
    if not path.exists():
        return {"error": f"File not found: {input_path}", "raw_length": 0}

    content = path.read_text(encoding='utf-8', errors='replace')
    if not content.strip():
        return {"error": "Empty file", "raw_length": 0}

    try:
        scores, warnings = parse_scorecard(content)
        findings = extract_findings(content)
        agent_num = extract_agent_number(input_path)

        non_null = [v for v in scores.values() if v is not None]
        overall = round(sum(non_null) / len(non_null) * 10) if non_null else None

        return {
            "agent_number": agent_num,
            "scores": scores,
            "overall_score": overall,
            "findings": findings,
            "parse_warnings": warnings,
        }
    except Exception as e:
        return {"error": str(e), "raw_length": len(content)}


def main():
    parser = argparse.ArgumentParser(description="Parse agent audit report to JSON")
    parser.add_argument("--input", required=True, help="Path to markdown report")
    parser.add_argument("--output", required=True, help="Path for output JSON")
    args = parser.parse_args()

    result = parse_report(args.input)

    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding='utf-8')

    if "error" in result:
        print(f"ERROR: {result['error']}", file=sys.stderr)
        sys.exit(1)

    n_scores = sum(1 for v in result["scores"].values() if v is not None)
    n_findings = len(result["findings"])
    n_warnings = len(result["parse_warnings"])
    print(f"Parsed {n_scores}/15 scores, {n_findings} findings, {n_warnings} warnings -> {args.output}")


if __name__ == "__main__":
    main()
