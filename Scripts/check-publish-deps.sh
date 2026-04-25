#!/usr/bin/env bash
# Static dependency checker for the publish pipeline.
#
# Goal: catch the class of failure where a script reaches for a
# command (or Python module) that isn't on the GitHub Actions
# `ubuntu-latest` runner. We learned the hard way that ripgrep,
# numpy, and Pillow aren't bundled by default — each one took its
# own follow-up PR to surface and fix because Bash exits on the
# first failure.
#
# Approach: check against a curated **watch list** of modern CLI
# tools and Python modules that power-users have locally but
# runners don't. A naive "list every external command" parser
# would either drown in false positives (every awk-internal token
# looking like a command) or false negatives (string-literal data
# inside arrays). The watch list is the pragmatic middle: small,
# accurate, easy to extend when a new offender shows up.
#
# Usage:
#   Scripts/check-publish-deps.sh                   # checks the default set
#   Scripts/check-publish-deps.sh path/to/script.sh # check a specific script
#   Scripts/check-publish-deps.sh --strict          # exit non-zero on findings
#
# What it doesn't catch (by design):
#   - Logic bugs (use a real run for those)
#   - Missing PNG/asset files referenced by markdown
#   - GNU-vs-BSD command divergence (e.g. `sed -i` semantics)
#   - Tools we forgot to add to the watch list — extend
#     `RUNNER_MISSING_TOOLS` below when a new offender bites us.

set -uo pipefail

DEFAULT_TARGETS=(
  "Scripts/publish-help-to-web.sh"
  "Scripts/test-help-publish-regressions.sh"
  "Scripts/check-help-parity.sh"
  "Scripts/validate-screenshot-manifest.sh"
)

STRICT=false
TARGETS=()
for arg in "$@"; do
  case "$arg" in
    --strict) STRICT=true ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) TARGETS+=("$arg") ;;
  esac
