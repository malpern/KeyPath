---
layout: default
title: "Shortcuts Without Reaching"
description: "Turn your home row keys into modifiers — the most popular advanced keyboard technique"
theme: parchment
header_image: header-home-row-mods.png
permalink: /guides/home-row-mods/
---


# Shortcuts Without Reaching

Every keyboard shortcut on your Mac requires a modifier — Command, Shift, Control, Option. Those keys are tucked into the bottom corners of your keyboard, forcing your fingers off the home row dozens of times an hour. Over a full workday, that's thousands of small reaches that slow you down and strain your hands.

Home row mods fix this by putting modifiers right under your fingertips. Tap a key normally and you get the letter. Hold it briefly and it becomes a modifier. Your hands never move — every shortcut is one fluid motion from the home row.

If you're new to keyboard customization, read [Keyboard Concepts]({{ '/guides/concepts/' | relative_url }}) first for background on dual-role keys and layers.

---

## What are home row mods?

Every home row key gets a second job — tap for the letter, hold for a modifier. The layout is mirrored so both hands get the same modifiers:

![Home row mod layout — tap for letter, hold for modifier]({{ '/images/help/diagram-home-row-layout.png' | relative_url }})

The result: any keyboard shortcut is one fluid motion. Hold F + press C = ⌘C (Copy). Hold A + press Tab = ⇧Tab (Shift-Tab). No reaching, no contortion.

<div id="hrm-interactive" style="border-radius:16px; padding:32px 20px 24px; margin:1.5rem 0; user-select:none; -webkit-user-select:none;">
  <p id="hrm-prompt" style="text-align:center; margin:0 0 24px; font-family:Georgia,serif; font-size:16px; color:#a08e74; letter-spacing:0.01em;">
    <span style="opacity:0.7;">Try it</span> — click and release quickly, or click and hold
  </p>
  <div style="display:flex; justify-content:center; align-items:flex-start; gap:32px;">
    <div style="text-align:center;">
      <div style="font-family:Georgia,serif; font-size:14px; color:#a89878; margin-bottom:10px;">left hand</div>
      <div style="display:flex; gap:8px;">
        <div class="hrm-key" data-letter="A" data-mod="⇧" data-modname="Shift"></div>
        <div class="hrm-key" data-letter="S" data-mod="⌃" data-modname="Control"></div>
        <div class="hrm-key" data-letter="D" data-mod="⌥" data-modname="Option"></div>
        <div class="hrm-key" data-letter="F" data-mod="⌘" data-modname="Command"></div>
      </div>
    </div>
    <div style="text-align:center;">
      <div style="font-family:Georgia,serif; font-size:14px; color:#a89878; margin-bottom:10px;">right hand</div>
      <div style="display:flex; gap:8px;">
        <div class="hrm-key" data-letter="J" data-mod="⌘" data-modname="Command"></div>
        <div class="hrm-key" data-letter="K" data-mod="⌥" data-modname="Option"></div>
        <div class="hrm-key" data-letter="L" data-mod="⌃" data-modname="Control"></div>
        <div class="hrm-key" data-letter=";" data-mod="⇧" data-modname="Shift"></div>
      </div>
    </div>
  </div>
  <div id="hrm-result" style="text-align:center; margin-top:24px; min-height:80px; display:flex; flex-direction:column; align-items:center;">
    <svg id="hrm-stopwatch" width="44" height="44" viewBox="0 0 44 44" style="opacity:0; transition:opacity 0.15s; margin-bottom:6px;">
      <circle cx="22" cy="24" r="18" fill="#faf6f0" stroke="#a5906d" stroke-width="2"/>
      <rect x="20" y="2" width="4" height="8" rx="2" fill="#a5906d"/>
      <line id="hrm-watch-hand" x1="22" y1="24" x2="22" y2="10" stroke="#a5906d" stroke-width="2" stroke-linecap="round" transform-origin="22 24"/>
      <circle cx="22" cy="24" r="2.5" fill="#a5906d"/>
    </svg>
    <div id="hrm-result-symbol" style="font-size:36px; font-family:-apple-system,system-ui,sans-serif; font-weight:600; line-height:1.2; opacity:0; transition:opacity 0.2s;"></div>
    <div id="hrm-result-label" style="font-size:15px; font-family:Georgia,serif; margin-top:4px; opacity:0; transition:opacity 0.2s;"></div>
  </div>
</div>

