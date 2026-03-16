#!/usr/bin/env python3
"""Extended validation of a build plan using plan-catalog.json.

Runs 26 checks with severity tiers (blocker | warning | info) and writes
validation-report.json alongside the input catalog.  Exits 0 on PASS, 1 on
BLOCKED or error.

Usage:
    python validate_plan_extended.py <path-to-plan-catalog.json>

No external dependencies.
"""

import json
import re
import sys
from collections import defaultdict
from pathlib import Path

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

REQUIRED_ARTIFACTS = [
    "PLAN-SUMMARY.md", "DEPENDENCY-GRAPH.md", "CONTRACTS.md",
    "WORKSTREAMS.md", "HUMAN-GATES.md", "RISKS.md",
]

REQUIRED_FM_FIELDS = [
    "id", "title", "workstream", "build_block", "estimated_hours",
    "depends_on", "human_gate", "review_tier", "files_touched",
    "acceptance_criteria",
]

VALID_REVIEW_TIERS = {"must_review", "review_by_summary", "auto_merge"}

ORCHESTRATOR_FIELDS = ["spawn_priority", "lineage_context", "ci_validation", "merge_strategy"]

VAGUE_PHRASES = [
    "should work", "properly configured", "as expected",
    "correctly handles", "appropriate", "reasonable",
]

_EVENT_PATTERN = re.compile(
    r"event:|\.created|\.updated|\.completed|\.deleted|\.failed",
    re.IGNORECASE,
)


def _ids(tasks):
    return {t["id"] for t in tasks if t.get("id")}


def _has_cycle(graph):
    """DFS cycle detection. Returns list of nodes in a cycle, or empty list."""
    WHITE, GRAY, BLACK = 0, 1, 2
    color = {n: WHITE for n in graph}
    parent = {}

    def dfs(node):
        color[node] = GRAY
        for dep in graph.get(node, []):
            if dep not in color:
                continue
            if color[dep] == GRAY:
                return [dep, node]
            if color[dep] == WHITE:
                parent[dep] = node
                cycle = dfs(dep)
                if cycle:
                    return cycle
        color[node] = BLACK
        return []

    for node in list(graph):
        if color.get(node, WHITE) == WHITE:
            cycle = dfs(node)
            if cycle:
                return cycle
    return []


def _fuzzy_match(needle, haystack_list):
    """True if needle appears as a substring in any item of haystack_list."""
    needle_lower = needle.lower().strip()
    for item in haystack_list:
        if needle_lower in item.lower().strip():
            return True
    return False


# ---------------------------------------------------------------------------
# Individual checks
# ---------------------------------------------------------------------------

def check_01_required_artifacts(catalog):
    artifacts = catalog.get("top_level_artifacts", {})
    missing = [a for a in REQUIRED_ARTIFACTS if not artifacts.get(a, False)]
    passed = len(missing) == 0
    detail = "All required artifacts present" if passed else f"Missing: {', '.join(missing)}"
    return passed, detail


def check_02_valid_frontmatter(catalog):
    tasks = catalog.get("tasks", [])
    bad = []
    for t in tasks:
        missing = [f for f in REQUIRED_FM_FIELDS if f not in t or t[f] in (None, "")]
        # depends_on can be empty list, that's fine
        missing = [f for f in missing if f != "depends_on" or "depends_on" not in t]
        if missing:
            bad.append(f"{t.get('id', t.get('file_path', '?'))}: missing {missing}")
    passed = len(bad) == 0
    detail = "All tasks have valid frontmatter" if passed else f"{len(bad)} task(s) with missing fields: {'; '.join(bad[:5])}"
    return passed, detail


def check_03_no_dangling_deps(catalog):
    tasks = catalog.get("tasks", [])
    all_ids = _ids(tasks)
    dangling = []
    for t in tasks:
        for dep in t.get("depends_on", []):
            if dep and dep not in all_ids:
                dangling.append(f"{t['id']} -> {dep}")
    passed = len(dangling) == 0
    detail = "No dangling dependencies" if passed else f"Dangling refs: {'; '.join(dangling[:10])}"
    return passed, detail


def check_04_no_circular_deps(catalog):
    graph = catalog.get("dependency_graph", {})
    cycle = _has_cycle(graph)
    passed = len(cycle) == 0
    detail = "No circular dependencies" if passed else f"Cycle detected involving: {' -> '.join(cycle)}"
    return passed, detail


