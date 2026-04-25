#!/usr/bin/env python3
"""
Sync the in-app help docs (`Sources/KeyPathAppKit/Resources/*.md`) into
the Jekyll documentation site that lives on the `gh-pages` branch.

The script transforms each app-style markdown file into a Jekyll-style
markdown file:
  - Adds Jekyll front matter (layout, title, description, theme,
    header_image, permalink).
  - Translates internal links: `[text](help:foo)` becomes
    `[text]({{ '/guides/foo/' | relative_url }})`.
  - Strips the leading `![alt](header-*.png)` line from the body and
    moves it into the `header_image:` front-matter field.
  - Copies referenced `header-*.png` files from the app's resources
    directory to the site's `images/help/` directory.

Operating principles (encoded in the implementation):
  - Add or update only. Pages that exist on `gh-pages/guides/` but
    have no app source (e.g. `activity-insights.md`) are left alone.
  - Header images are copied, never deleted.
  - The script is idempotent: running twice with no source changes
    produces no diff in the gh-pages worktree.

Usage:
    python3 Scripts/sync-docs-to-pages.py \\
        --gh-pages-worktree /tmp/keypath-gh-pages \\
        [--dry-run]

The expected workflow (CI-driven):
    git worktree add ../gh-pages-worktree gh-pages
    python3 Scripts/sync-docs-to-pages.py \\
        --gh-pages-worktree ../gh-pages-worktree
    cd ../gh-pages-worktree
    git add -A
    git diff --cached --quiet || git commit -m "..." && git push
"""
from __future__ import annotations

import argparse
import re
import shutil
import sys
from pathlib import Path
from typing import Iterable

# Hand-maintained sidecar; loaded lazily.
META_FILENAME = "_jekyll_meta.yml"

# Where header images live on the Jekyll site.
JEKYLL_IMAGE_SUBDIR = Path("images/help")

# Where guide markdown files live on the Jekyll site.
JEKYLL_GUIDES_SUBDIR = Path("guides")

# Files in `Resources/` we never sync (sidecar metadata, etc.).
SKIP_FILES = {META_FILENAME}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.strip().splitlines()[0])
    parser.add_argument(
        "--gh-pages-worktree",
        type=Path,
        required=True,
        help="Path to a checked-out worktree of the `gh-pages` branch.",
    )
    parser.add_argument(
        "--source-dir",
        type=Path,
        default=Path("Sources/KeyPathAppKit/Resources"),
        help="Directory containing the in-app help markdown files.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Don't write anything; just report what would change.",
    )
    args = parser.parse_args()

    source_dir: Path = args.source_dir.resolve()
    target_root: Path = args.gh_pages_worktree.resolve()

    if not source_dir.is_dir():
        print(f"error: source directory not found: {source_dir}", file=sys.stderr)
        return 2
    if not target_root.is_dir():
        print(f"error: gh-pages worktree not found: {target_root}", file=sys.stderr)
        return 2

    meta = load_meta(source_dir / META_FILENAME)

    target_guides_dir = target_root / JEKYLL_GUIDES_SUBDIR
    target_images_dir = target_root / JEKYLL_IMAGE_SUBDIR
    if not args.dry_run:
        target_guides_dir.mkdir(parents=True, exist_ok=True)
        target_images_dir.mkdir(parents=True, exist_ok=True)

    sync_count = 0
    image_count = 0
    skipped: list[str] = []
    for md_path in sorted(source_dir.glob("*.md")):
        if md_path.name in SKIP_FILES:
            continue
        slug = md_path.stem
        page_meta = meta.get(slug, {})
        # Sidecar opt-out for pages whose gh-pages copy is hand-curated
        # at a non-default path (e.g. `getting-started/installation.md`).
        if str(page_meta.get("skip_jekyll", "")).lower() == "true":
            skipped.append(slug)
            continue
        try:
            jekyll_md, header_image, inline_images = transform(
                md_path, slug, page_meta
            )
        except TransformError as e:
            print(f"error: {md_path.name}: {e}", file=sys.stderr)
            return 1

        target_md = target_guides_dir / md_path.name
        if write_if_changed(target_md, jekyll_md, args.dry_run):
            sync_count += 1
            print(f"  guide: {md_path.name}")

        # Copy referenced images (header + inline). Both share the
        # `images/help/` destination on the Jekyll site.
        all_images: list[str] = []
        if header_image:
            all_images.append(header_image)
        all_images.extend(inline_images)
        for image_name in all_images:
            src_image = source_dir / image_name
            if not src_image.exists():
                print(
                    f"warning: {md_path.name} references missing image "
                    f"{image_name!r}",
                    file=sys.stderr,
                )
                continue
            target_image = target_images_dir / image_name
            if copy_if_changed(src_image, target_image, args.dry_run):
                image_count += 1
                print(f"  image: {image_name}")

    if skipped:
        print(f"Skipped {len(skipped)} (skip_jekyll): {', '.join(skipped)}")
    summary = (
        f"Synced {sync_count} guide(s), {image_count} image(s)"
        f"{' (dry run)' if args.dry_run else ''}."
    )
    print(summary)
    return 0