<style>
.hrm-key {
  width:80px; height:80px;
  background:#f5ede2;
  border:2px solid #bfad92;
  border-radius:11px;
  cursor:pointer;
  position:relative;
  display:flex; align-items:center; justify-content:center;
  transition: transform 0.12s ease, box-shadow 0.12s ease, background 0.2s ease, border-color 0.2s ease;
  box-shadow: 0 4px 0 #c8b99e, 0 5px 10px rgba(100,80,50,0.08);
}
.hrm-key::before {
  content: attr(data-letter);
  font-family: -apple-system, system-ui, Helvetica, Arial, sans-serif;
  font-size: 32px;
  font-weight: 500;
  color: #50402e;
  transition: opacity 0.2s, transform 0.2s;
}
/* Gentle nudge animation — one key at a time, staggered */
.hrm-key:nth-child(1) { animation: hrm-nudge 4s ease-in-out 0.0s infinite; }
.hrm-key:nth-child(2) { animation: hrm-nudge 4s ease-in-out 0.5s infinite; }
.hrm-key:nth-child(3) { animation: hrm-nudge 4s ease-in-out 1.0s infinite; }
.hrm-key:nth-child(4) { animation: hrm-nudge 4s ease-in-out 1.5s infinite; }
@keyframes hrm-nudge {
  0%, 85%, 100% { transform: translateY(0); }
  90% { transform: translateY(-3px); }
  95% { transform: translateY(0); }
}
/* Hover: warm lift, letter stays fully visible */
.hrm-key:hover {
  animation: none !important;
  transform: translateY(-2px);
  box-shadow: 0 6px 0 #c8b99e, 0 8px 16px rgba(100,80,50,0.12);
  border-color: #a89478;
}
/* Tap: press down, green tint, letter pops */
.hrm-key.tapped {
  animation: none !important;
  transform: translateY(3px);
  box-shadow: 0 1px 0 #c8b99e;
  background: #eaf5eb;
  border-color: #7bbe7f;
}
.hrm-key.tapped::before {
  color: #3a8a3e;
  transform: scale(1.12);
}
/* Hold: press deep, blue tint, letter fades, modifier appears */
.hrm-key.holding {
  animation: none !important;
  transform: translateY(3px);
  box-shadow: 0 1px 0 #c8b99e;
  background: #f5ede2;
  border-color: #bfad92;
}
.hrm-key.holding::before {
  opacity: 0.35;
}
.hrm-key.held {
  animation: none !important;
  transform: translateY(4px);
  box-shadow: 0 0 0 transparent;
  background: #e6eef7;
  border-color: #7ba3cc;
}
.hrm-key.held::before {
  opacity: 0;
}
.hrm-key .hrm-mod-overlay {
  position: absolute;
  font-family: -apple-system, system-ui, sans-serif;
  font-size: 28px;
  color: #4a76a8;
  opacity: 0;
  transform: scale(0.7);
  transition: opacity 0.2s, transform 0.2s;
  pointer-events: none;
}
.hrm-key.held .hrm-mod-overlay {
  opacity: 1;
  transform: scale(1);
}
</style>

<script>
(function() {
  var HOLD_MS = 350;
  // Add modifier overlay span inside each key
  document.querySelectorAll('.hrm-key').forEach(function(key) {
    var overlay = document.createElement('span');
    overlay.className = 'hrm-mod-overlay';
    overlay.textContent = key.dataset.mod;
    key.appendChild(overlay);
  });

  document.querySelectorAll('.hrm-key').forEach(function(key) {
    var timer = null, holdTimer = null, isHeld = false;
    var letter = key.dataset.letter;
    var mod = key.dataset.mod;
    var modname = key.dataset.modname;
    var sym = document.getElementById('hrm-result-symbol');
    var lbl = document.getElementById('hrm-result-label');
    var prompt = document.getElementById('hrm-prompt');
    var watch = document.getElementById('hrm-stopwatch');
    var hand = document.getElementById('hrm-watch-hand');
    var watchCircle = watch.querySelector('circle');
    var spinFrame = null, spinStart = 0;

    function showResult(symbol, label, color) {
      sym.style.color = color;
      sym.textContent = symbol;
      sym.style.opacity = '1';
      lbl.style.color = color;
      lbl.textContent = label;
      lbl.style.opacity = '1';
      prompt.style.opacity = '0.3';
    }

    function fadeResult() {
      sym.style.opacity = '0';
      lbl.style.opacity = '0';
      watch.style.opacity = '0';
      hand.style.transform = 'rotate(0deg)';
      hand.style.stroke = '#a5906d';
      watchCircle.style.stroke = '#a5906d';
      setTimeout(function() { prompt.style.opacity = '1'; }, 400);
    }

    function startSpin() {
      watch.style.opacity = '1';
      spinStart = Date.now();
      function spin() {
        var elapsed = Date.now() - spinStart;
        var deg = (elapsed / HOLD_MS) * 360;
        hand.style.transform = 'rotate(' + Math.min(deg, 360) + 'deg)';
        if (elapsed < HOLD_MS) spinFrame = requestAnimationFrame(spin);
      }
      spinFrame = requestAnimationFrame(spin);
    }

    function stopSpin(color) {
      cancelAnimationFrame(spinFrame);
      if (color) {
        hand.style.stroke = color;
        watchCircle.style.stroke = color;
      }
    }

    function onDown(e) {
      e.preventDefault();
      isHeld = false;
      key.classList.remove('tapped', 'held', 'holding');
      fadeResult();
      key.classList.add('holding');
      startSpin();
      timer = setTimeout(function() {
        isHeld = true;
        key.classList.remove('holding');
        key.classList.add('held');
        stopSpin('#4a76a8');
        showResult(mod + ' ' + modname, 'Hold ' + letter + ' = ' + modname + ' modifier', '#4a76a8');
      }, HOLD_MS);
    }

    function onUp(e) {
      e.preventDefault();
      clearTimeout(timer);
      stopSpin(null);
      key.classList.remove('holding');
      if (!isHeld) {
        watch.style.opacity = '0';
        key.classList.add('tapped');
        showResult(letter.toLowerCase(), 'Tap ' + letter + ' = the letter ' + letter.toLowerCase(), '#3a8a3e');
      }
      holdTimer = setTimeout(function() {
        key.classList.remove('tapped', 'held');
        fadeResult();
      }, 1400);
    }

    function onLeave() {
      clearTimeout(timer);
      clearTimeout(holdTimer);
      key.classList.remove('tapped', 'held', 'holding');
    }

    key.addEventListener('mousedown', onDown);
    key.addEventListener('mouseup', onUp);
    key.addEventListener('mouseleave', onLeave);
    key.addEventListener('touchstart', onDown, {passive: false});
    key.addEventListener('touchend', onUp, {passive: false});
  });
})();
</script>

