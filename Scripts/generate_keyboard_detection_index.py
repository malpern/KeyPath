#!/usr/bin/env python3
"""
Generate a normalized keyboard detection index for KeyPath.

The generated runtime artifact combines:
- VIA definitions for broad VID:PID coverage
- QMK metadata and the existing QMK VID:PID index for fallback coverage
- local overrides for curated built-in aliases or exact-match corrections

The shipped app consumes only the reduced generated files, not the upstream
definition repositories.
"""

from __future__ import annotations

import argparse
import io
import json
import tarfile
import tempfile
import urllib.request
from collections import defaultdict
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path, PurePosixPath
from typing import Any


SCRIPT_DIR = Path(__file__).parent
PROJECT_ROOT = SCRIPT_DIR.parent
RESOURCES_DIR = PROJECT_ROOT / "Sources" / "KeyPathAppKit" / "Resources"

DEFAULT_QMK_METADATA = RESOURCES_DIR / "qmk-keyboard-metadata.json"
DEFAULT_QMK_INDEX = RESOURCES_DIR / "qmk-keyboard-index.json"
DEFAULT_QMK_VID_PID = RESOURCES_DIR / "qmk-vid-pid-index.json"
DEFAULT_OVERRIDES = RESOURCES_DIR / "keyboard-detection-overrides.json"
DEFAULT_OUTPUT = RESOURCES_DIR / "keyboard-detection-index.json"
DEFAULT_SOURCES_OUTPUT = RESOURCES_DIR / "keyboard-detection-sources.json"
DEFAULT_REPORT_OUTPUT = PROJECT_ROOT / "docs" / "reports" / "keyboard-detection-report.md"

VIA_REPO = "the-via/keyboards"
VIA_REF = "master"
VIA_COMMIT_API = f"https://api.github.com/repos/{VIA_REPO}/commits/{VIA_REF}"
VIA_TARBALL = f"https://codeload.github.com/{VIA_REPO}/tar.gz/refs/heads/{VIA_REF}"

EXACT_DROP_THRESHOLD = 0.10
VENDOR_DROP_THRESHOLD = 0.25


class GenerationError(RuntimeError):
    pass


@dataclass(frozen=True)
class DetectionRecord:
    match_key: str
    match_type: str
    source: str
    confidence: str
    display_name: str
    manufacturer: str | None
    qmk_path: str | None
    built_in_layout_id: str | None

    def to_json(self) -> dict[str, Any]:
        return {
            "matchKey": self.match_key,
            "matchType": self.match_type,
            "source": self.source,
            "confidence": self.confidence,
            "displayName": self.display_name,
            "manufacturer": self.manufacturer,
            "qmkPath": self.qmk_path,
            "builtInLayoutId": self.built_in_layout_id,
        }


def load_json(path: Path) -> Any:
    with path.open() as f:
        return json.load(f)


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w") as f:
        json.dump(payload, f, indent=2, sort_keys=False)
        f.write("\n")


def format_hex(value: Any, *, field: str, context: str) -> str:
    if value is None:
        raise GenerationError(f"Missing {field} for {context}")
    if isinstance(value, int):
        return f"{value:04X}"
    if isinstance(value, str):
        raw = value.strip()
        if raw.lower().startswith("0x"):
            raw = raw[2:]
        raw = raw.upper()
        if not raw or any(ch not in "0123456789ABCDEF" for ch in raw):
            raise GenerationError(f"Malformed {field} '{value}' for {context}")
        return raw.zfill(4)
    raise GenerationError(f"Unsupported {field} value '{value}' for {context}")