def check_05_task_count_range(catalog):
    total = catalog.get("total_tasks", 0)
    passed = 40 <= total <= 55
    detail = f"Task count: {total} (expected 40-55)"
    return passed, detail


def check_06_task_sizing(catalog):
    tasks = catalog.get("tasks", [])
    out_of_range = []
    for t in tasks:
        h = t.get("estimated_hours", 0)
        if h < 3 or h > 8:
            out_of_range.append(f"{t['id']}={h}h")
    passed = len(out_of_range) == 0
    detail = "All tasks within 3-8h range" if passed else f"{len(out_of_range)} task(s) outside range: {', '.join(out_of_range[:8])}"
    return passed, detail


def check_07_directory_breadth(catalog):
    tasks = catalog.get("tasks", [])
    wide = []
    for t in tasks:
        dirs = set()
        for fp in t.get("files_touched", []):
            parts = fp.replace("\\", "/").split("/")
            if len(parts) > 1:
                dirs.add(parts[0])
        if len(dirs) > 2:
            wide.append(f"{t['id']} ({len(dirs)} dirs)")
    passed = len(wide) == 0
    detail = "All tasks touch at most 2 directories" if passed else f"{len(wide)} task(s) touch >2 dirs: {', '.join(wide[:5])}"
    return passed, detail


def check_08_no_runnable_code(_catalog):
    return True, "Requires file access -- skipped in catalog-based validation"


def check_09_blueprint_refs(catalog):
    tasks = catalog.get("tasks", [])
    missing = []
    for t in tasks:
        has_refs = bool(t.get("blueprint_refs"))
        is_inferred = (t.get("source", "") == "inferred")
        if not has_refs and not is_inferred:
            missing.append(t.get("id", "?"))
    passed = len(missing) == 0
    detail = "All tasks have blueprint_refs or are inferred" if passed else f"{len(missing)} task(s) without refs: {', '.join(missing[:8])}"
    return passed, detail


def check_10_dependency_reasons(catalog):
    tasks = catalog.get("tasks", [])
    missing = []
    for t in tasks:
        deps = t.get("depends_on", [])
        reasons = t.get("dependency_reasons", {})
        for dep in deps:
            if dep and dep not in reasons:
                missing.append(f"{t['id']}->{dep}")
    passed = len(missing) == 0
    detail = "All dependencies have reasons" if passed else f"{len(missing)} missing reason(s): {'; '.join(missing[:8])}"
    return passed, detail


def check_11_review_tiers(catalog):
    tasks = catalog.get("tasks", [])
    invalid = []
    for t in tasks:
        tier = t.get("review_tier", "")
        if tier and tier not in VALID_REVIEW_TIERS:
            invalid.append(f"{t['id']}={tier}")
    passed = len(invalid) == 0
    detail = "All review tiers valid" if passed else f"Invalid tiers: {', '.join(invalid[:8])}"
    return passed, detail


def check_12_inferred_confirmation(catalog):
    tasks = catalog.get("tasks", [])
    bad = []
    for t in tasks:
        if t.get("source", "") == "inferred":
            if not t.get("requires_human_confirmation", False):
                bad.append(t.get("id", "?"))
    passed = len(bad) == 0
    detail = "All inferred tasks require human confirmation" if passed else f"{len(bad)} inferred task(s) missing flag: {', '.join(bad[:8])}"
    return passed, detail


def check_13_workstream_density(catalog):
    ws_summary = catalog.get("workstream_summary", [])
    if len(ws_summary) < 2:
        return True, "Fewer than 2 workstreams; density check N/A"
    counts = [ws["task_count"] for ws in ws_summary if ws["task_count"] > 0]
    if not counts:
        return True, "No tasks in workstreams"
    ratio = max(counts) / min(counts)
    passed = ratio <= 3.0
    detail = f"Density ratio: {ratio:.1f}x (max/min task counts, threshold 3.0x)"
    return passed, detail


def check_14_product_context(catalog):
    tasks = catalog.get("tasks", [])
    has_desc = sum(1 for t in tasks if t.get("description_excerpt", ""))
    passed = has_desc > 0
    detail = f"{has_desc}/{len(tasks)} tasks have non-empty description_excerpt"
    return passed, detail


