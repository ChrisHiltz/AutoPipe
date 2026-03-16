#!/usr/bin/env python3
"""Validate a build plan directory against skill constraints.

Usage:
    python validate_plan.py <build-plan-dir>

Checks:
    1. Required artifacts exist
    2. Task files have valid YAML frontmatter with all required fields
    3. No dangling dependency references
    4. No circular dependencies
    5. Task count within 30-60 range
    6. Task sizing within 2-8 hours
    7. Tasks touch at most 2 directories
    8. No runnable code in task bodies
    9. Every task has blueprint_refs (or is marked inferred)
    10. Every depends_on has a dependency_reason
    11. Review tiers are valid
    12. Inferred tasks have requires_human_confirmation
    13. Task density variance across workstreams
    14. Product context section present in every task

Outputs a JSON report and prints a summary with pass/fail per check.
Exit code 0 = all checks pass, 1 = failures found.
"""

import json
import os
import re
import sys
from collections import defaultdict
from pathlib import Path

try:
    import yaml
except ImportError:
    print("WARNING: pyyaml not installed. Install with: pip install pyyaml")
    print("Falling back to basic YAML parsing (may miss edge cases).")
    yaml = None


def parse_frontmatter(content: str) -> dict:
    """Extract YAML frontmatter from markdown content."""
    match = re.match(r'^---\s*\n(.*?)\n---', content, re.DOTALL)
    if not match:
        return {}
    raw = match.group(1)
    if yaml:
        try:
            return yaml.safe_load(raw) or {}
        except yaml.YAMLError:
            return {}
    # Fallback: basic key-value parsing
    result = {}
    for line in raw.split('\n'):
        if ':' in line:
            key, _, val = line.partition(':')
            result[key.strip()] = val.strip()
    return result


def find_task_files(plan_dir: Path) -> list[tuple[Path, str, dict]]:
    """Find all task files (files inside tasks/ directories)."""
    tasks = []
    for root, dirs, files in os.walk(plan_dir):
        root_path = Path(root)
        # Only look at files inside tasks/ directories
        if root_path.name == 'tasks' or 'tasks' in root_path.parts:
            for f in files:
                if f.endswith('.md'):
                    fp = root_path / f
                    content = fp.read_text(encoding='utf-8', errors='replace')
                    fm = parse_frontmatter(content)
                    if fm:
                        tasks.append((fp, content, fm))
    return tasks


def check_required_artifacts(plan_dir: Path) -> list[dict]:
    """Check 1: Required top-level artifacts exist."""
    required = [
        'PRODUCT-TRUTHS.md',
        'DIRECTORY-CONTRACT.md',
        'WORKSTREAMS.md',
        'DEPENDENCY-GRAPH.md',
        'CONTRACTS.md',
        'HUMAN-GATES.md',
        'RISKS.md',
        'PLAN-SUMMARY.md',
        'REVIEW-CHECKLIST.md',
    ]
    results = []
    for artifact in required:
        exists = (plan_dir / artifact).exists()
        results.append({
            "check": f"artifact_exists:{artifact}",
            "passed": exists,
            "detail": f"{'Found' if exists else 'MISSING'}: {artifact}"
        })
    return results


def check_required_fields(tasks: list) -> list[dict]:
    """Check 2: All required YAML fields present."""
    required_fields = [
        'id', 'title', 'workstream', 'build_block', 'status', 'lane',
        'depends_on', 'estimated_hours', 'human_gate', 'review_tier',
        'blueprint_refs', 'files_touched', 'acceptance_criteria'
    ]
    results = []
    for fp, content, fm in tasks:
        missing = [f for f in required_fields if f not in fm]
        results.append({
            "check": f"required_fields:{fp.name}",
            "passed": len(missing) == 0,
            "detail": f"Missing: {missing}" if missing else "All required fields present"
        })
    return results


def check_dangling_deps(tasks: list) -> list[dict]:
    """Check 3: No dangling dependency references."""
    all_ids = {fm.get('id') for _, _, fm in tasks if fm.get('id')}
    results = []
    for fp, content, fm in tasks:
        deps = fm.get('depends_on', [])
        if not isinstance(deps, list):
            deps = [deps]
        dangling = [d for d in deps if d and d not in all_ids]
        results.append({
            "check": f"dangling_deps:{fm.get('id', fp.name)}",
            "passed": len(dangling) == 0,
            "detail": f"Dangling: {dangling}" if dangling else "No dangling deps"
        })
    return results


def check_circular_deps(tasks: list) -> list[dict]:
    """Check 4: No circular dependencies in the DAG."""
    graph = {}
    for fp, content, fm in tasks:
        task_id = fm.get('id')
        deps = fm.get('depends_on', [])
        if not isinstance(deps, list):
            deps = [deps]
        graph[task_id] = [d for d in deps if d]

    # DFS cycle detection
    visited = set()
    rec_stack = set()
    cycles = []

    def dfs(node, path):
        visited.add(node)
        rec_stack.add(node)
        for neighbor in graph.get(node, []):
            if neighbor not in visited:
                dfs(neighbor, path + [neighbor])
            elif neighbor in rec_stack:
                cycles.append(path + [neighbor])
        rec_stack.discard(node)

    for node in graph:
        if node not in visited:
            dfs(node, [node])

    return [{
        "check": "circular_dependencies",
        "passed": len(cycles) == 0,
        "detail": f"Cycles found: {cycles[:3]}" if cycles else "No circular dependencies"
    }]


