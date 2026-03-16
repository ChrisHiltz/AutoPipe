#!/usr/bin/env python3
"""Catalog a build-plan directory into plan-catalog.json.

Walks a build-plan directory tree, extracts YAML frontmatter and
body-derived fields from every task file, and writes a comprehensive
plan-catalog.json alongside a human-readable stdout summary.

Usage:
    python catalog_plan.py <build-plan-dir>

Dependencies:
    pyyaml (optional -- falls back to naive key:value parsing)
"""

import re
import os
import json
import sys
from collections import defaultdict
from pathlib import Path

try:
    import yaml
except ImportError:
    print("WARNING: pyyaml not installed. Install with: pip install pyyaml", file=sys.stderr)
    yaml = None

# ---------------------------------------------------------------------------
# Parsing helpers
# ---------------------------------------------------------------------------

def parse_frontmatter(content: str) -> dict:
    """Extract YAML frontmatter from a markdown file."""
    match = re.match(r'^---\s*\n(.*?)\n---', content, re.DOTALL)
    if not match:
        return {}
    raw = match.group(1)
    if yaml:
        try:
            return yaml.safe_load(raw) or {}
        except yaml.YAMLError:
            return {}
    result = {}
    for line in raw.split('\n'):
        if ':' in line:
            key, _, val = line.partition(':')
            result[key.strip()] = val.strip()
    return result


def find_task_files(plan_dir: Path) -> list:
    """Return list of (filepath, content, frontmatter) for every .md inside a tasks dir."""
    tasks = []
    for root, _dirs, files in os.walk(plan_dir):
        root_path = Path(root)
        if root_path.name == 'tasks' or 'tasks' in root_path.parts:
            for f in files:
                if f.endswith('.md'):
                    fp = root_path / f
                    content = fp.read_text(encoding='utf-8', errors='replace')
                    fm = parse_frontmatter(content)
                    if fm:
                        tasks.append((fp, content, fm))
    return tasks


def extract_section(body: str, heading: str) -> str:
    """Return text under ``## {heading}`` up to the next ``## `` or EOF."""
    pattern = re.compile(
        r'^##\s+' + re.escape(heading) + r'\s*\n(.*?)(?=^##\s|\Z)',
        re.MULTILINE | re.DOTALL,
    )
    m = pattern.search(body)
    return m.group(1).strip() if m else ''


def _strip_frontmatter(content: str) -> str:
    """Return content after the closing ``---`` of frontmatter."""
    m = re.match(r'^---\s*\n.*?\n---\s*\n?', content, re.DOTALL)
    return content[m.end():] if m else content

# ---------------------------------------------------------------------------
# Per-task extraction
# ---------------------------------------------------------------------------

_ERROR_PATH_RE = re.compile(
    r'error|fail|timeout|rollback|denied|retry|degrad|circuit|409|503|422',
    re.IGNORECASE,
)

_DECISION_XREF_RE = re.compile(
    r'(?:DA|BL|CC|UX|AB)-\d|DECISIONS-LOCKED',
    re.IGNORECASE,
)


def _ensure_list(val):
    """Coerce a value into a list (handles None, str, list)."""
    if val is None:
        return []
    if isinstance(val, list):
        return val
    if isinstance(val, str):
        return [v.strip() for v in val.split(',') if v.strip()]
    return [val]


def _ensure_dict(val):
    if isinstance(val, dict):
        return val
    return {}