---

## Getting started

1. Open KeyPath and click the gear icon to open the inspector panel
2. Go to the **Custom Rules** tab
3. Enable the **Home Row Mods** pre-built rule
4. Start typing normally

![Screenshot — Home Row Mods pack detail in KeyPath]({{ '/images/help/pack-detail-home-row-mods.png' | relative_url }})

The defaults are tuned to feel natural right away. KeyPath automatically detects same-hand typing rolls (like "fd" or "jk") and treats them as letters, not modifiers. It also suppresses modifiers during fast typing bursts. These protections mean misfires are rare out of the box — most users don't need to change any settings.

**Tip:** Start by using home row mods only for shortcuts you already know (⌘C, ⌘V, ⌘Z). Once those feel natural, expand to new shortcuts.

---

## Advanced settings

Once you're comfortable with the defaults, these settings let you fine-tune how home row mods feel. Open the Home Row Mods rule's settings to access these controls.

### Typing Feel

KeyPath provides a slider to adjust the tap-hold threshold:


![Screenshot]({{ '/images/help/hrm-typing-feel-slider.png' | relative_url }})

- Slide toward **"More Letters"** for a longer tap window (fewer accidental modifiers)
- Slide toward **"More Modifiers"** for quicker modifier activation

*Start with defaults, then adjust one parameter at a time.*

### How tap-hold works

