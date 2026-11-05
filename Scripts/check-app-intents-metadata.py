#!/usr/bin/env python3
"""Check an App Intents extract against the types declared in a Swift module.

Usage: check-app-intents-metadata.py <extract.actionsdata> <swift-source-dir>

Finds every type declared as conforming to AppIntent, AppEntity, AppEnum or
AppShortcutsProvider in the sources, and fails (exit 1) unless the extract
contains each of them. Used by generate-app-intents-metadata.sh at build time
and by verify-installed-app.sh on an installed app.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

# `struct Name: A, B, AppIntent {`, `extension Name: AppEnum {` and the like,
# optionally after attributes (`@available(...)`) and modifiers, with generic
# parameters. Conformance lists in this module fit on the declaration line.
# This is a guard against drift, not a Swift parser: a conformance it cannot
# see is not required.
DECLARATION = re.compile(
    r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*"
    r"(?:(?:public|package|internal|fileprivate|private|final|open)\s+)*"
    r"(?:struct|enum|class|actor|extension)\s+(\w+)(?:<[^>{]*>)?\s*:\s*([^{]*)\{?",
    re.MULTILINE,
)
PROTOCOLS = ("AppIntent", "AppEntity", "AppEnum", "AppShortcutsProvider")
# Protocols that refine AppIntent; a conformance to any of them is an intent.
INTENT_REFINEMENTS = {
    "AppIntent",
    "OpenIntent",
    "SetValueIntent",
    "AudioPlaybackIntent",
    "AudioRecordingIntent",
    "LiveActivityIntent",
    "ForegroundContinuableIntent",
    "ProgressReportingIntent",
    "URLRepresentableIntent",
    "WidgetConfigurationIntent",
    "ControlConfigurationIntent",
}


# Block comments, then line comments. String literals containing `//` are not
# special-cased; at worst that hides a declaration later on the same line.
COMMENTS = re.compile(r"/\*.*?\*/|//[^\n]*", re.DOTALL)


def strip_comments(text: str) -> str:
    return COMMENTS.sub(lambda match: "\n" * match.group(0).count("\n"), text)


def declared_types(source_dir: Path) -> dict[str, list[str]]:
    found: dict[str, list[str]] = {name: [] for name in PROTOCOLS}
    for path in sorted(source_dir.rglob("*.swift")):
        text = strip_comments(path.read_text(encoding="utf-8"))
        for match in DECLARATION.finditer(text):
            conformances = {
                c.strip().split(" where ")[0].strip() for c in match.group(2).split(",")
            }
            name = match.group(1)
            for protocol in PROTOCOLS:
                matches = (
                    conformances & INTENT_REFINEMENTS
                    if protocol == "AppIntent"
                    else {protocol} & conformances
                )
                if matches and name not in found[protocol]:
                    found[protocol].append(name)
    return found


def identifiers(section) -> set[str]:
    """Names in an extract section, whether it is keyed by name or a list.

    Each name is also recorded by its last dotted component, because the
    checker reads bare declaration names (`Inner`, not `Outer.Inner`).
    """
    if isinstance(section, dict):
        names = set(section)
    elif isinstance(section, list):
        names = {entry.get("identifier") for entry in section if isinstance(entry, dict)}
    else:
        return set()
    names.discard(None)
    return names | {name.rsplit(".", 1)[-1] for name in names}


def check(extract: dict, declared: dict[str, list[str]]) -> list[str]:
    problems: list[str] = []
    actions = identifiers(extract.get("actions"))
    entities = identifiers(extract.get("entities"))
    enums = identifiers(extract.get("enums"))
    for name in declared["AppIntent"]:
        if name not in actions:
            problems.append(f"intent {name} is missing from actions")
    for name in declared["AppEntity"]:
        if name not in entities:
            problems.append(f"entity {name} is missing from entities")
    for name in declared["AppEnum"]:
        if name not in enums:
            problems.append(f"enum {name} is missing from enums")
    if declared["AppShortcutsProvider"]:
        if not extract.get("autoShortcutProviderMangledName"):
            problems.append("the App Shortcuts provider is missing")
        if not extract.get("autoShortcuts"):
            problems.append("no App Shortcuts were extracted")
    if not declared["AppIntent"]:
        problems.append("no AppIntent types found in the sources")
    return problems


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    extract_path, source_dir = Path(argv[1]), Path(argv[2])
    try:
        extract = json.loads(extract_path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        print(f"cannot read {extract_path}: {error}", file=sys.stderr)
        return 1
    declared = declared_types(source_dir)
    problems = check(extract, declared)
    for problem in problems:
        print(f"App Intents metadata: {problem}", file=sys.stderr)
    if problems:
        return 1
    counts = ", ".join(f"{len(v)} {k}" for k, v in declared.items())
    print(f"App Intents metadata matches the sources ({counts})")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
