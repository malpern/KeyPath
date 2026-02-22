# Neovim in the Terminal

You live in the terminal. Neovim is your editor. But when you switch to other macOS apps, your muscle memory goes silent — no `hjkl`, no `w`/`b`, no `gd`. KeyPath bridges the gap: hold the Leader key and your vim instincts work everywhere, while the HUD shows a quick-reference card for the Neovim commands you use most.

## What You Get

Enable the **Neovim Terminal** collection in the Rules tab and you get two things:

1. **Leader-layer shortcuts** — hold the Leader key and use `h j k l`, `w b e`, `0 $`, `/`, `y`, `p`, and more in any macOS app. These translate vim motions into native macOS cursor movements and editing commands.

2. **Quick-reference HUD** — the same Leader hold pops up a categorized reference card covering core vim *and* Neovim-specific features (LSP, Telescope, buffers, terminal mode). Glance at it when you forget a binding; dismiss by releasing Leader.

## Enabling It

1. Open **KeyPath → Rules** tab
2. Find **Neovim Terminal** in the Navigation section
3. Toggle it **on**

The collection shares the navigation layer with Vim and KindaVim — only one of the three should be active at a time. KeyPath handles conflict detection automatically.

## The HUD Reference Card

When you hold the Leader key, the HUD appears with two columns:

**Left column — Core Vim:**
- **Movement** — `h j k l`, `w b e`, `0 $`, `gg G`, `f t`, `{ }`
- **Operators** — `d`, `c`, `y`, `> <`, `=`
- **Text Objects** — `iw aw`, `ip ap`, `i" a"`
- **Search** — `/ ?`, `n N`, `* #`

**Right column — Neovim-specific:**
- **Buffers & Tabs** — `:bn :bp :bd`, `gt gT`, `Ctrl-^`
- **LSP** — `gd`, `gr`, `K`, `<leader>rn`, `<leader>ca`
- **Telescope** — `<leader>ff fg fb fh`
- **Terminal Mode** — `:terminal`, `Ctrl-\ Ctrl-n`, `i`

The reference content is static — no mode tracking or app detection needed. It shows the same card every time, designed to be scanned in under a second.

## Leader-Layer Shortcuts

These shortcuts work in any macOS app while holding the Leader key:

| Key | Action |
|-----|--------|
| `h j k l` | Arrow keys (left/down/up/right) |
| `w` | Word forward (Option-Right) |
| `b` | Word back (Option-Left) |
| `e` | End of word (Option-Right) |
| `0` | Line start (Cmd-Left) |
| `$` | Line end (Cmd-Right) |
| `gg / G` | Document top/bottom |
| `/` | Find (Cmd-F) |
| `n / N` | Next/previous match |
| `y` | Yank / copy (Cmd-C) |
| `p` | Put / paste (Cmd-V) |
| `u` | Undo (Cmd-Z) |
| `r` | Redo (Cmd-Shift-Z) |
| `d` | Delete word (Option-Backspace) |
| `x` | Forward delete |
| `o / O` | Open line below/above |

## Tips

- The Neovim-specific categories (LSP, Telescope, etc.) on the right column are reference-only — they describe commands that work inside Neovim, not shortcuts that KeyPath sends. They're there so you have one place to look.
- If you use both Neovim and regular macOS apps, this collection is for you. For deeper KindaVim modal editing integration, see [Full Vim Modes](help:kindavim).
- The Leader key defaults to Space. Change it in the **Leader Key** collection in the Rules tab.

## Resources

- [Neovim documentation](https://neovim.io/doc/) ↗
- [Telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) ↗
- [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig) ↗
- [Vim Cheat Sheet](https://vim.rtorr.com/) ↗
