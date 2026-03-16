#!/usr/bin/env python3
"""Synthesize multiple agent score JSONs into an audit synthesis report."""

import argparse
import glob
import json
import statistics
import sys
from datetime import datetime, timezone
from pathlib import Path

ALL_CATEGORIES = [
    "task_decomposition",
    "parallelization_safety",
    "dependency_sequencing",
    "instruction_clarity",
    "setup_determinism",
    "worktree_pr_friendliness",
    "cicd_readiness",
    "test_strategy",
    "merge_conflict_risk",
    "human_loop_burden",
    "secrets_config_env",
    "data_migration_safety",
    "failure_recovery",
    "observability",
    "one_pass_likelihood",
]

# Map category keys to keywords for matching findings to categories
CATEGORY_KEYWORDS = {
    "task_decomposition": ["task", "decomposition", "breakdown", "subtask"],
    "parallelization_safety": ["parallel", "concurrent", "race condition"],
    "dependency_sequencing": ["dependency", "sequencing", "order", "prerequisite"],
    "instruction_clarity": ["instruction", "clarity", "ambiguous", "unclear"],
    "setup_determinism": ["setup", "determinism", "deterministic", "reproducible"],
    "worktree_pr_friendliness": ["worktree", "branch", "pr", "pull request"],
    "cicd_readiness": ["ci", "cd", "pipeline", "ci/cd", "cicd"],
    "test_strategy": ["test", "testing", "coverage", "assertion"],
    "merge_conflict_risk": ["merge", "conflict"],
    "human_loop_burden": ["human", "loop", "manual", "intervention"],
    "secrets_config_env": ["secret", "config", "env", "environment", "credential"],
    "data_migration_safety": ["migration", "data", "state", "transition", "schema"],
    "failure_recovery": ["failure", "recovery", "rollback", "fallback"],
    "observability": ["observability", "debug", "logging", "monitoring", "trace"],
    "one_pass_likelihood": ["one-pass", "one pass", "likelihood", "single pass"],
}


def classify_range(score_range: int) -> str:
    """Classify the agreement level based on score range."""
    if score_range <= 2:
        return "consensus"
    elif score_range <= 4:
        return "split"
    else:
        return "outlier"


def match_finding_to_category(finding: dict) -> str | None:
    """Try to match a finding to a category based on its summary and fix_location."""
    text = ""
    if finding.get("summary"):
        text += finding["summary"].lower() + " "
    for loc in finding.get("fix_location", []):
        text += loc.lower() + " "

    best_cat = None
    best_count = 0
    for cat, keywords in CATEGORY_KEYWORDS.items():
        count = sum(1 for kw in keywords if kw in text)
        if count > best_count:
            best_count = count
            best_cat = cat
    return best_cat if best_count > 0 else None


def deduplicate_findings(all_findings: list[dict]) -> list[dict]:
    """Group findings by fix_location, merge summaries."""
    location_groups: dict[str, dict] = {}

    for f in all_findings:
        locs = tuple(sorted(f.get("fix_location", [])))
        loc_key = "|".join(locs) if locs else f.get("id", "") or f.get("summary", "")[:50]

        if not loc_key:
            loc_key = f"orphan_{len(location_groups)}"

        if loc_key in location_groups:
            existing = location_groups[loc_key]
            # Merge summaries
            if f.get("summary") and f["summary"] not in existing["summaries"]:
                existing["summaries"].append(f["summary"])
            if f.get("id") and f["id"] not in existing["ids"]:
                existing["ids"].append(f["id"])
            # Keep highest severity
            severity_order = {"blocker": 4, "critical": 3, "high": 2, "medium": 1, "low": 0, "info": 0}
            cur_sev = severity_order.get(existing.get("severity") or "", -1)
            new_sev = severity_order.get(f.get("severity") or "", -1)
            if new_sev > cur_sev:
                existing["severity"] = f.get("severity")
        else:
            location_groups[loc_key] = {
                "ids": [f["id"]] if f.get("id") else [],
                "severity": f.get("severity"),
                "fix_location": list(locs),
                "summaries": [f["summary"]] if f.get("summary") else [],
            }

    deduped = []
    for group in location_groups.values():
        deduped.append({
            "ids": group["ids"],
            "severity": group["severity"],
            "fix_location": group["fix_location"],
            "summary": " | ".join(group["summaries"]) if group["summaries"] else None,
        })
    return deduped


def load_agent_files(input_dir: str) -> list[dict]:
    """Load all agent-*-scores.json files from a directory."""
    pattern = str(Path(input_dir) / "agent-*-scores.json")
    files = sorted(glob.glob(pattern))
    agents = []
    for f in files:
        try:
            data = json.loads(Path(f).read_text(encoding='utf-8'))
            if "error" not in data:
                agents.append(data)
            else:
                print(f"WARNING: Skipping {f} (parse error: {data['error']})", file=sys.stderr)
        except (json.JSONDecodeError, OSError) as e:
            print(f"WARNING: Could not load {f}: {e}", file=sys.stderr)
    return agents