def check_15_orchestrator_metadata(catalog):
    tasks = catalog.get("tasks", [])
    missing_counts = defaultdict(int)
    for t in tasks:
        for field in ORCHESTRATOR_FIELDS:
            val = t.get(field, "")
            if val in (None, "", 0):
                missing_counts[field] += 1
    problems = [f"{f} missing in {c} task(s)" for f, c in missing_counts.items() if c > 0]
    passed = len(problems) == 0
    detail = "All orchestrator fields present" if passed else "; ".join(problems)
    return passed, detail


def check_16_spawn_wave_plan(catalog):
    artifacts = catalog.get("top_level_artifacts", {})
    has_dep_graph = artifacts.get("DEPENDENCY-GRAPH.md", False)
    passed = has_dep_graph
    detail = ("DEPENDENCY-GRAPH.md present (spawn wave section requires file access to verify)"
              if passed else "DEPENDENCY-GRAPH.md not found")
    return passed, detail


def check_17_error_path_ac(catalog):
    tasks = catalog.get("tasks", [])
    total = len(tasks)
    if total == 0:
        return True, "No tasks to check"
    with_error = sum(1 for t in tasks if t.get("has_error_path_ac", False))
    pct = with_error / total * 100
    passed = pct >= 70
    detail = f"{with_error}/{total} ({pct:.0f}%) tasks have error-path ACs (threshold 70%)"
    return passed, detail


def check_18_decision_cross_refs(catalog):
    tasks = catalog.get("tasks", [])
    total = len(tasks)
    if total == 0:
        return True, "No tasks to check"
    with_refs = sum(1 for t in tasks if t.get("has_decision_cross_refs", False))
    pct = with_refs / total * 100
    artifacts = catalog.get("top_level_artifacts", {})
    has_decisions = artifacts.get("DECISIONS-LOCKED.md", False)
    passed = pct >= 50
    extra = "" if has_decisions else " | DECISIONS-LOCKED.md not found"
    detail = f"{with_refs}/{total} ({pct:.0f}%) tasks have decision cross-refs (threshold 50%){extra}"
    return passed, detail


def check_19_interface_contracts(catalog):
    tasks = catalog.get("tasks", [])
    all_produced = []
    for t in tasks:
        all_produced.extend(t.get("contracts_produced", []))
    unmatched = []
    for t in tasks:
        for consumed in t.get("contracts_consumed", []):
            if not _fuzzy_match(consumed, all_produced):
                unmatched.append(f"{t['id']}: {consumed}")
    passed = len(unmatched) == 0
    detail = ("All consumed contracts have producers" if passed
              else f"{len(unmatched)} unmatched consumed contract(s): {'; '.join(unmatched[:5])}")
    return passed, detail


def check_20_event_schema_coverage(catalog):
    tasks = catalog.get("tasks", [])
    produced_events = []
    for t in tasks:
        for c in t.get("contracts_produced", []):
            if _EVENT_PATTERN.search(c):
                produced_events.append(c)
    if not produced_events:
        return True, "No event patterns found in contracts_produced"
    all_consumed = []
    for t in tasks:
        all_consumed.extend(t.get("contracts_consumed", []))
    uncovered = [e for e in produced_events if not _fuzzy_match(e, all_consumed)]
    passed = len(uncovered) == 0
    detail = ("All produced events have consumers" if passed
              else f"{len(uncovered)} event(s) without consumers: {'; '.join(uncovered[:5])}")
    return passed, detail


def check_21_health_check_presence(catalog):
    tasks = catalog.get("tasks", [])
    found = False
    for t in tasks:
        for ac in t.get("acceptance_criteria", []):
            if isinstance(ac, str):
                lower = ac.lower()
                if "health check" in lower or "/health" in lower:
                    found = True
                    break
        if found:
            break
    passed = found
    detail = "Health check / smoke test AC found" if passed else "No task mentions health check or /health in acceptance_criteria"
    return passed, detail


