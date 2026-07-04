# Help Content Philosophy

Help articles live in `Sources/KeyPathAppKit/Resources/*.md` and render in the in-app Help Browser (`HelpBrowserView.swift`). All help content follows this layered structure.

## Content hierarchy (this order matters)

1. **User goals and problems first** — Every article opens with the problem the user has, not the feature name. "Stop reaching for the Dock" not "Action URI System". "Every shortcut forces your fingers off the home row" not "Home row mods turn keys into dual-role keys."
2. **KeyPath UI and how to accomplish the goal** — Show the user how to do it in the app. Use ASCII mockups labeled as screenshots, reference actual tab names, buttons, and pickers. Step-by-step instructions tied to what they see on screen.
3. **Mechanical keyboard context (secondary)** — Introduce insider concepts (layers, tap-hold, Kanata variants, Chordal Hold, etc.) only after the user understands what they're trying to accomplish and how to do it in KeyPath. Position these in "Advanced" or "Technical Details" sections near the end.
4. **Rich external resources** — Every article ends with curated links to community references, tool docs, learning resources, and hardware. Use `↗` suffix for external links.

## Content rules

- **Titles are user goals**, not feature names: "Shortcuts Without Reaching" not "Home Row Mods", "One Key, Multiple Actions" not "Tap-Hold & Tap-Dance", "Launching Apps" not "Action URIs"
- **Cross-links use goal-oriented names** throughout all articles
- **ASCII UI mockups** labeled as "Screenshot — [description]:" show actual KeyPath UI (inspector tabs, pickers, drawers, rule editors) — not just keyboard diagrams
- **Watercolor header images** (`header-*.png`) at top of each article, rendered with `mix-blend-mode: multiply` on parchment background
- **Watercolor divider images** (`decor-divider.png`) between sections, blending into background (no white boxes)
- **Internal links** use `help:resource-name` scheme (e.g., `[Shortcuts Without Reaching](help:home-row-mods)`)
- **Technical reference docs** (like Action URI Reference) are separate from user-facing guides

## Anti-patterns to avoid

- ❌ **Don't lead with jargon** — "Hyper key", "tap-hold-release-keys", "deflayer", "CAGS layout" should never be the first thing a user reads in a section
- ❌ **Don't write feature-centric content** — "KeyPath supports 4 tap-hold variants" is engineer-speak. Write "Here's how to make one key do two things" instead
- ❌ **Don't skip the UI** — If there's a button, tab, slider, or picker involved, show it (ASCII mockup or step-by-step). Don't just say "configure it in settings"
- ❌ **Don't make the user learn Kanata to use KeyPath** — Kanata config syntax belongs in the "From Kanata" switching guide and technical references, not in user-facing how-to articles
- ❌ **Don't mix UI guides with technical references** — App launching UI guide and Action URI deep-link reference are separate articles, not one article trying to serve both audiences
- ❌ **Don't use stale tab/button names** — The UI has specific names: "Custom Rules" tab, "Key Mapper" tab, "Launchers" tab, "Add Shortcut" button, gear icon for settings shelf. Use the real names.
- ❌ **Don't rely solely on watercolor illustrations** — They set the aesthetic tone but don't teach. Use ASCII mockups of the actual KeyPath UI to show what the user will see