def synthesize(agents: list[dict], previous: dict | None = None) -> dict:
    """Produce an audit synthesis from multiple agent score files."""
    category_scores: dict[str, dict] = {}
    all_findings: list[dict] = []
    # Collect findings-to-category mapping
    category_findings: dict[str, list[str]] = {c: [] for c in ALL_CATEGORIES}
    category_files: dict[str, list[str]] = {c: [] for c in ALL_CATEGORIES}

    # Gather all findings from all agents
    for agent in agents:
        for finding in agent.get("findings", []):
            all_findings.append(finding)
            cat = match_finding_to_category(finding)
            if cat:
                if finding.get("id"):
                    category_findings[cat].append(finding["id"])
                for loc in finding.get("fix_location", []):
                    if loc not in category_files[cat]:
                        category_files[cat].append(loc)

    # Compute per-category statistics
    medians: list[float] = []
    for cat in ALL_CATEGORIES:
        scores_list = []
        for agent in agents:
            s = agent.get("scores", {}).get(cat)
            if s is not None:
                scores_list.append(s)

        if len(scores_list) >= 2:
            med = statistics.median(scores_list)
            score_range = max(scores_list) - min(scores_list)
            classification = classify_range(score_range)
            category_scores[cat] = {
                "median": med,
                "scores": scores_list,
                "range": score_range,
                "classification": classification,
            }
            medians.append(med)
        else:
            category_scores[cat] = {
                "median": None,
                "scores": scores_list,
                "range": None,
                "classification": "insufficient_data",
            }

    # Overall score
    overall = round(statistics.mean(medians) * 10) if medians else None

    # Fix targets: categories where median < 9
    fix_targets = []
    for cat in ALL_CATEGORIES:
        info = category_scores[cat]
        if info["median"] is not None and info["median"] < 9:
            fix_targets.append({
                "category": cat,
                "median": info["median"],
                "all_scores": info["scores"],
                "classification": info["classification"],
                "agent_findings": category_findings.get(cat, []),
                "affected_files": category_files.get(cat, []),
                "fix_pattern_key": cat,
            })

    # Sort fix_targets by median ascending (worst first)
    fix_targets.sort(key=lambda x: x["median"])

    # Deduplicate findings
    deduped = deduplicate_findings(all_findings)

    # Compute deltas against previous synthesis
    deltas: dict[str, float] = {}
    if previous and "category_scores" in previous:
        for cat in ALL_CATEGORIES:
            old_med = previous["category_scores"].get(cat, {}).get("median")
            new_med = category_scores[cat]["median"]

            if new_med is not None and old_med is not None:
                deltas[cat] = round(new_med - old_med, 1)
            elif new_med is None and old_med is not None:
                # Carry forward old score if no new data
                category_scores[cat] = previous["category_scores"][cat].copy()
                category_scores[cat]["classification"] = (
                    previous["category_scores"][cat].get("classification", "carried_forward")
                )
                if old_med is not None and old_med not in [m for m in medians]:
                    medians.append(old_med)

        # Recompute overall if medians changed from carry-forward
        if medians:
            overall = round(statistics.mean(medians) * 10)

    return {
        "overall_score": overall,
        "agents_reporting": len(agents),
        "category_scores": category_scores,
        "fix_targets": fix_targets,
        "deduplicated_findings": deduped,
        "deltas": deltas,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


def main():
    parser = argparse.ArgumentParser(description="Synthesize agent scores into audit report")
    parser.add_argument("--input-dir", required=True, help="Directory containing agent-*-scores.json files")
    parser.add_argument("--output", required=True, help="Path for output synthesis JSON")
    parser.add_argument("--previous-synthesis", default=None, help="Path to previous synthesis for delta tracking")
    args = parser.parse_args()

    agents = load_agent_files(args.input_dir)
    if not agents:
        print("ERROR: No valid agent score files found", file=sys.stderr)
        sys.exit(1)

    previous = None
    if args.previous_synthesis:
        prev_path = Path(args.previous_synthesis)
        if prev_path.exists():
            try:
                previous = json.loads(prev_path.read_text(encoding='utf-8'))
            except (json.JSONDecodeError, OSError) as e:
                print(f"WARNING: Could not load previous synthesis: {e}", file=sys.stderr)

    result = synthesize(agents, previous)

    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding='utf-8')

    n_cats = sum(1 for v in result["category_scores"].values() if v["median"] is not None)
    n_fixes = len(result["fix_targets"])
    n_findings = len(result["deduplicated_findings"])
    print(
        f"Synthesized {result['agents_reporting']} agents: "
        f"{n_cats}/15 categories scored, {n_fixes} fix targets, "
        f"{n_findings} deduplicated findings -> {args.output}"
    )


if __name__ == "__main__":
    main()