def qmk_display_name(qmk_path: str, metadata: dict[str, dict[str, str | None]]) -> tuple[str, str | None]:
    meta = metadata.get(qmk_path, {})
    name = meta.get("name")
    manufacturer = meta.get("manufacturer")
    if name:
        return name, manufacturer

    parts = [part for part in qmk_path.split("/") if part]
    meaningful: list[str] = []
    for part in parts:
        lower = part.lower()
        is_revision = lower.startswith("rev") and len(lower) <= 6
        is_version = lower.startswith("v") and lower[1:].isdigit()
        if is_revision or is_version:
            continue
        meaningful.append(part)
    display_parts = meaningful or parts
    pretty = []
    for part in display_parts:
        pretty.append(part if part != part.lower() else part[:1].upper() + part[1:])
    return " ".join(pretty), manufacturer


def choose_preferred_qmk_path(paths: list[str], built_in_aliases: dict[str, str]) -> str:
    unique = sorted(set(paths))
    return sorted(
        unique,
        key=lambda path: (
            built_in_aliases.get(path) is None,
            len(path),
            path,
        ),
    )[0]


def load_qmk_metadata(path: Path) -> dict[str, dict[str, str | None]]:
    data = load_json(path)
    keyboards = data.get("keyboards", {})
    result: dict[str, dict[str, str | None]] = {}
    for qmk_path, meta in keyboards.items():
        result[qmk_path] = {
            "name": meta.get("n"),
            "manufacturer": meta.get("m"),
        }
    return result


def load_qmk_index_stats(path: Path) -> int:
    data = load_json(path)
    return len(data.get("keyboards", []))


def load_overrides(path: Path) -> tuple[list[dict[str, Any]], dict[str, str]]:
    data = load_json(path)
    return data.get("exactEntries", []), data.get("qmkPathBuiltInAliases", {})


def load_qmk_vid_pid_index(
    path: Path,
    metadata: dict[str, dict[str, str | None]],
    built_in_aliases: dict[str, str],
) -> tuple[dict[str, DetectionRecord], dict[str, DetectionRecord], dict[str, Any]]:
    data = load_json(path)
    entries = data.get("entries", {})

    exact_records: dict[str, DetectionRecord] = {}
    vendor_records: dict[str, DetectionRecord] = {}
    unresolved_vendor_fallbacks: list[dict[str, Any]] = []

    exact_count = 0
    vendor_count = 0

    for key, paths in entries.items():
        unique_paths = sorted(set(paths))
        if ":" in key:
            best_path = choose_preferred_qmk_path(unique_paths, built_in_aliases)
            display_name, manufacturer = qmk_display_name(best_path, metadata)
            exact_records[key] = DetectionRecord(
                match_key=key,
                match_type="exactVIDPID",
                source="qmk",
                confidence="high",
                display_name=display_name,
                manufacturer=manufacturer,
                qmk_path=best_path,
                built_in_layout_id=built_in_aliases.get(best_path),
            )
            exact_count += 1
            continue

        if len(unique_paths) == 1:
            best_path = unique_paths[0]
            display_name, manufacturer = qmk_display_name(best_path, metadata)
            vendor_records[key] = DetectionRecord(
                match_key=key,
                match_type="vendorOnly",
                source="qmk",
                confidence="low",
                display_name=display_name,
                manufacturer=manufacturer,
                qmk_path=best_path,
                built_in_layout_id=built_in_aliases.get(best_path),
            )
            vendor_count += 1
            continue

        built_in_ids = {built_in_aliases.get(candidate) for candidate in unique_paths if built_in_aliases.get(candidate)}
        if len(built_in_ids) == 1:
            target_builtin = next(iter(built_in_ids))
            best_path = choose_preferred_qmk_path(
                [candidate for candidate in unique_paths if built_in_aliases.get(candidate) == target_builtin],
                built_in_aliases,
            )
            display_name, manufacturer = qmk_display_name(best_path, metadata)
            vendor_records[key] = DetectionRecord(
                match_key=key,
                match_type="vendorOnly",
                source="qmk",
                confidence="low",
                display_name=display_name,
                manufacturer=manufacturer,
                qmk_path=best_path,
                built_in_layout_id=target_builtin,
            )
            vendor_count += 1
            continue

        unresolved_vendor_fallbacks.append({
            "vendorId": key,
            "paths": unique_paths,
            "reason": "vendor fallback did not collapse to a single layout target",
        })

    stats = {
        "generated": data.get("generated"),
        "version": data.get("version"),
        "exactSourceEntries": exact_count,
        "vendorSourceEntries": vendor_count,
        "unresolvedVendorFallbacks": unresolved_vendor_fallbacks,
    }
    return exact_records, vendor_records, stats