def build_task_record(fp: Path, content: str, fm: dict, plan_dir: Path) -> dict:
    """Build a single task record from frontmatter + body analysis."""
    body = _strip_frontmatter(content)

    ac = _ensure_list(fm.get('acceptance_criteria'))

    # Body-derived booleans
    has_error_path_ac = any(_ERROR_PATH_RE.search(c) for c in ac if isinstance(c, str))
    # Check both body AND acceptance criteria for decision cross-refs
    ac_text = ' '.join(str(c) for c in ac)
    has_decision_cross_refs = bool(_DECISION_XREF_RE.search(body)) or bool(_DECISION_XREF_RE.search(ac_text))

    body_lower = body.lower()
    scope_boundary_present = ('in scope' in body_lower and 'out of scope' in body_lower)

    desc_section = extract_section(body, 'Description')
    desc_excerpt = desc_section[:200].lstrip() if desc_section else ''

    iface_section = extract_section(body, 'Interface Contracts')
    iface_excerpt = iface_section[:300].lstrip() if iface_section else ''

    files_touched = _ensure_list(fm.get('files_touched'))

    return {
        'file_path': str(fp.relative_to(plan_dir)),
        'id': fm.get('id', ''),
        'title': fm.get('title', ''),
        'workstream': fm.get('workstream', ''),
        'build_block': fm.get('build_block', ''),
        'estimated_hours': _to_number(fm.get('estimated_hours', 0)),
        'depends_on': _ensure_list(fm.get('depends_on')),
        'dependency_reasons': _ensure_dict(fm.get('dependency_reasons')),
        'blocks': _ensure_list(fm.get('blocks')),
        'review_tier': fm.get('review_tier', ''),
        'human_gate': bool(fm.get('human_gate', False)),
        'gate_reason': fm.get('gate_reason', ''),
        'acceptance_criteria': ac,
        'ac_count': len(ac),
        'contracts_consumed': _ensure_list(fm.get('contracts_consumed')),
        'contracts_produced': _ensure_list(fm.get('contracts_produced')),
        'files_touched': files_touched,
        'spawn_priority': fm.get('spawn_priority', ''),
        'merge_strategy': fm.get('merge_strategy', ''),
        'ci_validation': fm.get('ci_validation', ''),
        'parallel_safe': bool(fm.get('parallel_safe', False)),
        'blueprint_refs': _ensure_list(fm.get('blueprint_refs')),
        'source': fm.get('source', ''),
        'requires_human_confirmation': bool(fm.get('requires_human_confirmation', False)),
        'lineage_context': fm.get('lineage_context', ''),
        'status': fm.get('status', ''),
        'lane': fm.get('lane', ''),
        # body-derived
        'has_error_path_ac': has_error_path_ac,
        'has_decision_cross_refs': has_decision_cross_refs,
        'scope_boundary_present': scope_boundary_present,
        'description_excerpt': desc_excerpt,
        'interface_contracts_excerpt': iface_excerpt,
    }


def _to_number(val):
    """Best-effort conversion to float, defaulting to 0."""
    try:
        return float(val)
    except (TypeError, ValueError):
        return 0

# ---------------------------------------------------------------------------
# Top-level aggregation
# ---------------------------------------------------------------------------

TOP_LEVEL_ARTIFACTS = [
    'PLAN-SUMMARY.md', 'DEPENDENCY-GRAPH.md', 'CONTRACTS.md',
    'WORKSTREAMS.md', 'HUMAN-GATES.md', 'RISKS.md',
    'PRODUCT-TRUTHS.md', 'DIRECTORY-CONTRACT.md', 'REVIEW-CHECKLIST.md',
    '.agent-rules.md', 'DECISIONS-LOCKED.md', 'TECH-DECISIONS.md',
    'SERVICE-PROVISIONING.md',
]


def _build_file_map(plan_dir: Path) -> dict:
    """Map workstream directory names to their task file listings."""
    file_map = {}
    for entry in sorted(plan_dir.iterdir()):
        if entry.is_dir():
            tasks_dir = entry / 'tasks'
            if tasks_dir.is_dir():
                task_files = sorted(f.name for f in tasks_dir.iterdir() if f.suffix == '.md')
                file_map[entry.name] = {
                    'dir_path': str(entry.relative_to(plan_dir)),
                    'task_files': task_files,
                }
    return file_map


def _compute_dag_depth(dep_graph: dict) -> int:
    """Compute the longest chain via iterative BFS/topological depth."""
    in_degree = defaultdict(int)
    all_nodes = set(dep_graph.keys())
    for deps in dep_graph.values():
        for d in deps:
            all_nodes.add(d)
    for node in all_nodes:
        if node not in dep_graph:
            dep_graph[node] = []
    # Build forward adjacency (parent -> children that depend on parent)
    children = defaultdict(list)
    for node, deps in dep_graph.items():
        for d in deps:
            children[d].append(node)
            in_degree[node] += 1

    # BFS from roots (nodes with 0 in-degree)
    queue = [n for n in all_nodes if in_degree[n] == 0]
    depth = {}
    for n in queue:
        depth[n] = 1
    while queue:
        next_queue = []
        for node in queue:
            for child in children[node]:
                new_depth = depth[node] + 1
                if new_depth > depth.get(child, 0):
                    depth[child] = new_depth
                in_degree[child] -= 1
                if in_degree[child] == 0:
                    next_queue.append(child)
        queue = next_queue

    return max(depth.values()) if depth else 0