def check_task_count(tasks: list) -> list[dict]:
    """Check 5: Total task count within 30-60."""
    count = len(tasks)
    return [{
        "check": "task_count",
        "passed": 30 <= count <= 60,
        "detail": f"Task count: {count} (target: 30-60)"
    }]


def check_sizing(tasks: list) -> list[dict]:
    """Check 6: Every task estimated 2-8 hours."""
    results = []
    for fp, content, fm in tasks:
        hours = fm.get('estimated_hours')
        if hours is not None:
            try:
                h = int(hours)
                ok = 2 <= h <= 8
                results.append({
                    "check": f"sizing:{fm.get('id', fp.name)}",
                    "passed": ok,
                    "detail": f"{h}h {'OK' if ok else 'OUT OF RANGE (2-8h)'}"
                })
            except (ValueError, TypeError):
                results.append({
                    "check": f"sizing:{fm.get('id', fp.name)}",
                    "passed": False,
                    "detail": f"Non-integer hours: {hours}"
                })
    return results


def check_directory_limit(tasks: list) -> list[dict]:
    """Check 7: Each task touches at most 2 directories."""
    results = []
    for fp, content, fm in tasks:
        ft = fm.get('files_touched', [])
        if isinstance(ft, list) and len(ft) > 2:
            results.append({
                "check": f"dir_limit:{fm.get('id', fp.name)}",
                "passed": False,
                "detail": f"Touches {len(ft)} dirs: {ft}"
            })
    # If no violations, add a single pass
    if not results:
        results.append({
            "check": "dir_limit",
            "passed": True,
            "detail": "All tasks within 2-directory limit"
        })
    return results


def check_no_code(tasks: list) -> list[dict]:
    """Check 8: No runnable code in task bodies."""
    code_patterns = [
        (r'```(?:python|py)\n.*?(?:def |class |import )', 'Python code'),
        (r'```(?:typescript|ts|javascript|js)\n.*?(?:function |const |export )', 'JS/TS code'),
        (r'```sql\n.*?(?:SELECT |INSERT |CREATE TABLE|ALTER TABLE|DROP )', 'SQL code'),
        (r'```(?:jsx|tsx)\n.*?(?:return \(|<[A-Z])', 'React JSX/TSX'),
    ]
    results = []
    for fp, content, fm in tasks:
        # Get body after frontmatter
        body = content.split('---', 2)[-1] if '---' in content else content
        violations = []
        for pattern, label in code_patterns:
            if re.search(pattern, body, re.DOTALL | re.IGNORECASE):
                violations.append(label)
        if violations:
            results.append({
                "check": f"no_code:{fm.get('id', fp.name)}",
                "passed": False,
                "detail": f"Contains: {violations}"
            })
    if not results:
        results.append({
            "check": "no_code",
            "passed": True,
            "detail": "No runnable code found in any task"
        })
    return results


def check_blueprint_refs(tasks: list) -> list[dict]:
    """Check 9: Every task has blueprint_refs or is marked inferred."""
    results = []
    for fp, content, fm in tasks:
        refs = fm.get('blueprint_refs', [])
        source = fm.get('source', 'blueprint')
        has_refs = isinstance(refs, list) and len(refs) > 0
        is_inferred = source == 'inferred'
        ok = has_refs or is_inferred
        results.append({
            "check": f"blueprint_refs:{fm.get('id', fp.name)}",
            "passed": ok,
            "detail": f"{'Has refs' if has_refs else 'Inferred' if is_inferred else 'MISSING refs and not marked inferred'}"
        })
    return results


def check_dependency_reasons(tasks: list) -> list[dict]:
    """Check 10: Every depends_on has a dependency_reason."""
    results = []
    for fp, content, fm in tasks:
        deps = fm.get('depends_on', [])
        if not isinstance(deps, list):
            deps = [deps]
        deps = [d for d in deps if d]
        if not deps:
            continue
        reasons = fm.get('dependency_reasons', {})
        if not isinstance(reasons, dict):
            reasons = {}
        missing = [d for d in deps if str(d) not in reasons and d not in reasons]
        results.append({
            "check": f"dep_reasons:{fm.get('id', fp.name)}",
            "passed": len(missing) == 0,
            "detail": f"Missing reasons for: {missing}" if missing else "All deps have reasons"
        })
    return results


def check_review_tiers(tasks: list) -> list[dict]:
    """Check 11: Review tiers are valid."""
    valid_tiers = {'must_review', 'review_by_summary', 'auto_merge'}
    results = []
    for fp, content, fm in tasks:
        tier = fm.get('review_tier', '')
        ok = tier in valid_tiers
        if not ok:
            results.append({
                "check": f"review_tier:{fm.get('id', fp.name)}",
                "passed": False,
                "detail": f"Invalid tier: '{tier}' (must be one of {valid_tiers})"
            })
    if not any(not r['passed'] for r in results):
        results.append({
            "check": "review_tiers",
            "passed": True,
            "detail": "All review tiers valid"
        })
    return results