def check_22_migration_ordering(catalog):
    tasks = catalog.get("tasks", [])
    migration_re = re.compile(r"migration|supabase/", re.IGNORECASE)
    path_tasks = defaultdict(list)
    for t in tasks:
        for fp in t.get("files_touched", []):
            if migration_re.search(fp):
                path_tasks[fp].append(t)
    unsafe = []
    for path, touching in path_tasks.items():
        if len(touching) >= 2:
            parallel = [t for t in touching if t.get("parallel_safe", False)]
            if len(parallel) >= 2:
                ids = [t["id"] for t in parallel]
                unsafe.append(f"{path}: parallel tasks {', '.join(ids)}")
    passed = len(unsafe) == 0
    detail = ("No migration ordering conflicts" if passed
              else f"{len(unsafe)} unsafe migration overlap(s): {'; '.join(unsafe[:5])}")
    return passed, detail


def check_23_merge_hotspots(catalog):
    hotspots = catalog.get("merge_hotspots", [])
    critical = [h for h in hotspots if h.get("task_count", 0) >= 4]
    warnings = [h for h in hotspots if h.get("task_count", 0) == 3]
    if critical:
        severity_override = "blocker"
        passed = False
        detail = f"{len(critical)} critical hotspot(s) (4+ tasks): {'; '.join(h['path'] for h in critical[:5])}"
    elif warnings:
        severity_override = "warning"
        passed = False
        detail = f"{len(warnings)} hotspot(s) at 3 tasks: {'; '.join(h['path'] for h in warnings[:5])}"
    else:
        severity_override = None
        passed = True
        detail = "No merge hotspots (3+ tasks on same file)"
    return passed, detail, severity_override


def check_24_ac_testability(catalog):
    tasks = catalog.get("tasks", [])
    flagged = []
    for t in tasks:
        for ac in t.get("acceptance_criteria", []):
            if isinstance(ac, str):
                lower = ac.lower()
                for phrase in VAGUE_PHRASES:
                    if phrase in lower:
                        flagged.append(f"{t['id']}: \"{phrase}\"")
                        break
    passed = len(flagged) == 0
    detail = ("All ACs appear testable" if passed
              else f"{len(flagged)} task(s) with vague ACs: {'; '.join(flagged[:5])}")
    return passed, detail


def check_25_human_gate_justification(catalog):
    tasks = catalog.get("tasks", [])
    missing = []
    for t in tasks:
        if t.get("human_gate", False):
            reason = t.get("gate_reason", "")
            if not reason or not str(reason).strip():
                missing.append(t.get("id", "?"))
    passed = len(missing) == 0
    detail = ("All human-gated tasks have gate_reason" if passed
              else f"{len(missing)} gated task(s) without reason: {', '.join(missing[:8])}")
    return passed, detail


def check_26_contract_symmetry(catalog):
    tasks = catalog.get("tasks", [])
    all_produced = []
    for t in tasks:
        all_produced.extend(t.get("contracts_produced", []))
    all_consumed = set()
    for t in tasks:
        for c in t.get("contracts_consumed", []):
            all_consumed.add(c)
    unmatched = [c for c in all_consumed if not _fuzzy_match(c, all_produced)]
    passed = len(unmatched) == 0
    detail = ("Contract symmetry OK" if passed
              else f"{len(unmatched)} consumed contract(s) without producer: {'; '.join(unmatched[:5])}")
    return passed, detail


# ---------------------------------------------------------------------------
# Check registry
# ---------------------------------------------------------------------------