def _compute_merge_hotspots(task_records: list) -> list:
    """Find files touched by 3+ tasks."""
    path_tasks = defaultdict(set)
    for t in task_records:
        for fp in t['files_touched']:
            path_tasks[fp].add(t['id'])
    hotspots = []
    for path, ids in sorted(path_tasks.items()):
        count = len(ids)
        if count >= 3:
            hotspots.append({
                'path': path,
                'task_count': count,
                'severity': 'critical' if count >= 4 else 'warning',
            })
    return sorted(hotspots, key=lambda h: -h['task_count'])


def build_catalog(plan_dir: Path) -> dict:
    """Build the full plan catalog dict."""
    plan_dir = plan_dir.resolve()

    raw_tasks = find_task_files(plan_dir)
    task_records = [build_task_record(fp, content, fm, plan_dir)
                    for fp, content, fm in raw_tasks]

    # Top-level artifacts
    top_level = {name: (plan_dir / name).exists() for name in TOP_LEVEL_ARTIFACTS}

    # Workstream summary
    ws_data = defaultdict(lambda: {'blocks': set(), 'count': 0, 'hours': 0.0})
    for t in task_records:
        ws = t['workstream'] or '_unknown'
        ws_data[ws]['count'] += 1
        ws_data[ws]['hours'] += t['estimated_hours']
        if t['build_block']:
            ws_data[ws]['blocks'].add(t['build_block'])

    workstream_summary = sorted([
        {
            'name': ws,
            'block_count': len(d['blocks']),
            'task_count': d['count'],
            'total_hours': d['hours'],
        }
        for ws, d in ws_data.items()
    ], key=lambda w: w['name'])

    # Dependency graph + DAG depth
    dep_graph = {t['id']: t['depends_on'] for t in task_records if t['id']}
    dag_depth = _compute_dag_depth(dict(dep_graph))

    # Human-gated tasks
    human_gated = [t['id'] for t in task_records if t['human_gate'] and t['id']]

    # Merge hotspots
    merge_hotspots = _compute_merge_hotspots(task_records)

    return {
        'plan_dir': str(plan_dir),
        'file_map': _build_file_map(plan_dir),
        'top_level_artifacts': top_level,
        'total_tasks': len(task_records),
        'total_hours': round(sum(t['estimated_hours'] for t in task_records), 2),
        'workstream_summary': workstream_summary,
        'dependency_graph': dep_graph,
        'dag_depth': dag_depth,
        'human_gated_tasks': human_gated,
        'merge_hotspots': merge_hotspots,
        'tasks': task_records,
    }

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

def print_summary(catalog: dict) -> None:
    """Print a concise human-readable summary to stdout."""
    print(f"Plan directory : {catalog['plan_dir']}")
    print(f"Total tasks    : {catalog['total_tasks']}")
    print(f"Total hours    : {catalog['total_hours']}")
    print(f"DAG depth      : {catalog['dag_depth']}")
    print(f"Human gates    : {len(catalog['human_gated_tasks'])}")
    print(f"Merge hotspots : {len(catalog['merge_hotspots'])}")
    print()

    artifacts_present = [k for k, v in catalog['top_level_artifacts'].items() if v]
    artifacts_missing = [k for k, v in catalog['top_level_artifacts'].items() if not v]
    print(f"Artifacts present ({len(artifacts_present)}): {', '.join(artifacts_present) or '(none)'}")
    print(f"Artifacts missing ({len(artifacts_missing)}): {', '.join(artifacts_missing) or '(none)'}")
    print()

    print("Workstream summary:")
    for ws in catalog['workstream_summary']:
        print(f"  {ws['name']:30s}  blocks={ws['block_count']}  tasks={ws['task_count']}  hours={ws['total_hours']}")
    print()

    if catalog['merge_hotspots']:
        print("Merge hotspots:")
        for h in catalog['merge_hotspots']:
            print(f"  [{h['severity'].upper():8s}] {h['path']}  ({h['task_count']} tasks)")
        print()

    if catalog['human_gated_tasks']:
        print(f"Human-gated tasks: {', '.join(catalog['human_gated_tasks'])}")
        print()


def main() -> None:
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <build-plan-dir>", file=sys.stderr)
        sys.exit(1)

    plan_dir = Path(sys.argv[1])
    if not plan_dir.is_dir():
        print(f"Error: {plan_dir} is not a directory", file=sys.stderr)
        sys.exit(1)

    catalog = build_catalog(plan_dir)

    out_path = plan_dir / 'plan-catalog.json'
    out_path.write_text(json.dumps(catalog, indent=2, default=str), encoding='utf-8')

    print_summary(catalog)
    print(f"Wrote {out_path}")


if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        print(f"Fatal error: {exc}", file=sys.stderr)
        sys.exit(1)
