#!/usr/bin/env python3
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import re
import subprocess
from pathlib import Path, PurePosixPath
from typing import Any, Mapping


ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = ROOT / ".product-truth" / "historical-task-candidates.json"
MANIFEST_PROTOCOL = "docatlas-source-history-candidates-v1"
REPORT_PROTOCOL = "docatlas-source-history-audit-v1"
EXPECTED_REPOSITORY = "Vanilla1999/smart_glass"
EXPECTED_VISIBILITY = "public"
TASK_PREFIX = "smart-glass-hf-"
SHA_RE = re.compile(r"[0-9a-f]{40}")
ABSOLUTE_PATH_RE = re.compile(
    r"(?:^|[\s'\"])(?:/tmp/|/home/|/Users/|[A-Za-z]:\\Users\\)",
)
CODE_SUFFIXES = {
    ".py", ".dart", ".ts", ".tsx", ".js", ".jsx", ".java", ".kt",
    ".kts", ".go", ".rs", ".c", ".cc", ".cpp", ".h", ".hpp",
}
FORBIDDEN_REPORT_KEYS = {
    "raw_patch", "patch", "diff", "commit_message", "prompt", "gold_patch",
    "hidden_test_content", "environment", "credentials", "token",
}


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def load_json(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError(f"expected JSON object: {path}")
    return payload


def git(*args: str, text: bool = True, check: bool = True):
    completed = subprocess.run(
        ["git", *args],
        cwd=ROOT,
        text=text,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if check and completed.returncode != 0:
        stderr = completed.stderr if text else completed.stderr.decode("utf-8", "replace")
        raise ValueError(f"git {' '.join(args)} failed: {stderr.strip()[:300]}")
    return completed.stdout


def validate_manifest(manifest: Mapping[str, Any]) -> None:
    if manifest.get("schema_version") != 1 or manifest.get("protocol") != MANIFEST_PROTOCOL:
        raise ValueError("source history manifest identity mismatch")
    if manifest.get("repository") != EXPECTED_REPOSITORY:
        raise ValueError("source history repository identity mismatch")
    if manifest.get("visibility") != EXPECTED_VISIBILITY:
        raise ValueError("source history visibility mismatch")
    frozen = str(manifest.get("frozen_inventory_head") or "")
    if SHA_RE.fullmatch(frozen) is None:
        raise ValueError("source history frozen head is not a full SHA")
    tasks = manifest.get("tasks")
    if not isinstance(tasks, list) or len(tasks) != 8:
        raise ValueError("source history manifest requires exactly eight tasks")
    seen_ids: set[str] = set()
    seen_commits: set[str] = set()
    for index, task in enumerate(tasks, start=1):
        if not isinstance(task, Mapping) or set(task) != {"id", "fix_commit"}:
            raise ValueError("source history task exceeds the manifest allowlist")
        task_id = str(task.get("id") or "")
        if task_id != f"{TASK_PREFIX}{index:03d}":
            raise ValueError("source history task identity/order mismatch")
        fix_commit = str(task.get("fix_commit") or "")
        if SHA_RE.fullmatch(fix_commit) is None:
            raise ValueError("source history fix commit is not a full SHA")
        if task_id in seen_ids or fix_commit in seen_commits:
            raise ValueError("source history task identity is duplicated")
        seen_ids.add(task_id)
        seen_commits.add(fix_commit)
    expected_boundary = {
        "history_audit_only": True,
        "gold_control_executed": False,
        "real_model_oracle_executed": False,
        "valid_tasks": 0,
        "product_truth_proven": False,
        "product_maturity": "Beta",
    }
    if manifest.get("claim_boundary") != expected_boundary:
        raise ValueError("source history manifest claim boundary drift")
    if ABSOLUTE_PATH_RE.search(canonical_json(manifest)):
        raise ValueError("source history manifest contains an absolute path")


def is_test_path(path: str) -> bool:
    pure = PurePosixPath(path)
    lowered_parts = {part.casefold() for part in pure.parts}
    name = pure.name.casefold()
    return bool(
        lowered_parts.intersection({"test", "tests", "integration_test", "e2e"})
        or name.startswith("test_")
        or "_test." in name
        or ".test." in name
        or ".spec." in name
    )


def is_production_path(path: str) -> bool:
    pure = PurePosixPath(path)
    if pure.suffix.casefold() not in CODE_SUFFIXES or is_test_path(path):
        return False
    lowered_parts = {part.casefold() for part in pure.parts}
    return not lowered_parts.intersection({"docs", ".github", "examples", "fixtures"})


def _single_parent(commit: str) -> str:
    row = str(git("rev-list", "--parents", "-n", "1", commit)).strip().split()
    if len(row) != 2:
        raise ValueError(f"historical fix is not single-parent: {commit}")
    return row[1]


def _changed_files(parent: str, commit: str) -> list[str]:
    return sorted(
        line.strip()
        for line in str(git("diff", "--name-only", parent, commit, "--")).splitlines()
        if line.strip()
    )


def _diff_stats(parent: str, commit: str) -> tuple[int, int, int]:
    additions = 0
    deletions = 0
    files = 0
    for line in str(git("diff", "--numstat", parent, commit, "--")).splitlines():
        parts = line.split("\t", 2)
        if len(parts) != 3:
            continue
        files += 1
        if parts[0].isdigit():
            additions += int(parts[0])
        if parts[1].isdigit():
            deletions += int(parts[1])
    return files, additions, deletions


def audit_task(task: Mapping[str, Any], *, frozen_head: str) -> dict[str, Any]:
    task_id = str(task["id"])
    fix_commit = str(task["fix_commit"])
    git("cat-file", "-e", f"{fix_commit}^{{commit}}")
    ancestor = subprocess.run(
        ["git", "merge-base", "--is-ancestor", fix_commit, frozen_head],
        cwd=ROOT,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    ).returncode == 0
    if not ancestor:
        raise ValueError(f"historical fix is not reachable from frozen head: {task_id}")
    parent = _single_parent(fix_commit)
    changed = _changed_files(parent, fix_commit)
    production = [path for path in changed if is_production_path(path)]
    tests = [path for path in changed if is_test_path(path)]
    docs = [path for path in changed if path.startswith("docs/") or path.endswith(".md")]
    file_count, additions, deletions = _diff_stats(parent, fix_commit)
    patch = git("diff", "--binary", parent, fix_commit, "--", text=False)
    if not changed or not patch:
        raise ValueError(f"historical fix has an empty first-parent patch: {task_id}")
    if production and tests:
        status = "STRUCTURALLY_READY_FOR_GOLD_CONTROL"
    elif production:
        status = "NEEDS_REVIEWED_REGRESSION_TEST"
    else:
        status = "REJECT_NO_PRODUCTION_CHANGE"
    return {
        "id": task_id,
        "fix_commit": fix_commit,
        "base_commit": parent,
        "fix_tree": str(git("rev-parse", f"{fix_commit}^{{tree}}")).strip(),
        "patch_sha256": sha256_bytes(patch),
        "changed_file_count": file_count,
        "additions": additions,
        "deletions": deletions,
        "production_paths": production,
        "test_paths": tests,
        "documentation_paths": docs,
        "production_path_count": len(production),
        "test_path_count": len(tests),
        "status": status,
        "gold_control_executed": False,
        "real_model_oracle_executed": False,
        "valid": False,
    }


def build_report(manifest: Mapping[str, Any]) -> dict[str, Any]:
    validate_manifest(manifest)
    frozen_head = str(manifest["frozen_inventory_head"])
    git("cat-file", "-e", f"{frozen_head}^{{commit}}")
    rows = [audit_task(task, frozen_head=frozen_head) for task in manifest["tasks"]]
    counts = {
        "structurally_ready": sum(row["status"] == "STRUCTURALLY_READY_FOR_GOLD_CONTROL" for row in rows),
        "needs_regression_test": sum(row["status"] == "NEEDS_REVIEWED_REGRESSION_TEST" for row in rows),
        "rejected": sum(row["status"].startswith("REJECT_") for row in rows),
    }
    report = {
        "schema_version": 1,
        "protocol": REPORT_PROTOCOL,
        "repository": manifest["repository"],
        "visibility": manifest["visibility"],
        "frozen_inventory_head": frozen_head,
        "manifest_sha256": sha256_bytes(canonical_json(manifest).encode("utf-8")),
        "summary": {
            "candidate_tasks": len(rows),
            **counts,
            "gold_controlled_tasks": 0,
            "real_model_oracle_tasks": 0,
            "valid_tasks": 0,
        },
        "tasks": rows,
        "claim_boundary": {
            "history_audit_complete": True,
            "gold_control_executed": False,
            "real_model_oracle_executed": False,
            "task_pack_ready": False,
            "product_truth_proven": False,
            "product_failure_proven": False,
            "product_maturity": "Beta",
        },
    }
    verify_report(report)
    return report


def _walk_keys(value: Any):
    if isinstance(value, Mapping):
        for key, child in value.items():
            yield str(key)
            yield from _walk_keys(child)
    elif isinstance(value, list):
        for child in value:
            yield from _walk_keys(child)


def verify_report(report: Mapping[str, Any]) -> None:
    if report.get("schema_version") != 1 or report.get("protocol") != REPORT_PROTOCOL:
        raise ValueError("source history report identity mismatch")
    if report.get("repository") != EXPECTED_REPOSITORY or report.get("visibility") != EXPECTED_VISIBILITY:
        raise ValueError("source history report repository boundary mismatch")
    if SHA_RE.fullmatch(str(report.get("frozen_inventory_head") or "")) is None:
        raise ValueError("source history report frozen head mismatch")
    if not re.fullmatch(r"[0-9a-f]{64}", str(report.get("manifest_sha256") or "")):
        raise ValueError("source history report manifest digest missing")
    tasks = report.get("tasks")
    if not isinstance(tasks, list) or len(tasks) != 8:
        raise ValueError("source history report must contain eight tasks")
    status_counts = {"structurally_ready": 0, "needs_regression_test": 0, "rejected": 0}
    for index, row in enumerate(tasks, start=1):
        if not isinstance(row, Mapping) or row.get("id") != f"{TASK_PREFIX}{index:03d}":
            raise ValueError("source history report task identity drift")
        for field in ("fix_commit", "base_commit", "fix_tree"):
            if SHA_RE.fullmatch(str(row.get(field) or "")) is None:
                raise ValueError(f"source history report task {field} is invalid")
        if not re.fullmatch(r"[0-9a-f]{64}", str(row.get("patch_sha256") or "")):
            raise ValueError("source history report patch digest missing")
        production = row.get("production_paths")
        tests = row.get("test_paths")
        if not isinstance(production, list) or not isinstance(tests, list):
            raise ValueError("source history report path inventories missing")
        if row.get("production_path_count") != len(production) or row.get("test_path_count") != len(tests):
            raise ValueError("source history report path counts drift")
        expected_status = (
            "STRUCTURALLY_READY_FOR_GOLD_CONTROL" if production and tests else
            "NEEDS_REVIEWED_REGRESSION_TEST" if production else
            "REJECT_NO_PRODUCTION_CHANGE"
        )
        if row.get("status") != expected_status:
            raise ValueError("source history report task status is inconsistent")
        if expected_status == "STRUCTURALLY_READY_FOR_GOLD_CONTROL":
            status_counts["structurally_ready"] += 1
        elif expected_status == "NEEDS_REVIEWED_REGRESSION_TEST":
            status_counts["needs_regression_test"] += 1
        else:
            status_counts["rejected"] += 1
        if row.get("gold_control_executed") is not False or row.get("real_model_oracle_executed") is not False or row.get("valid") is not False:
            raise ValueError("source history report promotes an unaudited task")
    expected_summary = {
        "candidate_tasks": 8,
        **status_counts,
        "gold_controlled_tasks": 0,
        "real_model_oracle_tasks": 0,
        "valid_tasks": 0,
    }
    if report.get("summary") != expected_summary:
        raise ValueError("source history report summary drift")
    expected_boundary = {
        "history_audit_complete": True,
        "gold_control_executed": False,
        "real_model_oracle_executed": False,
        "task_pack_ready": False,
        "product_truth_proven": False,
        "product_failure_proven": False,
        "product_maturity": "Beta",
    }
    if report.get("claim_boundary") != expected_boundary:
        raise ValueError("source history report claim boundary drift")
    forbidden = FORBIDDEN_REPORT_KEYS.intersection(_walk_keys(report))
    if forbidden:
        raise ValueError("source history report contains forbidden raw fields")
    if ABSOLUTE_PATH_RE.search(canonical_json(report)):
        raise ValueError("source history report contains an absolute local path")


def self_test(report: Mapping[str, Any]) -> None:
    mutations: list[tuple[str, dict[str, Any]]] = []
    changed_summary = copy.deepcopy(report)
    changed_summary["summary"]["valid_tasks"] = 8
    mutations.append(("summary drift", changed_summary))
    forged_valid = copy.deepcopy(report)
    forged_valid["tasks"][0]["valid"] = True
    mutations.append(("promotes an unaudited task", forged_valid))
    forged_status = copy.deepcopy(report)
    forged_status["tasks"][0]["status"] = "STRUCTURALLY_READY_FOR_GOLD_CONTROL"
    mutations.append(("status is inconsistent", forged_status))
    raw_patch = copy.deepcopy(report)
    raw_patch["tasks"][0]["raw_patch"] = "source"
    mutations.append(("forbidden raw fields", raw_patch))
    stable = copy.deepcopy(report)
    stable["claim_boundary"]["product_maturity"] = "Stable"
    mutations.append(("claim boundary drift", stable))
    product_claim = copy.deepcopy(report)
    product_claim["claim_boundary"]["product_truth_proven"] = True
    mutations.append(("claim boundary drift", product_claim))
    for fragment, payload in mutations:
        try:
            verify_report(payload)
        except ValueError as exc:
            if fragment not in str(exc):
                raise AssertionError(f"expected {fragment!r}, got {str(exc)!r}") from exc
        else:
            raise AssertionError(f"mutation was accepted: {fragment}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    report = build_report(load_json(MANIFEST_PATH))
    if args.self_test:
        self_test(report)
    output = args.output if args.output.is_absolute() else ROOT / args.output
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    summary = report["summary"]
    print(
        "Product Truth source-history audit: PASS; "
        f"candidates={summary['candidate_tasks']}; "
        f"structural={summary['structurally_ready']}; "
        f"needs_test={summary['needs_regression_test']}; "
        f"rejected={summary['rejected']}; valid=0"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