# ---------------------------------------------------------------------------
# Transformation
# ---------------------------------------------------------------------------

class TransformError(Exception):
    pass


HEADER_IMAGE_RE = re.compile(r"^!\[[^\]]*\]\((header-[^)]+)\)\s*$")
HELP_LINK_RE = re.compile(r"\(help:([a-z0-9\-]+)\)")
H1_RE = re.compile(r"^#\s+(.+?)\s*$")
# Body-level image references that aren't already wrapped in Jekyll's
# `relative_url` helper. Captures `(alt, filename)`.
INLINE_IMAGE_RE = re.compile(r"!\[([^\]]*)\]\(([^){}]+\.(?:png|jpg|jpeg|gif|svg))\)")
# In-app screenshot-automation directive. The site has a separate
# screenshot-rendering pipeline that fills in the actual PNG; the
# sync just emits the corresponding markdown image reference so the
# rendered page picks it up. Format:
#   <!-- screenshot: id="<slug>" method="..." view="..." state="..." -->
SCREENSHOT_DIRECTIVE_RE = re.compile(
    r"<!--\s*screenshot:\s*id=\"([a-z0-9\-]+)\"[^>]*-->"
)


def transform(
    md_path: Path,
    slug: str,
    page_meta: dict,
) -> tuple[str, str | None, list[str]]:
    """Return (jekyll_markdown, header_image_filename_or_None,
    inline_image_filenames). The inline images are reported so the
    caller can copy them alongside the markdown."""
    raw = md_path.read_text()
    lines = raw.splitlines()
    if not lines:
        raise TransformError("empty file")

    # 1. Pluck a leading header-image line out of the body. The Jekyll
    #    layout renders header_image from front matter, so we must not
    #    leave it in the body too.
    header_image: str | None = None
    body_start = 0
    if lines:
        match = HEADER_IMAGE_RE.match(lines[0])
        if match:
            header_image = match.group(1)
            body_start = 1
            # also skip a blank line that typically follows
            if body_start < len(lines) and lines[body_start].strip() == "":
                body_start += 1

    # 2. Find the title — first H1 in the body.
    title: str | None = page_meta.get("title")
    for line in lines[body_start:]:
        m = H1_RE.match(line)
        if m:
            title = title or m.group(1).strip()
            break
    if not title:
        raise TransformError("no H1 found and no title in metadata")

    # 3. Description: prefer sidecar; fall back to a sentence from the body.
    description = page_meta.get("description") or first_sentence(lines[body_start:])
    if not description:
        raise TransformError("no description in metadata and no body sentence")

    # 4. Translate internal links. `help:foo-bar` → relative_url helper.
    body = "\n".join(lines[body_start:])
    body = HELP_LINK_RE.sub(
        lambda m: "({{ '/guides/" + m.group(1) + "/' | relative_url }})",
        body,
    )

    # 5. Translate inline image references. The app stores both the
    #    markdown and its referenced images side-by-side in
    #    `Resources/`; the Jekyll site keeps markdown in `guides/`
    #    and images in `images/help/`. Rewriting the path here lets
    #    Jekyll's `relative_url` filter resolve correctly regardless
    #    of where the site is mounted (root domain vs `/KeyPath`).
    inline_images: list[str] = []

    def replace_inline(match: re.Match[str]) -> str:
        alt = match.group(1)
        filename = match.group(2)
        # Don't double-rewrite if the path is already qualified.
        if filename.startswith(("http://", "https://", "/", "{{")):
            return match.group(0)
        inline_images.append(filename)
        return f"![{alt}]({{{{ '/images/help/{filename}' | relative_url }}}})"

    body = INLINE_IMAGE_RE.sub(replace_inline, body)

    # Screenshot-automation directives: emit a markdown image whose
    # path resolves into the site's `images/help/<id>.png`. We do
    # NOT track these in `inline_images` because the PNG itself is
    # produced by a separate screenshot-rendering pipeline, not by
    # this script.
    body = SCREENSHOT_DIRECTIVE_RE.sub(
        lambda m: (
            "![Screenshot]({{ '/images/help/"
            + m.group(1)
            + ".png' | relative_url }})"
        ),
        body,
    )

    # 6. Compose front matter.
    front_matter = format_front_matter({
        "layout": "default",
        "title": title,
        "description": description,
        "theme": page_meta.get("theme", "parchment"),
        **({"header_image": header_image} if header_image else {}),
        "permalink": f"/guides/{slug}/",
    })

    return front_matter + "\n\n" + body.lstrip() + "\n", header_image, inline_images