done
if [[ ${#TARGETS[@]} -eq 0 ]]; then
  TARGETS=("${DEFAULT_TARGETS[@]}")
fi

# ---------------------------------------------------------------------------
# Watch list: CLI tools that power users tend to have locally
# (homebrew, asdf) but `ubuntu-latest` runners do NOT. When a
# script reaches for one of these without a `command -v X` fallback
# guard, the workflow blows up.
#
# Add to this list whenever a new offender bites us. Keep
# alphabetised. Sources for what's NOT in the runner:
#   https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md
# ---------------------------------------------------------------------------

RUNNER_MISSING_TOOLS=(
  ag        # the_silver_searcher (rg's older cousin)
  bat       # cat with syntax highlighting
  delta     # nicer git diff
  eza       # ls replacement (the modern fork of exa)
  exa       # ls replacement (older)
  fd        # find replacement
  glow      # markdown renderer
  hyperfine # benchmarking
  mdcat     # markdown→terminal renderer
  rg        # ripgrep — bit us in PR #332
  sd        # sed replacement
  shellcheck
  tree      # not always present on minimal runner images
  watchexec # file watcher
  yq        # YAML query (jq is present, yq usually is not)
  zoxide    # smarter cd
)

# macOS-only commands that would catastrophically fail on Linux
# runners. Listed separately so the report can label them more
# clearly.
MACOS_ONLY_TOOLS=(
  codesign
  defaults
  diskutil
  hdiutil
  launchctl
  networksetup
  osascript
  pbcopy
  pbpaste
  plutil
  pmset
  security
  sips
  spctl
)

# ---------------------------------------------------------------------------
# Python modules: stdlib is fine; anything else needs explicit
# install in the workflow. We already install numpy + Pillow there.
# ---------------------------------------------------------------------------

PYTHON_STDLIB=(
  argparse base64 collections csv dataclasses datetime decimal enum
  errno fnmatch functools glob hashlib io itertools json logging
  math os pathlib pickle random re shutil socket struct subprocess
  sys tempfile textwrap threading time typing unittest urllib uuid
  xml zipfile
)

PYTHON_INSTALLED=(
  numpy
  PIL
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

contains() {
  # contains <needle> <items…>
  # Pass the array expanded with `"${arr[@]}"` rather than by name —
  # `local -n` (bash 4.3+) is unavailable on default macOS bash 3.2,
  # so we keep this explicit-args version compatible with both.
  local needle="$1" item
  shift
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

# Does the script anywhere defend against a missing `tool` via a
# `command -v tool` or `which tool` probe? If so we trust the
# script knows what it's doing and skip the warning for that tool
# in that script.
has_runtime_guard() {
  local file="$1" tool="$2"
  grep -qE "(command[[:space:]]+-v|\<which\>)[[:space:]]+${tool}\b" "$file"
}

# Find all uses of `tool` in `file`, excluding those that:
#   - are inside a comment line
#   - are part of the `command -v tool` / `which tool` guard itself
#   - sit inside a string that mentions the tool only as text
#     (e.g. error messages — we can't fully detect this, but the
#     watch-list approach avoids most false positives)
# Returns "file:line" pairs where each match was found, or nothing
# if not found.
find_tool_uses() {
  local file="$1" tool="$2"
  # Match `tool` as a whole word, anchored at a position where it
  # is plausibly a command (preceded by start-of-line, whitespace,
  # `|`, `;`, `&`, `(`, `$(`, or `=`).
  grep -nE "(^|[|;&[:space:](=]|\\\$\()${tool}([[:space:]]|$)" "$file" \
    | grep -vE "^[[:space:]]*[0-9]+:[[:space:]]*#" \
    | grep -vE "(command[[:space:]]+-v|\<which\>)[[:space:]]+${tool}\b" \
    || true
}

# Find Python imports inside `python3 - <<'PY' ... PY` heredocs.
# Handles all four shapes:
#   import foo
#   import foo.bar
#   import foo, bar, baz       ← multiple on one line, was missed pre-fix
#   import foo as f
#   from foo import bar
#   from foo.bar import baz
extract_python_imports() {
  local file="$1"
  awk '
    function emit(line, mod) {
      sub(/^[[:space:]]+/, "", mod)
      sub(/[[:space:]]+as[[:space:]]+.*$/, "", mod)  # strip "as alias"
      sub(/\..*$/, "", mod)                          # top-level package only
      sub(/[[:space:]]+$/, "", mod)
      if (mod != "") print FILENAME ":" line ":" mod
    }

    /<<[[:space:]]*'\''?PY'\''?/ { in_heredoc=1; next }
    /^PY[[:space:]]*$/ { in_heredoc=0; next }
    in_heredoc {
      # `from foo import …` — single top-level package, easy.
      if (match($0, /^[[:space:]]*from[[:space:]]+[A-Za-z_][A-Za-z0-9_.]*/)) {
        spec = substr($0, RSTART, RLENGTH)
        sub(/^[[:space:]]*from[[:space:]]+/, "", spec)
        emit(NR, spec)
        next
      }
      # `import foo[, bar[, baz]]` — split on commas to catch every
      # module on the line.
      if (match($0, /^[[:space:]]*import[[:space:]]+[A-Za-z_][A-Za-z0-9_., ]*/)) {
        spec = substr($0, RSTART, RLENGTH)
        sub(/^[[:space:]]*import[[:space:]]+/, "", spec)
        n = split(spec, mods, /[[:space:]]*,[[:space:]]*/)
        for (i = 1; i <= n; i++) emit(NR, mods[i])
      }
    }
  ' "$file"
}

classify_python() {
  local mod="$1"
  if contains "$mod" "${PYTHON_STDLIB[@]}"; then echo baseline; return; fi
  if contains "$mod" "${PYTHON_INSTALLED[@]}"; then echo installed; return; fi
  echo missing
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

# Dedupe across multiple line matches. Stored as a simple
# space-delimited string of `<key>` tokens rather than a true
# associative array — `declare -A` requires bash 4+, which macOS
# ships pre-installed users do not have. Keys are formatted to
# avoid spaces so substring matching stays unambiguous.
SEEN_KEYS=""
findings=0

report() {
  local kind="$1" file="$2" line="$3" name="$4" status="$5"
  local key="${kind}|${file}|${name}"
  case " $SEEN_KEYS " in
    *" $key "*) return ;;
  esac
  SEEN_KEYS="$SEEN_KEYS $key"
  case "$status" in
    missing)
      echo "  ${file}:${line}: ${kind} '${name}' is NOT on the runner baseline."
      ((findings++))
      ;;
    macos_only)
      echo "  ${file}:${line}: ${kind} '${name}' is macOS-only — won't exist on Linux runners."
      ((findings++))
      ;;
  esac
}

echo "Static dependency check against ubuntu-latest baseline + workflow installs."
echo

for target in "${TARGETS[@]}"; do
  if [[ ! -f "$target" ]]; then
    echo "warning: $target does not exist; skipping" >&2
    continue
  fi
  echo "Scanning $target"

  # Watch-listed CLI tools.
  for tool in "${RUNNER_MISSING_TOOLS[@]}"; do
    # Skip if the script has a `command -v` guard for this tool.
    if has_runtime_guard "$target" "$tool"; then continue; fi
    while IFS= read -r match; do
      [[ -z "$match" ]] && continue
      line="${match%%:*}"
      report "command" "$target" "$line" "$tool" "missing"
    done < <(find_tool_uses "$target" "$tool")
  done

  # macOS-only tools.
  for tool in "${MACOS_ONLY_TOOLS[@]}"; do
    while IFS= read -r match; do
      [[ -z "$match" ]] && continue
      line="${match%%:*}"
      report "command" "$target" "$line" "$tool" "macos_only"
    done < <(find_tool_uses "$target" "$tool")
  done

  # Python imports inside heredocs.
  while IFS=: read -r file line mod; do
    [[ -z "$mod" ]] && continue
    status=$(classify_python "$mod")
    [[ "$status" == "missing" ]] && report "python module" "$file" "$line" "$mod" "missing"
  done < <(extract_python_imports "$target")
done

echo
if [[ $findings -eq 0 ]]; then
  echo "OK — no missing dependencies detected."
  exit 0
fi

echo "Found $findings dependency issue(s). Fix options for each:"
echo "  - Add a 'command -v X' fallback guard in the script (preferred)."
echo "  - Install the dependency in .github/workflows/publish-help-docs.yml"
echo "    (then add it to PYTHON_INSTALLED in this script for Python deps)."
echo "  - Replace the missing tool with a stdlib equivalent (grep, awk, etc)."

if $STRICT; then
  exit 1
fi
exit 0
