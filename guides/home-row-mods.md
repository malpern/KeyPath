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
  background: #f9f3ea;
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

  // Map physical keyboard keys to interactive key elements
  var keyMap = {};
  document.querySelectorAll('.hrm-key').forEach(function(key) {
    keyMap[key.dataset.letter.toLowerCase()] = key;
  });

  // Track visibility with IntersectionObserver
  var isVisible = false;
  var container = document.getElementById('hrm-interactive');
  if (window.IntersectionObserver) {
    var observer = new IntersectionObserver(function(entries) {
      isVisible = entries[0].isIntersecting;
    }, { threshold: 0.5 });
    observer.observe(container);
  } else {
    isVisible = true;
  }

  // Shared UI references
  var sym = document.getElementById('hrm-result-symbol');
  var lbl = document.getElementById('hrm-result-label');
  var prompt = document.getElementById('hrm-prompt');
  var watch = document.getElementById('hrm-stopwatch');
  var watchHand = document.getElementById('hrm-watch-hand');
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
    watchHand.style.transform = 'rotate(0deg)';
    watchHand.style.stroke = '#a5906d';
    watchCircle.style.stroke = '#a5906d';
    setTimeout(function() { prompt.style.opacity = '1'; }, 400);
  }

  function startSpin() {
    watch.style.opacity = '1';
    spinStart = Date.now();
    function spin() {
      var elapsed = Date.now() - spinStart;
      var deg = (elapsed / HOLD_MS) * 360;
      watchHand.style.transform = 'rotate(' + Math.min(deg, 360) + 'deg)';
      if (elapsed < HOLD_MS) spinFrame = requestAnimationFrame(spin);
    }
    spinFrame = requestAnimationFrame(spin);
  }

  function stopSpin(color) {
    cancelAnimationFrame(spinFrame);
    if (color) {
      watchHand.style.stroke = color;
      watchCircle.style.stroke = color;
    }
  }

  // Per-key state
  document.querySelectorAll('.hrm-key').forEach(function(key) {
    var timer = null, holdTimer = null, isHeld = false;
    var letter = key.dataset.letter;
    var mod = key.dataset.mod;
    var modname = key.dataset.modname;

    function triggerDown() {
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

    function triggerUp() {
      clearTimeout(timer);
      key.classList.remove('holding');
      if (!isHeld) {
        stopSpin(null);
        watch.style.opacity = '0';
        key.classList.add('tapped');
        showResult(letter.toLowerCase(), 'Tap ' + letter + ' = the letter ' + letter.toLowerCase(), '#3a8a3e');
      } else {
        showResult(mod + ' ' + modname, 'Hold ' + letter + ' = ' + modname + ' modifier', '#4a76a8');
      }
      holdTimer = setTimeout(function() {
        key.classList.remove('tapped', 'held');
        fadeResult();
      }, 1400);
    }

    function onDown(e) { e.preventDefault(); triggerDown(); }
    function onUp(e) { e.preventDefault(); triggerUp(); }
    function onLeave() {
      clearTimeout(timer);
      clearTimeout(holdTimer);
      key.classList.remove('tapped', 'held', 'holding');
    }

    // Store trigger functions for keyboard access
    key._triggerDown = triggerDown;
    key._triggerUp = triggerUp;

    key.addEventListener('mousedown', onDown);
    key.addEventListener('mouseup', onUp);
    key.addEventListener('mouseleave', onLeave);
    key.addEventListener('touchstart', onDown, {passive: false});
    key.addEventListener('touchend', onUp, {passive: false});
  });

  // Keyboard event handling — only when interactive demo is in view
  var activeKeys = {};
  document.addEventListener('keydown', function(e) {
    if (!isVisible) return;
    var k = e.key.toLowerCase();
    if (k === ';') k = ';';
    var el = keyMap[k];
    if (!el || activeKeys[k]) return;
    activeKeys[k] = true;
    e.preventDefault();
    el._triggerDown();
  });
  document.addEventListener('keyup', function(e) {
    if (!isVisible) return;
    var k = e.key.toLowerCase();
    if (k === ';') k = ';';
    var el = keyMap[k];
    if (!el || !activeKeys[k]) return;
    delete activeKeys[k];
    e.preventDefault();
    el._triggerUp();
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

<div id="demo-taphold" class="hrm-demo" style="border-radius:12px; padding:28px 20px 20px; margin:1rem 0; text-align:center;">
  <div style="display:flex; justify-content:center; align-items:center; gap:40px;">
    <div style="text-align:center; width:90px;">
      <div class="hrm-key demo-key" id="th-f" style="margin:0 auto;">F</div>
      <div id="th-hint" style="margin-top:12px; font-family:Georgia,serif; font-size:14px; height:20px; transition:opacity 0.3s; opacity:0;">&nbsp;</div>
    </div>
    <div style="text-align:center; width:56px;">
      <svg id="th-watch" width="44" height="48" viewBox="0 0 44 48" style="transition:opacity 0.3s; opacity:0;">
        <rect x="18" y="0" width="8" height="8" rx="3" fill="#a5906d"/>
        <circle cx="22" cy="28" r="18" fill="#faf6f0" stroke="#a5906d" stroke-width="2.5" id="th-ring"/>
        <line id="th-hand" x1="22" y1="28" x2="22" y2="14" stroke="#a5906d" stroke-width="2.5" stroke-linecap="round" style="transform-origin:22px 28px; transition:transform 0.25s linear;"/>
        <circle cx="22" cy="28" r="3" fill="#a5906d"/>
      </svg>
    </div>
    <div style="text-align:center; width:120px;">
      <div id="th-result-sym" style="font-family:-apple-system,system-ui,sans-serif; font-size:36px; font-weight:600; height:44px; line-height:44px; transition:opacity 0.3s; opacity:0;">&nbsp;</div>
      <div id="th-result-lbl" style="font-family:Georgia,serif; font-size:13px; height:18px; transition:opacity 0.3s; opacity:0;">&nbsp;</div>
    </div>
  </div>
</div>

### Opposite-hand activation

Waiting for the full timeout on every keypress would make typing feel sluggish. KeyPath has a faster way: it watches which hand presses the next key. If you press a key on the **other hand** while holding F, it resolves immediately as a modifier — no need to wait for the timer.

<div id="demo-opposite" class="hrm-demo" style="border-radius:12px; padding:28px 20px 20px; margin:1rem 0; text-align:center;">
  <div style="display:flex; justify-content:center; align-items:center; gap:24px;">
    <div style="text-align:center; width:170px;">
      <div style="font-family:Georgia,serif; font-size:13px; color:#a89878; margin-bottom:10px;">left hand</div>
      <div style="display:flex; gap:6px; justify-content:center;">
        <div class="hrm-key demo-key" id="oh-d">D</div>
        <div class="hrm-key demo-key" id="oh-f">F</div>
      </div>
      <div id="oh-hint-left" style="margin-top:12px; font-family:Georgia,serif; font-size:13px; height:18px; transition:opacity 0.3s; opacity:0;">&nbsp;</div>
    </div>
    <div style="text-align:center; width:70px;">
      <svg id="oh-watch" width="44" height="48" viewBox="0 0 44 48" style="transition:opacity 0.3s; opacity:0;">
        <rect x="18" y="0" width="8" height="8" rx="3" fill="#a5906d"/>
        <circle cx="22" cy="28" r="18" fill="#faf6f0" stroke="#a5906d" stroke-width="2.5" id="oh-ring"/>
        <line id="oh-hand" x1="22" y1="28" x2="22" y2="14" stroke="#a5906d" stroke-width="2.5" stroke-linecap="round" style="transform-origin:22px 28px; transition:transform 0.25s linear;"/>
        <circle cx="22" cy="28" r="3" fill="#a5906d"/>
      </svg>
      <div id="oh-status" style="font-family:Georgia,serif; font-size:12px; font-weight:600; height:18px; margin-top:8px; transition:opacity 0.3s; opacity:0;">&nbsp;</div>
    </div>
    <div style="text-align:center; width:170px;">
      <div style="font-family:Georgia,serif; font-size:13px; color:#a89878; margin-bottom:10px;">right hand</div>
      <div style="display:flex; gap:6px; justify-content:center;">
        <div class="hrm-key demo-key" id="oh-j">J</div>
        <div class="hrm-key demo-key" id="oh-k">K</div>
      </div>
      <div id="oh-hint-right" style="margin-top:12px; font-family:Georgia,serif; font-size:13px; height:18px; transition:opacity 0.3s; opacity:0;">&nbsp;</div>
    </div>
  </div>
  <div style="margin-top:16px; height:60px;">
    <div id="oh-result-sym" style="font-family:-apple-system,system-ui,sans-serif; font-size:36px; font-weight:600; height:44px; line-height:44px; transition:opacity 0.3s; opacity:0;">&nbsp;</div>
    <div id="oh-result-lbl" style="font-family:Georgia,serif; font-size:13px; height:16px; transition:opacity 0.3s; opacity:0;">&nbsp;</div>
  </div>
</div>

<style>
.demo-key {
  width:72px; height:72px;
  background:#f5ede2;
  border:2px solid #bfad92;
  border-radius:10px;
  display:flex; align-items:center; justify-content:center;
  font-family:-apple-system,system-ui,Helvetica,sans-serif;
  font-size:28px; font-weight:500; color:#50402e;
  pointer-events:none;
  transition: transform 0.2s ease, box-shadow 0.2s ease, background 0.3s ease, border-color 0.3s ease, color 0.3s ease, opacity 0.3s ease;
  box-shadow: 0 3px 0 #c8b99e, 0 4px 8px rgba(100,80,50,0.08);
}
.demo-key.pressed {
  transform: translateY(3px);
  box-shadow: 0 1px 0 #c8b99e;
  background: #ede5d8;
  border-color: #a89478;
}
.demo-key.tap-resolved {
  transform: translateY(1px);
  box-shadow: 0 2px 0 #c8b99e;
  background: #eaf5eb;
  border-color: #7bbe7f;
  color: #3a8a3e;
}
.demo-key.hold-resolved {
  transform: translateY(3px);
  box-shadow: 0 0 0 transparent;
  background: #e6eef7;
  border-color: #7ba3cc;
  color: #4a76a8;
}
.demo-key.faded {
  opacity: 0.35;
}
</style>

<script>
(function() {
  // Helper: set text + fade in via opacity (no layout shift)
  function setText(el, text, color) {
    el.textContent = text;
    if (color) el.style.color = color;
    el.style.opacity = '1';
  }
  function hideEl(el) { el.style.opacity = '0'; }

  // === DEMO 1: Tap vs Hold ===
  var thF = document.getElementById('th-f');
  var thWatch = document.getElementById('th-watch');
  var thHand = document.getElementById('th-hand');
  var thRing = document.getElementById('th-ring');
  var thHint = document.getElementById('th-hint');
  var thSym = document.getElementById('th-result-sym');
  var thLbl = document.getElementById('th-result-lbl');

  function thReset() {
    thF.className = 'hrm-key demo-key'; thF.textContent = 'F';
    thWatch.style.opacity = '0';
    thHand.style.transition = 'none'; thHand.style.transform = 'rotate(0deg)';
    void thHand.offsetWidth;
    thHand.style.transition = 'transform 0.3s linear';
    thHand.style.stroke = '#a5906d'; thRing.style.stroke = '#a5906d';
    hideEl(thHint); hideEl(thSym); hideEl(thLbl);
  }

  var thSteps = [
    // === Tap scenario ===
    { t:0,    fn: thReset },
    { t:1200, fn: function() {
      thF.classList.add('pressed');
      setText(thHint, 'tap', '#5078a8');
      thWatch.style.opacity = '1';
    }},
    { t:1700, fn: function() {
      thHand.style.transform = 'rotate(40deg)';
    }},
    { t:2000, fn: function() {
      thF.classList.remove('pressed');
      thF.classList.add('tap-resolved');
      thRing.style.stroke = '#50a854'; thHand.style.stroke = '#50a854';
      hideEl(thHint);
      setText(thSym, 'f', '#3a8a3e');
      setText(thLbl, 'the letter', '#3a8a3e');
    }},
    { t:4800, fn: function() {
      hideEl(thSym); hideEl(thLbl);
      thWatch.style.opacity = '0';
    }},
    { t:5400, fn: thReset },
    // === Hold scenario ===
    { t:6200, fn: function() {
      thF.classList.add('pressed');
      setText(thHint, 'hold', '#b98d32');
      thWatch.style.opacity = '1';
    }},
    { t:6800,  fn: function() { thHand.style.transform = 'rotate(72deg)'; }},
    { t:7400,  fn: function() { thHand.style.transform = 'rotate(144deg)'; }},
    { t:8000,  fn: function() { thHand.style.transform = 'rotate(216deg)'; }},
    { t:8600,  fn: function() { thHand.style.transform = 'rotate(288deg)'; }},
    { t:9200,  fn: function() {
      thHand.style.transform = 'rotate(360deg)';
      thF.classList.remove('pressed');
      thF.classList.add('hold-resolved');
      thRing.style.stroke = '#4a76a8'; thHand.style.stroke = '#4a76a8';
      hideEl(thHint);
      setText(thSym, '⌘', '#4a76a8');
      setText(thLbl, 'Command modifier', '#4a76a8');
    }},
    { t:12200, fn: function() {
      hideEl(thSym); hideEl(thLbl);
      thWatch.style.opacity = '0';
    }},
    { t:12800, fn: thReset },
  ];
  var TH_LOOP = 14000;

  // === DEMO 2: Opposite Hand ===
  var ohD = document.getElementById('oh-d');
  var ohF = document.getElementById('oh-f');
  var ohJ = document.getElementById('oh-j');
  var ohK = document.getElementById('oh-k');
  var ohWatch = document.getElementById('oh-watch');
  var ohHand = document.getElementById('oh-hand');
  var ohRing = document.getElementById('oh-ring');
  var ohHintL = document.getElementById('oh-hint-left');
  var ohHintR = document.getElementById('oh-hint-right');
  var ohStatus = document.getElementById('oh-status');
  var ohSym = document.getElementById('oh-result-sym');
  var ohLbl = document.getElementById('oh-result-lbl');

  function ohReset() {
    [ohD, ohF, ohJ, ohK].forEach(function(k) { k.className = 'hrm-key demo-key'; });
    ohWatch.style.opacity = '0';
    ohHand.style.transition = 'none'; ohHand.style.transform = 'rotate(0deg)';
    void ohHand.offsetWidth;
    ohHand.style.transition = 'transform 0.3s linear';
    ohHand.style.stroke = '#a5906d'; ohRing.style.stroke = '#a5906d'; ohRing.style.fill = '#faf6f0';
    hideEl(ohHintL); hideEl(ohHintR); hideEl(ohStatus);
    hideEl(ohSym); hideEl(ohLbl);
  }

  var ohSteps = [
    // === Scenario 1: F held + J (other hand) → ⌘J ===
    { t:0,    fn: ohReset },
    { t:1200, fn: function() {
      ohF.classList.add('pressed');
      setText(ohHintL, 'hold', '#b98d32');
      ohWatch.style.opacity = '1';
      setText(ohStatus, 'waiting...', '#b98d32');
    }},
    { t:1800, fn: function() { ohHand.style.transform = 'rotate(60deg)'; }},
    { t:2400, fn: function() { ohHand.style.transform = 'rotate(120deg)'; }},
    // J pressed — short circuit
    { t:3000, fn: function() {
      ohJ.classList.add('pressed');
      setText(ohHintR, 'tap', '#5078a8');
    }},
    { t:3500, fn: function() {
      ohRing.style.stroke = '#4a76a8'; ohRing.style.fill = '#dae8f5';
      ohHand.style.stroke = '#4a76a8';
      setText(ohStatus, 'other hand — instant!', '#4a76a8');
    }},
    { t:3900, fn: function() {
      ohRing.style.fill = '#faf6f0';
      ohF.classList.remove('pressed'); ohF.classList.add('hold-resolved');
      ohJ.classList.remove('pressed'); ohJ.classList.add('tap-resolved');
      hideEl(ohHintL); hideEl(ohHintR);
      setText(ohSym, '⌘J', '#4a76a8');
      setText(ohLbl, 'Command + J', '#4a76a8');
    }},
    { t:6800, fn: function() {
      hideEl(ohSym); hideEl(ohLbl); hideEl(ohStatus);
      ohWatch.style.opacity = '0';
    }},
    { t:7400, fn: ohReset },
    // === Scenario 2: F held + D (same hand) → fd ===
    { t:8400, fn: function() {
      ohF.classList.add('pressed');
      setText(ohHintL, 'hold', '#b98d32');
      ohWatch.style.opacity = '1';
      setText(ohStatus, 'waiting...', '#b98d32');
    }},
    { t:9000, fn: function() { ohHand.style.transform = 'rotate(50deg)'; }},
    { t:9600, fn: function() { ohHand.style.transform = 'rotate(100deg)'; }},
    // D pressed — same hand
    { t:10200, fn: function() {
      ohD.classList.add('pressed');
      setText(ohHintL, 'tap + tap', '#5078a8');
    }},
    { t:10700, fn: function() {
      ohRing.style.stroke = '#50a854'; ohRing.style.fill = '#e2f2e3';
      ohHand.style.stroke = '#50a854';
      setText(ohStatus, 'same hand — letters!', '#3a8a3e');
    }},
    { t:11100, fn: function() {
      ohRing.style.fill = '#faf6f0';
      ohF.classList.remove('pressed'); ohF.classList.add('tap-resolved');
      ohD.classList.remove('pressed'); ohD.classList.add('tap-resolved');
      ohJ.classList.add('faded'); ohK.classList.add('faded');
      hideEl(ohHintL);
      setText(ohSym, 'fd', '#3a8a3e');
      setText(ohLbl, 'just the letters', '#3a8a3e');
    }},
    { t:14000, fn: function() {
      hideEl(ohSym); hideEl(ohLbl); hideEl(ohStatus);
      ohWatch.style.opacity = '0';
    }},
    { t:14600, fn: ohReset },
  ];
  var OH_LOOP = 16000;

  // Auto-play with IntersectionObserver
  function runTimeline(steps, loopMs, container) {
    var timers = [], running = false;
    function start() {
      if (running) return;
      running = true;
      (function loop() {
        timers.forEach(clearTimeout); timers = [];
        steps.forEach(function(s) { timers.push(setTimeout(s.fn, s.t)); });
        timers.push(setTimeout(loop, loopMs));
      })();
    }
    function stop() {
      running = false;
      timers.forEach(clearTimeout); timers = [];
    }
    if (window.IntersectionObserver) {
      new IntersectionObserver(function(e) {
        if (e[0].isIntersecting) start(); else stop();
      }, { threshold: 0.3 }).observe(container);
    } else { start(); }
  }

  // Transition setup for stopwatch rings
  [thRing, ohRing].forEach(function(r) { r.style.transition = 'stroke 0.25s, fill 0.25s'; });

  runTimeline(thSteps, TH_LOOP, document.getElementById('demo-taphold'));
  runTimeline(ohSteps, OH_LOOP, document.getElementById('demo-opposite'));
})();
</script>

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