CHECKS = [
    (1,  "required_artifacts",           "blocker",  check_01_required_artifacts),
    (2,  "valid_frontmatter",            "blocker",  check_02_valid_frontmatter),
    (3,  "no_dangling_deps",             "blocker",  check_03_no_dangling_deps),
    (4,  "no_circular_deps",             "blocker",  check_04_no_circular_deps),
    (5,  "task_count_range",             "warning",  check_05_task_count_range),
    (6,  "task_sizing",                  "warning",  check_06_task_sizing),
    (7,  "directory_breadth",            "warning",  check_07_directory_breadth),
    (8,  "no_runnable_code",             "info",     check_08_no_runnable_code),
    (9,  "blueprint_refs",               "warning",  check_09_blueprint_refs),
    (10, "dependency_reasons",           "warning",  check_10_dependency_reasons),
    (11, "review_tiers_valid",           "warning",  check_11_review_tiers),
    (12, "inferred_confirmation",        "warning",  check_12_inferred_confirmation),
    (13, "workstream_density",           "warning",  check_13_workstream_density),
    (14, "product_context",              "info",     check_14_product_context),
    (15, "orchestrator_metadata",        "warning",  check_15_orchestrator_metadata),
    (16, "spawn_wave_plan",              "info",     check_16_spawn_wave_plan),
    (17, "error_path_ac_coverage",       "warning",  check_17_error_path_ac),
    (18, "decision_cross_refs",          "warning",  check_18_decision_cross_refs),
    (19, "interface_contract_completeness", "warning", check_19_interface_contracts),
    (20, "event_schema_coverage",        "warning",  check_20_event_schema_coverage),
    (21, "health_check_presence",        "info",     check_21_health_check_presence),
    (22, "migration_ordering_safety",    "blocker",  check_22_migration_ordering),
    (23, "merge_hotspot_severity",       "warning",  check_23_merge_hotspots),
    (24, "ac_testability",               "warning",  check_24_ac_testability),
    (25, "human_gate_justification",     "warning",  check_25_human_gate_justification),
    (26, "contract_symmetry",            "warning",  check_26_contract_symmetry),
]

# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------

def run_checks(catalog):
    """Execute all checks and return the results list."""
    results = []
    for num, name, severity, fn in CHECKS:
        try:
            result = fn(catalog)
            # Some checks return (passed, detail, severity_override)
            if len(result) == 3:
                passed, detail, sev_override = result
                effective_severity = sev_override if sev_override else severity
            else:
                passed, detail = result
                effective_severity = severity
        except Exception as exc:
            passed = False
            detail = f"Check error: {exc}"
            effective_severity = severity
        results.append({
            "check_number": num,
            "check_name": name,
            "severity": effective_severity,
            "passed": passed,
            "detail": detail,
        })
    return results


def build_report(catalog_path, catalog):
    """Run all checks and build the report dict."""
    results = run_checks(catalog)
    blockers_failed = sum(
        1 for r in results if not r["passed"] and r["severity"] == "blocker"
    )
    failed = sum(1 for r in results if not r["passed"])
    passed = sum(1 for r in results if r["passed"])
    gate = "BLOCKED" if blockers_failed > 0 else "PASS"

    return {
        "gate": gate,
        "plan_catalog": str(catalog_path),
        "total_checks": len(results),
        "passed": passed,
        "failed": failed,
        "blockers_failed": blockers_failed,
        "checks": results,
    }


def print_report(report):
    """Print a human-readable summary to stdout."""
    gate = report["gate"]
    marker = "PASS" if gate == "PASS" else "!! BLOCKED !!"
    print(f"{'=' * 60}")
    print(f"  Build-Plan Validation Report   [{marker}]")
    print(f"{'=' * 60}")
    print(f"  Catalog : {report['plan_catalog']}")
    print(f"  Checks  : {report['total_checks']}  |  Passed: {report['passed']}  |  Failed: {report['failed']}")
    print(f"  Blockers failed: {report['blockers_failed']}")
    print(f"{'=' * 60}")
    print()

    # Group by severity
    for sev in ("blocker", "warning", "info"):
        group = [c for c in report["checks"] if c["severity"] == sev]
        if not group:
            continue
        print(f"  [{sev.upper()}]")
        for c in group:
            icon = "PASS" if c["passed"] else "FAIL"
            print(f"    {icon}  #{c['check_number']:02d} {c['check_name']}")
            if not c["passed"] or sev == "info":
                print(f"         {c['detail']}")
        print()

    print(f"Gate: {gate}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path-to-plan-catalog.json>", file=sys.stderr)
        sys.exit(1)

    catalog_path = Path(sys.argv[1]).resolve()
    if not catalog_path.is_file():
        print(f"Error: {catalog_path} is not a file", file=sys.stderr)
        sys.exit(1)

    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))

    report = build_report(catalog_path, catalog)

    # Write report alongside catalog
    out_path = catalog_path.parent / "validation-report.json"
    out_path.write_text(json.dumps(report, indent=2), encoding="utf-8")

    print_report(report)
    print()
    print(f"Wrote {out_path}")

    if report["gate"] == "BLOCKED":
        sys.exit(1)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"Fatal error: {exc}", file=sys.stderr)
        sys.exit(1)