def first_sentence(body_lines: Iterable[str]) -> str | None:
    """Best-effort fallback for `description` when sidecar is missing.
    Walks paragraphs, returns the first ~one-sentence chunk that isn't
    a heading or boilerplate."""
    skip_prefixes = ("#", ">", "|", "-", "*", "!", "```", "<")
    for line in body_lines:
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.startswith(skip_prefixes):
            continue
        # Take up to the first sentence terminator. Cap length.
        for terminator in (". ", "! ", "? "):
            if terminator in stripped:
                stripped = stripped.split(terminator, 1)[0] + terminator.strip()
                break
        return strip_inline_md(stripped)[:240]
    return None


def strip_inline_md(s: str) -> str:
    """Strip the small inline markdown the description rendering won't
    handle gracefully — bold/italic wrappers, inline code backticks,
    link wrappers (keep the text)."""
    s = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", s)  # links → label
    s = re.sub(r"\*\*([^*]+)\*\*", r"\1", s)  # bold
    s = re.sub(r"`([^`]+)`", r"\1", s)  # inline code
    return s


# ---------------------------------------------------------------------------
# YAML helpers
# ---------------------------------------------------------------------------


def load_meta(path: Path) -> dict:
    """Tiny YAML loader sufficient for our sidecar shape.

    The sidecar is a flat mapping of `slug: { description: "...", ... }`.
    Stdlib doesn't ship a YAML parser; we keep the format simple enough
    that a 30-line parser handles it without adding a dependency to
    macOS CI runners.
    """
    if not path.exists():
        return {}
    text = path.read_text()
    result: dict = {}
    current_slug: str | None = None
    for raw in text.splitlines():
        line = raw.rstrip()
        if not line or line.lstrip().startswith("#"):
            continue
        if not line.startswith(" "):
            # `slug:` header
            if not line.endswith(":"):
                raise TransformError(
                    f"unexpected top-level line in {path.name}: {line!r}"
                )
            current_slug = line[:-1].strip()
            result[current_slug] = {}
        else:
            if current_slug is None:
                raise TransformError(f"orphan field in {path.name}: {line!r}")
            stripped = line.strip()
            if ":" not in stripped:
                raise TransformError(f"missing colon in {path.name}: {line!r}")
            key, _, raw_value = stripped.partition(":")
            value = raw_value.strip()
            # Strip optional surrounding quotes.
            if len(value) >= 2 and value[0] == value[-1] and value[0] in ('"', "'"):
                value = value[1:-1]
            result[current_slug][key.strip()] = value
    return result


# YAML keys we always want quoted (because they often contain colons,
# punctuation, etc. that would otherwise break Jekyll's parsing).
QUOTED_KEYS = {"title", "description"}


def format_front_matter(fields: dict) -> str:
    out = ["---"]
    for key, value in fields.items():
        if key in QUOTED_KEYS:
            escaped = str(value).replace("\\", "\\\\").replace('"', '\\"')
            out.append(f'{key}: "{escaped}"')
        else:
            out.append(f"{key}: {value}")
    out.append("---")
    return "\n".join(out)


# ---------------------------------------------------------------------------
# I/O helpers
# ---------------------------------------------------------------------------


def write_if_changed(path: Path, content: str, dry_run: bool) -> bool:
    """Write `content` to `path` only if it differs. Returns True if a
    change was needed (and applied unless `dry_run`)."""
    if path.exists() and path.read_text() == content:
        return False
    if not dry_run:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
    return True


def copy_if_changed(src: Path, dst: Path, dry_run: bool) -> bool:
    """Copy `src` to `dst` only if the contents differ. Returns True if
    a change was needed."""
    if dst.exists() and dst.read_bytes() == src.read_bytes():
        return False
    if not dry_run:
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
    return True


if __name__ == "__main__":
    raise SystemExit(main())