def check_inferred_confirmation(tasks: list) -> list[dict]:
    """Check 12: Inferred tasks have requires_human_confirmation."""
    results = []
    for fp, content, fm in tasks:
        source = fm.get('source', 'blueprint')
        if source == 'inferred':
            confirmed = fm.get('requires_human_confirmation', False)
            results.append({
                "check": f"inferred_confirm:{fm.get('id', fp.name)}",
                "passed": confirmed is True,
                "detail": f"Inferred task {'has' if confirmed else 'MISSING'} requires_human_confirmation"
            })
    if not results:
        results.append({
            "check": "inferred_confirmation",
            "passed": True,
            "detail": "No inferred tasks (or all properly confirmed)"
        })
    return results


def check_density_variance(tasks: list) -> list[dict]:
    """Check 13: Task density across workstreams."""
    ws_counts = defaultdict(int)
    for fp, content, fm in tasks:
        ws = fm.get('workstream', 'unknown')
        ws_counts[ws] += 1

    if len(ws_counts) < 2:
        return [{"check": "density", "passed": True, "detail": "Too few workstreams to check"}]

    counts = list(ws_counts.values())
    max_c = max(counts)
    min_c = min(counts)
    ratio = max_c / min_c if min_c > 0 else float('inf')
    ok = ratio <= 3.0  # Max workstream can have at most 3x the tasks of min

    return [{
        "check": "density_variance",
        "passed": ok,
        "detail": f"Ratio: {ratio:.1f}x (max 3.0x). Counts: {dict(ws_counts)}"
    }]


def check_product_context(tasks: list) -> list[dict]:
    """Check 14: Product context section present in every task."""
    results = []
    missing = []
    for fp, content, fm in tasks:
        body = content.split('---', 2)[-1] if '---' in content else content
        has_context = 'product context' in body.lower() or 'product truths' in body.lower()
        if not has_context:
            missing.append(fm.get('id', fp.name))

    return [{
        "check": "product_context",
        "passed": len(missing) == 0,
        "detail": f"{len(missing)} tasks missing product context: {missing[:5]}" if missing
                  else f"All {len(tasks)} tasks have product context"
    }]


def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <build-plan-dir>")
        sys.exit(1)

    plan_dir = Path(sys.argv[1])
    if not plan_dir.is_dir():
        print(f"ERROR: {plan_dir} is not a directory")
        sys.exit(1)

    tasks = find_task_files(plan_dir)

    all_results = []
    checks = [
        ("Required Artifacts", check_required_artifacts, plan_dir),
        ("Required Fields", check_required_fields, tasks),
        ("Dangling Dependencies", check_dangling_deps, tasks),
        ("Circular Dependencies", check_circular_deps, tasks),
        ("Task Count (30-60)", check_task_count, tasks),
        ("Sizing (2-8h)", check_sizing, tasks),
        ("Directory Limit (max 2)", check_directory_limit, tasks),
        ("No Code in Tasks", check_no_code, tasks),
        ("Blueprint References", check_blueprint_refs, tasks),
        ("Dependency Reasons", check_dependency_reasons, tasks),
        ("Review Tiers", check_review_tiers, tasks),
        ("Inferred Task Confirmation", check_inferred_confirmation, tasks),
        ("Density Variance", check_density_variance, tasks),
        ("Product Context", check_product_context, tasks),
    ]

    print(f"\nValidating build plan at: {plan_dir}")
    print(f"Found {len(tasks)} task files in tasks/ directories\n")
    print("=" * 60)

    total_checks = 0
    total_passed = 0
    category_results = {}

    for name, check_fn, arg in checks:
        results = check_fn(arg)
        all_results.extend(results)

        passed = sum(1 for r in results if r['passed'])
        failed = sum(1 for r in results if not r['passed'])
        total_checks += len(results)
        total_passed += passed

        status = "PASS" if failed == 0 else "FAIL"
        print(f"  [{status}] {name}: {passed}/{len(results)}")

        # Show failures
        for r in results:
            if not r['passed']:
                print(f"         {r['detail']}")

        category_results[name] = {
            "passed": passed,
            "failed": failed,
            "total": len(results),
            "details": results
        }

    print("=" * 60)
    score = total_passed / total_checks if total_checks > 0 else 0
    print(f"\nSCORE: {total_passed}/{total_checks} ({score:.0%})")

    # Save report
    report = {
        "plan_dir": str(plan_dir),
        "task_count": len(tasks),
        "score": score,
        "passed": total_passed,
        "total": total_checks,
        "categories": category_results,
        "all_results": all_results
    }

    report_path = plan_dir / 'validation-report.json'
    with open(report_path, 'w', encoding='utf-8') as f:
        json.dump(report, f, indent=2, default=str)
    print(f"\nFull report saved to: {report_path}")

    sys.exit(0 if total_passed == total_checks else 1)


if __name__ == '__main__':
    main()