When you press a home row key, KeyPath watches how long you hold it. A quick tap produces the letter. A long press activates the modifier. The timing threshold is adjustable — see [Typing Feel](#typing-feel) below.

<video autoplay loop muted playsinline style="max-width: 100%; border-radius: 10px;">
  <source src="{{ '/images/help/video-tap-hold.mp4' | relative_url }}" type="video/mp4">
</video>

### Opposite-hand activation

Waiting for the full timeout on every keypress would make typing feel sluggish. KeyPath has a faster way: it watches which hand presses the next key. If you press a key on the **other hand** while holding F, it resolves immediately as a modifier — no need to wait for the timer.

<video autoplay loop muted playsinline style="max-width: 100%; border-radius: 10px;">
  <source src="{{ '/images/help/video-opposite-hand.mp4' | relative_url }}" type="video/mp4">
</video>

This is enabled by default (**On Press**). The picker offers three modes:

- **Off** — Any key press can trigger the hold action (classic tap-hold behavior)
- **On Press** — Hold triggers when the other hand *presses* a key. Faster response, may misfire on fast same-hand rolls.
- **On Release** — Hold triggers when the other-hand key is *released*. More forgiving for fast typists.

### Fast typing protection

When you're typing quickly, the last thing you want is for "fd" to become Ctrl+D. Fast typing protection solves this: keys pressed shortly after your last keystroke produce the letter immediately — no hold detection, no waiting state.


![Screenshot]({{ '/images/help/hrm-fast-typing.png' | relative_url }})

This is enabled by default at 150ms. Adjust the slider to match your typing speed — faster typists may want a lower value (strict), while slower typists can use a higher value (forgiving).

### Per-finger sensitivity

Pinkies are slower than index fingers. KeyPath lets you add extra tolerance for slower fingers to prevent accidental holds:


![Screenshot]({{ '/images/help/hrm-per-finger-sliders.png' | relative_url }})

### Quick tap

When enabled, a quick tap-and-release always produces the letter, even if another key was pressed during the tap window. This is especially helpful for fast typists who sometimes roll keys.

### Raw values

Click **# Raw values** in the timing header to see and edit the exact millisecond values for tap window and hold delay. Useful for precise tuning or matching values from a community config.

---

## Expert techniques

These are techniques being explored in the mechanical keyboard community. Some are in KeyPath today, others are planned or available through custom Kanata config.

### Anti-cascade / nomods layer

After a tap resolves, temporarily disable all home row mods for the rest of the typing burst, re-enabling them after a brief idle. This prevents chain-reaction misfires.

Pioneered by [Sunaku's home row mods configuration](https://sunaku.github.io/home-row-mods.html), which implements this via a dedicated "nomods" layer in Kanata.

### Typing streak detection

Track sustained typing bursts and suppress modifier activation entirely during the streak. Only re-enable modifiers after a pause. This eliminates nearly all misfires during fast prose typing.

See [Sunaku's bilateral combinations approach](https://sunaku.github.io/home-row-mods.html) for a detailed implementation.

### Achordion / Chordal Hold

QMK firmware libraries (created by [Pascal Getreuer](https://getreuer.info/posts/keyboards/home-row-mods/)) that make the tap/hold decision based on which hand pressed the next key. **Chordal Hold** was merged into QMK core in February 2025, making opposite-hand detection a built-in feature for QMK keyboards.

KeyPath's opposite-hand activation provides equivalent functionality for standard Mac keyboards via Kanata.

### Eager mods

Apply the modifier immediately while the tap-hold decision is still pending. If the key resolves as a tap, the modifier is retroactively canceled. This reduces perceived latency for intentional modifier use.

Kanata supports eager mode via `tap-hold-press` and `tap-hold-release` variants. See the [Kanata tap-hold documentation](https://github.com/jtroo/kanata/blob/main/docs/config.adoc#tap-hold) for details.

### Shift exemption

Shift is the most frequently used modifier during normal typing (capital letters, punctuation). Advanced configurations exempt Shift from streak suppression and anti-cascade so capitalization works naturally during fast typing, while still suppressing accidental Control, Option, and Command.

---

**Switching from Karabiner?** See the [From Karabiner-Elements guide]({{ '/migration/karabiner-users/' | relative_url }}) for a detailed comparison of how home row mods work in both tools.

---

## Resources

### KeyPath guides

- **[Keyboard Concepts]({{ '/guides/concepts/' | relative_url }})** — Background on tap-hold, layers, and modifiers
- **[One Key, Multiple Actions]({{ '/guides/tap-hold/' | relative_url }})** — Detailed guide to all tap-hold options in KeyPath
- **[What You Can Build]({{ '/guides/use-cases/' | relative_url }})** — See HRM as part of a complete setup with Hyper key, window tiling, and more
- **[Alternative Layouts]({{ '/guides/alternative-layouts/' | relative_url }})** — HRM works with any layout — see what's supported
- **[Keyboard Layouts]({{ '/guides/keyboard-layouts/' | relative_url }})** — Split keyboards and HRM are a natural match
- **[Switching from Karabiner?]({{ '/migration/karabiner-users/' | relative_url }})** — See how KeyPath's HRM compares to Karabiner's approach
- **[Back to Docs](https://malpern.github.io/KeyPath/docs)**

### External references

- **[The Home Row Mods Guide (Precondition)](https://precondition.github.io/home-row-mods)** — The definitive community reference on HRM layouts and tuning ↗
- **[Pascal Getreuer's home row mods analysis](https://getreuer.info/posts/keyboards/home-row-mods/)** — Technical deep dive on timing, anti-misfire, and Chordal Hold ↗
- **[Sunaku's home row mods](https://sunaku.github.io/home-row-mods.html)** — Advanced anti-cascade and bilateral combinations ↗
- **[Kanata tap-hold documentation](https://github.com/jtroo/kanata/blob/main/docs/config.adoc#tap-hold)** — Full reference for the engine behind KeyPath's tap-hold ↗
- **[jtroo's Kanata config](https://github.com/jtroo/kanata/blob/main/cfg_samples/jtroo.kbd)** — Real-world advanced config from Kanata's creator ↗
- **[QMK Chordal Hold](https://docs.qmk.fm/features/chordal_hold)** — Firmware-level opposite-hand detection (same concept KeyPath uses) ↗
- **[r/ErgoMechKeyboards](https://www.reddit.com/r/ErgoMechKeyboards/)** — Active community discussing HRM tuning and experiences ↗
- **[Ben Vallack's HRM journey](https://www.youtube.com/@BenVallack)** — Practical experiences with home row mods on various layouts ↗