def fetch_url_bytes(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": "KeyPath/1.0"})
    with urllib.request.urlopen(req, timeout=60) as response:
        return response.read()


def fetch_via_revision() -> str:
    payload = json.loads(fetch_url_bytes(VIA_COMMIT_API))
    return payload["sha"]


def derive_qmk_path_from_via_member(member_name: str) -> str:
    path = PurePosixPath(member_name)
    parts = list(path.parts)
    try:
        start = parts.index("v3") + 1
    except ValueError as exc:
        raise GenerationError(f"Unexpected VIA definition path: {member_name}") from exc
    rel_parts = parts[start:]
    filename = path.stem
    directory_parts = rel_parts[:-1]
    if directory_parts and directory_parts[-1].lower() == filename.lower():
        return "/".join(directory_parts)
    return "/".join(directory_parts + [filename])


def load_via_exact_records(
    metadata: dict[str, dict[str, str | None]],
    built_in_aliases: dict[str, str],
) -> tuple[dict[str, DetectionRecord], dict[str, Any]]:
    revision = fetch_via_revision()
    tarball = fetch_url_bytes(VIA_TARBALL)

    grouped: dict[str, list[DetectionRecord]] = defaultdict(list)
    parsed_files = 0
    skipped_files = 0

    with tarfile.open(fileobj=io.BytesIO(tarball), mode="r:gz") as archive:
        for member in archive.getmembers():
            if not member.isfile():
                continue
            if "/v3/" not in member.name or not member.name.endswith(".json"):
                continue
            fileobj = archive.extractfile(member)
            if fileobj is None:
                continue
            payload = json.load(fileobj)
            vendor_id = payload.get("vendorId")
            product_id = payload.get("productId")
            if vendor_id is None or product_id is None:
                skipped_files += 1
                continue
            qmk_path = derive_qmk_path_from_via_member(member.name)
            key = f"{format_hex(vendor_id, field='vendorId', context=member.name)}:{format_hex(product_id, field='productId', context=member.name)}"
            display_name = payload.get("name") or qmk_display_name(qmk_path, metadata)[0]
            grouped[key].append(
                DetectionRecord(
                    match_key=key,
                    match_type="exactVIDPID",
                    source="via",
                    confidence="high",
                    display_name=display_name,
                    manufacturer=None,
                    qmk_path=qmk_path or None,
                    built_in_layout_id=built_in_aliases.get(qmk_path),
                )
            )
            parsed_files += 1

    resolved: dict[str, DetectionRecord] = {}
    conflicts: list[dict[str, Any]] = []
    for key, candidates in grouped.items():
        ordered = sorted(
            candidates,
            key=lambda record: (
                record.built_in_layout_id is None,
                len(record.qmk_path or record.display_name),
                record.qmk_path or "",
                record.display_name,
            ),
        )
        resolved[key] = ordered[0]
        distinct_targets = {(candidate.qmk_path, candidate.built_in_layout_id, candidate.display_name) for candidate in ordered}
        if len(distinct_targets) > 1:
            conflicts.append({
                "matchKey": key,
                "source": "via",
                "candidates": [candidate.to_json() for candidate in ordered],
            })

    stats = {
        "repo": f"https://github.com/{VIA_REPO}",
        "ref": VIA_REF,
        "revision": revision,
        "parsedFiles": parsed_files,
        "skippedFiles": skipped_files,
        "conflicts": conflicts,
    }
    return resolved, stats


def build_override_records(exact_entries: list[dict[str, Any]], built_in_aliases: dict[str, str]) -> dict[str, DetectionRecord]:
    resolved: dict[str, DetectionRecord] = {}
    for index, entry in enumerate(exact_entries):
        context = f"override[{index}]"
        vendor_id = format_hex(entry.get("vendorId"), field="vendorId", context=context)
        product_id = format_hex(entry.get("productId"), field="productId", context=context)
        qmk_path = entry.get("qmkPath")
        resolved[f"{vendor_id}:{product_id}"] = DetectionRecord(
            match_key=f"{vendor_id}:{product_id}",
            match_type="exactVIDPID",
            source="override",
            confidence="high",
            display_name=entry.get("displayName") or qmk_path or f"{vendor_id}:{product_id}",
            manufacturer=entry.get("manufacturer"),
            qmk_path=qmk_path,
            built_in_layout_id=entry.get("builtInLayoutId") or (built_in_aliases.get(qmk_path) if qmk_path else None),
        )
    return resolved


def records_are_compatible(existing: DetectionRecord, incoming: DetectionRecord) -> bool:
    if existing.qmk_path and incoming.qmk_path and existing.qmk_path == incoming.qmk_path:
        return True
    if existing.built_in_layout_id and incoming.built_in_layout_id and existing.built_in_layout_id == incoming.built_in_layout_id:
        return True
    return False


def merge_exact_records(
    qmk_exact: dict[str, DetectionRecord],
    via_exact: dict[str, DetectionRecord],
    override_exact: dict[str, DetectionRecord],
) -> tuple[dict[str, DetectionRecord], list[dict[str, Any]], list[dict[str, Any]]]:
    merged = dict(qmk_exact)
    resolved_conflicts: list[dict[str, Any]] = []
    unresolved_conflicts: list[dict[str, Any]] = []

    for source_name, incoming in (("via", via_exact),):
        for key, record in incoming.items():
            existing = merged.get(key)
            if existing and existing != record:
                if not records_are_compatible(existing, record):
                    unresolved_conflicts.append({
                        "matchKey": key,
                        "existing": existing.to_json(),
                        "incoming": record.to_json(),
                        "reason": "sources disagree on exact match and no override is present",
                    })
                    merged.pop(key, None)
                    continue
                resolved_conflicts.append({
                    "matchKey": key,
                    "replaced": existing.to_json(),
                    "selected": record.to_json(),
                    "reason": f"{source_name} entry takes precedence",
                })
            merged[key] = record

    for key, record in override_exact.items():
        existing = merged.get(key)
        if existing and existing != record:
            resolved_conflicts.append({
                "matchKey": key,
                "replaced": existing.to_json(),
                "selected": record.to_json(),
                "reason": "override entry takes precedence",
            })
        elif not existing:
            unresolved_conflicts = [conflict for conflict in unresolved_conflicts if conflict["matchKey"] != key]
        merged[key] = record

    return merged, resolved_conflicts, unresolved_conflicts


def compare_coverage(previous_manifest: dict[str, Any] | None, exact_count: int, vendor_count: int, allow_drop: bool) -> None:
    if previous_manifest is None or allow_drop:
        return

    previous_coverage = previous_manifest.get("coverage", {})
    previous_exact = int(previous_coverage.get("exactEntries", 0))
    previous_vendor = int(previous_coverage.get("vendorFallbackEntries", 0))

    if previous_exact > 0 and exact_count < int(previous_exact * (1 - EXACT_DROP_THRESHOLD)):
        raise GenerationError(
            f"Exact entry count dropped from {previous_exact} to {exact_count}. "
            "Pass --allow-coverage-drop to acknowledge the change."
        )

    if previous_vendor > 0 and vendor_count < int(previous_vendor * (1 - VENDOR_DROP_THRESHOLD)):
        raise GenerationError(
            f"Vendor fallback entry count dropped from {previous_vendor} to {vendor_count}. "
            "Pass --allow-coverage-drop to acknowledge the change."
        )


def render_report(
    exact_records: dict[str, DetectionRecord],
    vendor_records: dict[str, DetectionRecord],
    source_counts: dict[str, int],
    via_stats: dict[str, Any],
    qmk_stats: dict[str, Any],
    resolved_conflicts: list[dict[str, Any]],
    unresolved_exact_conflicts: list[dict[str, Any]],
    previous_manifest: dict[str, Any] | None,
) -> str:
    previous_coverage = (previous_manifest or {}).get("coverage", {})
    exact_delta = len(exact_records) - int(previous_coverage.get("exactEntries", 0))
    vendor_delta = len(vendor_records) - int(previous_coverage.get("vendorFallbackEntries", 0))

    lines = [
        "# Keyboard Detection Report",
        "",
        f"- Generated: {datetime.now(UTC).strftime('%Y-%m-%d %H:%M:%SZ')}",
        f"- Exact entries: {len(exact_records)} ({exact_delta:+d} vs previous manifest)",
        f"- Vendor fallback entries: {len(vendor_records)} ({vendor_delta:+d} vs previous manifest)",
        f"- Final exact source mix: override={source_counts['override']}, via={source_counts['via']}, qmk={source_counts['qmk']}",
        f"- VIA revision: `{via_stats['revision']}`",
        f"- VIA parsed files: {via_stats['parsedFiles']} (skipped without IDs: {via_stats['skippedFiles']})",
        f"- QMK exact source entries: {qmk_stats['exactSourceEntries']}",
        f"- QMK vendor source entries: {qmk_stats['vendorSourceEntries']}",
        f"- QMK unresolved vendor fallbacks omitted from runtime index: {len(qmk_stats['unresolvedVendorFallbacks'])}",
        f"- Exact precedence conflicts resolved: {len(resolved_conflicts) + len(via_stats['conflicts'])}",
        f"- Exact conflicts omitted pending override: {len(unresolved_exact_conflicts)}",
        "",
    ]

    if resolved_conflicts:
        lines.extend(["## Resolved Exact-Match Conflicts", ""])
        for conflict in resolved_conflicts[:25]:
            selected = conflict["selected"]
            replaced = conflict["replaced"]
            lines.append(
                f"- `{conflict['matchKey']}` selected `{selected['source']}:{selected.get('qmkPath') or selected['displayName']}` over `{replaced['source']}:{replaced.get('qmkPath') or replaced['displayName']}`"
            )
        lines.append("")

    if unresolved_exact_conflicts:
        lines.extend(["## Omitted Exact-Match Conflicts", ""])
        for conflict in unresolved_exact_conflicts[:25]:
            existing = conflict["existing"]
            incoming = conflict["incoming"]
            lines.append(
                f"- `{conflict['matchKey']}` omitted because `{existing['source']}:{existing.get('qmkPath') or existing['displayName']}` disagrees with `{incoming['source']}:{incoming.get('qmkPath') or incoming['displayName']}`"
            )
        lines.append("")

    if via_stats["conflicts"]:
        lines.extend(["## VIA Duplicate VID:PID Collisions", ""])
        for conflict in via_stats["conflicts"][:25]:
            candidates = ", ".join(candidate.get("qmkPath") or candidate["displayName"] for candidate in conflict["candidates"])
            lines.append(f"- `{conflict['matchKey']}` -> {candidates}")
        lines.append("")

    if qmk_stats["unresolvedVendorFallbacks"]:
        lines.extend(["## Omitted Vendor Fallbacks", ""])
        for conflict in qmk_stats["unresolvedVendorFallbacks"][:25]:
            lines.append(f"- `{conflict['vendorId']}` -> {', '.join(conflict['paths'])}")
        lines.append("")

    return "\n".join(lines).rstrip() + "\n"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--qmk-vid-pid", type=Path, default=DEFAULT_QMK_VID_PID)
    parser.add_argument("--qmk-metadata", type=Path, default=DEFAULT_QMK_METADATA)
    parser.add_argument("--qmk-index", type=Path, default=DEFAULT_QMK_INDEX)
    parser.add_argument("--overrides", type=Path, default=DEFAULT_OVERRIDES)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--sources-output", type=Path, default=DEFAULT_SOURCES_OUTPUT)
    parser.add_argument("--report-output", type=Path, default=DEFAULT_REPORT_OUTPUT)
    parser.add_argument("--allow-coverage-drop", action="store_true")
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    previous_manifest = load_json(args.sources_output) if args.sources_output.exists() else None

    metadata = load_qmk_metadata(args.qmk_metadata)
    qmk_keyboard_count = load_qmk_index_stats(args.qmk_index)
    override_entries, built_in_aliases = load_overrides(args.overrides)

    qmk_exact, vendor_records, qmk_stats = load_qmk_vid_pid_index(args.qmk_vid_pid, metadata, built_in_aliases)
    via_exact, via_stats = load_via_exact_records(metadata, built_in_aliases)
    override_exact = build_override_records(override_entries, built_in_aliases)
    merged_exact, resolved_conflicts, unresolved_exact_conflicts = merge_exact_records(qmk_exact, via_exact, override_exact)

    source_counts = {
        "override": sum(1 for record in merged_exact.values() if record.source == "override"),
        "via": sum(1 for record in merged_exact.values() if record.source == "via"),
        "qmk": sum(1 for record in merged_exact.values() if record.source == "qmk"),
    }

    compare_coverage(previous_manifest, len(merged_exact), len(vendor_records), args.allow_coverage_drop)

    generated = datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
    index_payload = {
        "version": "1.0",
        "generated": generated,
        "exactEntries": [merged_exact[key].to_json() for key in sorted(merged_exact)],
        "vendorFallbackEntries": [vendor_records[key].to_json() for key in sorted(vendor_records)],
    }

    manifest_payload = {
        "version": "1.0",
        "generated": generated,
        "generator": "Scripts/generate_keyboard_detection_index.py",
        "upstream": {
            "via": {
                "repo": via_stats["repo"],
                "ref": via_stats["ref"],
                "revision": via_stats["revision"],
                "parsedFiles": via_stats["parsedFiles"],
                "skippedFiles": via_stats["skippedFiles"],
            },
            "qmk": {
                "keyboardIndexPath": str(args.qmk_index.relative_to(PROJECT_ROOT)),
                "keyboardCount": qmk_keyboard_count,
                "metadataPath": str(args.qmk_metadata.relative_to(PROJECT_ROOT)),
                "metadataCount": len(metadata),
                "vidPidIndexPath": str(args.qmk_vid_pid.relative_to(PROJECT_ROOT)),
                "vidPidGenerated": qmk_stats["generated"],
                "vidPidVersion": qmk_stats["version"],
                "exactSourceEntries": qmk_stats["exactSourceEntries"],
                "vendorSourceEntries": qmk_stats["vendorSourceEntries"],
            },
        },
        "coverage": {
            "exactEntries": len(merged_exact),
            "vendorFallbackEntries": len(vendor_records),
            "exactEntriesBySource": source_counts,
            "resolvedExactConflicts": len(resolved_conflicts) + len(via_stats["conflicts"]),
            "unresolvedExactConflicts": len(unresolved_exact_conflicts),
            "unresolvedVendorFallbacks": len(qmk_stats["unresolvedVendorFallbacks"]),
        },
    }

    report = render_report(
        merged_exact,
        vendor_records,
        source_counts,
        via_stats,
        qmk_stats,
        resolved_conflicts,
        unresolved_exact_conflicts,
        previous_manifest,
    )

    write_json(args.output, index_payload)
    write_json(args.sources_output, manifest_payload)
    args.report_output.parent.mkdir(parents=True, exist_ok=True)
    args.report_output.write_text(report)

    print(f"Wrote {len(merged_exact)} exact entries to {args.output}")
    print(f"Wrote {len(vendor_records)} vendor fallback entries to {args.output}")
    print(f"Wrote provenance manifest to {args.sources_output}")
    print(f"Wrote report to {args.report_output}")


if __name__ == "__main__":
    main()
