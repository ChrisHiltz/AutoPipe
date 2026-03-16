#!/usr/bin/env python3
"""Compare before/after plan-catalog.json snapshots to generate a fix changelog.

Usage:
    python track_fixes.py --before plan-catalog-before.json --after plan-catalog.json \
        --pass-number 1 [--checklist REVIEW-CHECKLIST.md]
"""

import argparse
import json
import sys
from datetime import datetime, timezone


def load_catalog(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def safe_get(d, key, default=None):
    """Get a value from a dict, defaulting gracefully for missing/None."""
    if default is None:
        if key in ("depends_on", "acceptance_criteria", "files_touched",
                    "top_level_artifacts", "merge_hotspots"):
            default = []
        elif key in ("estimated_hours", "total_hours", "total_tasks"):
            default = 0
        elif key in ("has_error_path_ac", "has_decision_cross_refs",
                      "scope_boundary_present", "human_gate"):
            default = False
        else:
            default = None
    return d.get(key, default) if d.get(key) is not None else default


def compare_tasks(before_tasks, after_tasks):
    """Compare task-level changes between two catalog snapshots."""
    before_ids = {t["task_id"]: t for t in before_tasks}
    after_ids = {t["task_id"]: t for t in after_tasks}

    added = [after_ids[tid] for tid in after_ids if tid not in before_ids]
    removed = [before_ids[tid] for tid in before_ids if tid not in after_ids]
    common_ids = set(before_ids) & set(after_ids)

    modified = []
    total_acs_added = 0

    for tid in sorted(common_ids):
        b = before_ids[tid]
        a = after_ids[tid]
        changes = []

        # acceptance_criteria count
        b_ac = len(safe_get(b, "acceptance_criteria", []))
        a_ac = len(safe_get(a, "acceptance_criteria", []))
        if a_ac != b_ac:
            diff = a_ac - b_ac
            total_acs_added += max(diff, 0)
            changes.append(f"{'Added' if diff > 0 else 'Removed'} {abs(diff)} acceptance criteria")

        # depends_on
        b_deps = set(safe_get(b, "depends_on", []))
        a_deps = set(safe_get(a, "depends_on", []))
        added_deps = sorted(a_deps - b_deps)
        removed_deps = sorted(b_deps - a_deps)
        if added_deps or removed_deps:
            parts = []
            if added_deps:
                parts.append(f"added [{', '.join(added_deps)}]")
            if removed_deps:
                parts.append(f"removed [{', '.join(removed_deps)}]")
            changes.append(f"Changed dependencies: {', '.join(parts)}")

        # human_gate
        b_hg = safe_get(b, "human_gate", False)
        a_hg = safe_get(a, "human_gate", False)
        if b_hg != a_hg:
            changes.append(f"human_gate flipped: {b_hg} -> {a_hg}")

        # estimated_hours
        b_eh = safe_get(b, "estimated_hours", 0)
        a_eh = safe_get(a, "estimated_hours", 0)
        if b_eh != a_eh:
            changes.append(f"estimated_hours changed: {b_eh} -> {a_eh}")

        # files_touched
        b_ft = set(safe_get(b, "files_touched", []))
        a_ft = set(safe_get(a, "files_touched", []))
        if b_ft != a_ft:
            added_f = sorted(a_ft - b_ft)
            removed_f = sorted(b_ft - a_ft)
            parts = []
            if added_f:
                parts.append(f"+{len(added_f)} files")
            if removed_f:
                parts.append(f"-{len(removed_f)} files")
            changes.append(f"files_touched changed: {', '.join(parts)}")

        # Body-derived boolean fields
        for field, label in [
            ("has_error_path_ac", "error-path ACs"),
            ("has_decision_cross_refs", "decision cross-references"),
            ("scope_boundary_present", "scope boundary"),
        ]:
            b_val = safe_get(b, field, False)
            a_val = safe_get(a, field, False)
            if b_val != a_val:
                verb = "Added" if a_val else "Removed"
                changes.append(f"{verb} {label} (was: {b_val}, now: {a_val})")

        if changes:
            modified.append({
                "task_id": tid,
                "title": a.get("title", ""),
                "changes": changes,
            })

    return added, removed, modified, total_acs_added


def compute_coverage(tasks, field):
    """Return percentage of tasks where a boolean field is true."""
    if not tasks:
        return 0.0
    count = sum(1 for t in tasks if safe_get(t, field, False))
    return round(count / len(tasks) * 100, 1)


def compare_top_level(before, after):
    """Compare top-level catalog fields."""
    changes = []

    b_total = safe_get(before, "total_tasks", 0)
    a_total = safe_get(after, "total_tasks", 0)
    if b_total != a_total:
        changes.append(f"total_tasks: {b_total} -> {a_total} ({a_total - b_total:+d})")

    b_hours = safe_get(before, "total_hours", 0)
    a_hours = safe_get(after, "total_hours", 0)
    if b_hours != a_hours:
        changes.append(f"total_hours: {b_hours} -> {a_hours} ({a_hours - b_hours:+.1f})")

    b_arts = set(safe_get(before, "top_level_artifacts", []))
    a_arts = set(safe_get(after, "top_level_artifacts", []))
    new_arts = sorted(a_arts - b_arts)
    if new_arts:
        changes.append(f"New artifacts: {', '.join(new_arts)}")

    b_hs = set(safe_get(before, "merge_hotspots", []))
    a_hs = set(safe_get(after, "merge_hotspots", []))
    if b_hs != a_hs:
        added_hs = sorted(a_hs - b_hs)
        removed_hs = sorted(b_hs - a_hs)
        parts = []
        if added_hs:
            parts.append(f"added [{', '.join(added_hs)}]")
        if removed_hs:
            parts.append(f"removed [{', '.join(removed_hs)}]")
        changes.append(f"Merge hotspot changes: {', '.join(parts)}")

    return changes


def generate_changelog(pass_num, added, removed, modified, total_acs_added,
                       top_changes, before_tasks, after_tasks):
    """Build the markdown changelog string."""
    b_err = compute_coverage(before_tasks, "has_error_path_ac")
    a_err = compute_coverage(after_tasks, "has_error_path_ac")
    tasks_with_new_acs = sum(
        1 for m in modified if any("acceptance criteria" in c for c in m["changes"])
    )

    lines = [f"# Fix Pass {pass_num} Changelog", ""]
    lines += ["## Summary"]
    lines.append(f"- Tasks modified: {len(modified)}")
    lines.append(f"- Tasks added: {len(added)}")
    lines.append(f"- Tasks removed: {len(removed)}")
    lines.append(f"- ACs added: {total_acs_added} total across {tasks_with_new_acs} tasks")
    lines.append(f"- Error-path coverage: {b_err}% -> {a_err}% ({a_err - b_err:+.1f}%)")
    lines.append("")

    if modified:
        lines.append("## Tasks Modified")
        for m in modified:
            lines.append(f"### {m['task_id']} \u2014 {m['title']}")
            for c in m["changes"]:
                lines.append(f"- {c}")
            lines.append("")

    if added:
        lines.append("## Tasks Added")
        for t in added:
            lines.append(f"### {t['task_id']} \u2014 {t.get('title', '')}")
            ws = t.get("workstream", "unknown")
            lines.append(f"- New task in {ws}")
            lines.append("")

    if removed:
        lines.append("## Tasks Removed")
        for t in removed:
            lines.append(f"### {t['task_id']} \u2014 {t.get('title', '')}")
            lines.append("")

    if top_changes:
        lines.append("## Top-Level Changes")
        for c in top_changes:
            lines.append(f"- {c}")
        lines.append("")

    return "\n".join(lines)


def append_to_checklist(checklist_path, pass_num, modified, total_acs_added,
                        before_tasks, after_tasks):
    """Append a remediation summary section to the checklist file."""
    b_err = compute_coverage(before_tasks, "has_error_path_ac")
    a_err = compute_coverage(after_tasks, "has_error_path_ac")
    b_xref = compute_coverage(before_tasks, "has_decision_cross_refs")
    a_xref = compute_coverage(after_tasks, "has_decision_cross_refs")

    key_changes = []
    for m in modified[:5]:
        key_changes.append(f"{m['task_id']}: {'; '.join(m['changes'][:2])}")

    import os
    if not os.path.exists(checklist_path):
        with open(checklist_path, "w", encoding="utf-8") as f:
            f.write("# Review Checklist\n\n")

    now = datetime.now(timezone.utc).isoformat()
    section = [
        "",
        f"## Fix Pass {pass_num} \u2014 Remediation Summary",
        f"- **Date:** {now}",
        f"- **Tasks modified:** {len(modified)}",
        f"- **ACs added:** {total_acs_added}",
        f"- **Error-path coverage:** {b_err}% -> {a_err}%",
        f"- **Decision cross-ref coverage:** {b_xref}% -> {a_xref}%",
        "- **Key changes:**",
    ]
    for kc in key_changes:
        section.append(f"  - {kc}")
    section.append("")

    with open(checklist_path, "a", encoding="utf-8") as f:
        f.write("\n".join(section))


def main():
    parser = argparse.ArgumentParser(description="Track fixes between plan-catalog snapshots")
    parser.add_argument("--before", required=True, help="Path to before catalog JSON")
    parser.add_argument("--after", required=True, help="Path to after catalog JSON")
    parser.add_argument("--pass-number", type=int, required=True, help="Fix pass number")
    parser.add_argument("--checklist", default=None, help="Path to checklist markdown to append summary")
    args = parser.parse_args()

    try:
        before = load_catalog(args.before)
        after = load_catalog(args.after)
    except (FileNotFoundError, json.JSONDecodeError) as e:
        print(f"Error loading catalogs: {e}", file=sys.stderr)
        sys.exit(1)

    before_tasks = before.get("tasks", [])
    after_tasks = after.get("tasks", [])

    added, removed, modified, total_acs_added = compare_tasks(before_tasks, after_tasks)
    top_changes = compare_top_level(before, after)

    if not added and not removed and not modified and not top_changes:
        print("No changes detected")
        changelog = f"# Fix Pass {args.pass_number} Changelog\n\nNo changes detected.\n"
    else:
        changelog = generate_changelog(
            args.pass_number, added, removed, modified, total_acs_added,
            top_changes, before_tasks, after_tasks,
        )

    out_path = f"fix-pass-{args.pass_number}-changelog.md"
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(changelog)
    print(f"Wrote {out_path}")

    if args.checklist:
        append_to_checklist(
            args.checklist, args.pass_number, modified, total_acs_added,
            before_tasks, after_tasks,
        )
        print(f"Appended summary to {args.checklist}")

    # Print summary to stdout
    print(f"\n--- Fix Pass {args.pass_number} Summary ---")
    print(f"Tasks modified: {len(modified)}")
    print(f"Tasks added:    {len(added)}")
    print(f"Tasks removed:  {len(removed)}")
    print(f"ACs added:      {total_acs_added}")
    b_err = compute_coverage(before_tasks, "has_error_path_ac")
    a_err = compute_coverage(after_tasks, "has_error_path_ac")
    print(f"Error-path:     {b_err}% -> {a_err}%")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"Fatal error: {e}", file=sys.stderr)
        sys.exit(1)
