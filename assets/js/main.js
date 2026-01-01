// KeyPath Documentation - Main JavaScript

(function() {
    'use strict';
    
    // Smooth scrolling for anchor links
    document.querySelectorAll('a[href^="#"]').forEach(anchor => {
        anchor.addEventListener('click', function (e) {
            const href = this.getAttribute('href');
            if (href === '#') return;
            
            const target = document.querySelector(href);
            if (target) {
                e.preventDefault();
                target.scrollIntoView({
                    behavior: 'smooth',
                    block: 'start'
                });
            }
        });
    });
    
    // Mobile menu toggle (if needed in future)
    const mobileMenuToggle = document.querySelector('.mobile-menu-toggle');
    if (mobileMenuToggle) {
        mobileMenuToggle.addEventListener('click', function() {
            document.body.classList.toggle('mobile-menu-open');
        });
    }

    // Visualization Toggle (Timeline / Piano Roll)
    const vizToggleBtns = document.querySelectorAll('.viz-toggle-btn');
    if (vizToggleBtns.length > 0) {
        vizToggleBtns.forEach(btn => {
            btn.addEventListener('click', function() {
                const target = this.dataset.vizTarget;

                // Update buttons
                vizToggleBtns.forEach(b => {
                    b.classList.remove('active');
                    b.setAttribute('aria-selected', 'false');
                });
                this.classList.add('active');
                this.setAttribute('aria-selected', 'true');

                // Update panels
                document.querySelectorAll('.viz-panel').forEach(panel => {
                    panel.classList.remove('active');
                });
                const targetPanel = document.getElementById('viz-' + target);
                if (targetPanel) {
                    targetPanel.classList.add('active');
                }
            });
        });
    }

    // Easter egg: Press 'p' twice to reveal Piano Roll toggle
    const vizToggle = document.querySelector('.viz-toggle-hidden');
    if (vizToggle) {
        let lastKeyTime = 0;
        let lastKey = '';

        document.addEventListener('keydown', function(e) {
            // Ignore if user is typing in an input
            if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') return;

            const now = Date.now();

            if (e.key.toLowerCase() === 'p') {
                if (lastKey === 'p' && (now - lastKeyTime) < 500) {
                    // Double-p detected - reveal the toggle
                    vizToggle.classList.add('revealed');
                    vizToggle.setAttribute('aria-hidden', 'false');
                }
                lastKey = 'p';
                lastKeyTime = now;
            } else {
                lastKey = '';
            }
        });
    }

    // Copy code block button
    // Handle both regular code blocks and Rouge-highlighted blocks (.highlight > pre > code)
    document.querySelectorAll('pre code, .highlight pre code').forEach(block => {
        const pre = block.parentElement;
        const container = pre.parentElement.classList.contains('highlight') ? pre.parentElement : pre;
        
        // Skip if button already exists
        if (container.querySelector('.copy-button')) return;
        
        const button = document.createElement('button');
        button.className = 'copy-button';
        button.textContent = 'Copy';
        button.setAttribute('aria-label', 'Copy code to clipboard');
        button.addEventListener('click', async (e) => {
            e.stopPropagation();
            try {
                await navigator.clipboard.writeText(block.textContent || block.innerText);
                button.textContent = 'Copied!';
                setTimeout(() => {
                    button.textContent = 'Copy';
                }, 2000);
            } catch (err) {
                // Fallback for older browsers
                const textArea = document.createElement('textarea');
                textArea.value = block.textContent || block.innerText;
                textArea.style.position = 'fixed';
                textArea.style.opacity = '0';
                document.body.appendChild(textArea);
                textArea.select();
                try {
                    document.execCommand('copy');
                    button.textContent = 'Copied!';
                    setTimeout(() => {
                        button.textContent = 'Copy';
                    }, 2000);
                } catch (fallbackErr) {
                    button.textContent = 'Failed';
                    setTimeout(() => {
                        button.textContent = 'Copy';
                    }, 2000);
                }
                document.body.removeChild(textArea);
            }
        });
        
        // Ensure container has relative positioning
        if (getComputedStyle(container).position === 'static') {
            container.style.position = 'relative';
        }
        container.appendChild(button);
    });


    // Docs sidebar drawer
    const sidebarToggle = document.querySelector('[data-sidebar-toggle]');
    const sidebarBackdrop = document.querySelector('[data-sidebar-backdrop]');
    const sidebar = document.getElementById('sidebar');

    const setSidebarOpen = (open) => {
        document.body.classList.toggle('sidebar-open', open);
        if (sidebarToggle) sidebarToggle.setAttribute('aria-expanded', open ? 'true' : 'false');
        if (sidebar) sidebar.setAttribute('aria-hidden', open ? 'false' : 'true');
    };

    const isSidebarOpen = () => document.body.classList.contains('sidebar-open');

    if (sidebarToggle && sidebar) {
        sidebar.setAttribute('aria-hidden', 'true');

        sidebarToggle.addEventListener('click', () => {
            setSidebarOpen(!isSidebarOpen());
        });

        if (sidebarBackdrop) {
            sidebarBackdrop.addEventListener('click', () => setSidebarOpen(false));
        }

        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape' && isSidebarOpen()) {
                setSidebarOpen(false);
            }
        });

        // Close drawer after navigation
        sidebar.querySelectorAll('a').forEach((a) => {
            a.addEventListener('click', () => setSidebarOpen(false));
        });
    }


    // Glossary popovers for common keyboard terms
    const GLOSSARY = {
        keymap: {
            title: 'Keymap',
            body: 'A list of “what each key does”. A keymap maps physical keys to actions.'
        },
        layer: {
            title: 'Layer',
            body: 'A temporary “mode” where the same keys do different things. Like holding Fn on a laptop keyboard.'
        },
        sequence: {
            title: 'Sequence',
            body: 'A set of keys pressed in order (one after another) to trigger an action.'
        },
        chord: {
            title: 'Chord',
            body: 'Two or more keys pressed at the same time to trigger an action.'
        },
        macro: {
            title: 'Macro',
            body: 'A shortcut that types or triggers multiple actions for you.'
        },
        tap_hold: {
            title: 'Tap-hold',
            body: 'Tap does one thing. Hold does another. (Example: tap = Esc, hold = Ctrl.)'
        },
        tap_dance: {
            title: 'Tap-dance',
            body: 'Tap once, twice, or more to get different actions from one key.'
        },
        home_row_mods: {
            title: 'Home-row mods',
            body: 'Modifier keys (Ctrl/Alt/Shift/Cmd) on the home row using tap-hold.'
        },
        combo: {
            title: 'Combo',
            body: 'A chord on specific keys that triggers something else.'
        },
        leader: {
            title: 'Leader key',
            body: 'A special key that starts a short command sequence. Example: Leader then L opens Slack.'
        },
        vim_motions: {
            title: 'Vim motions',
            body: 'Navigation keys from Vim (like hjkl, w, b). Great for moving around without leaving the home row.'
        }
    };

    const INFO_ICON_SVG = `
<svg viewBox="0 0 24 24" class="kp-popover-icon" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
  <circle cx="12" cy="12" r="10" />
  <path d="M12 16v-4" />
  <path d="M12 8h.01" />
</svg>`;

    const TERM_PATTERNS = [
        { key: 'keymap', re: /\bkeymaps?\b/gi },
        { key: 'layer', re: /\blayers?\b/gi },
        { key: 'sequence', re: /\bsequences?\b/gi },
        { key: 'chord', re: /\bchords?\b/gi },
        { key: 'macro', re: /\bmacros?\b/gi },
        { key: 'tap_hold', re: /\btap[ -]?hold\b/gi },
        { key: 'tap_dance', re: /\btap[ -]?dance\b/gi },
        { key: 'home_row_mods', re: /\bhome[ -]?row mods\b/gi },
        { key: 'combo', re: /\bcombos?\b/gi }
    ];

    const EXCLUDED_TAGS = new Set(['A', 'CODE', 'PRE', 'SCRIPT', 'STYLE', 'SVG', 'BUTTON', 'INPUT', 'TEXTAREA']);

    const createTermEl = (text, key) => {
        const el = document.createElement('button');
        el.type = 'button';
        el.className = 'kp-term';
        el.dataset.term = key;
        el.textContent = text;
        el.setAttribute('aria-label', `${text}. Show definition.`);
        return el;
    };

    const shouldSkipNode = (node) => {
        const p = node.parentElement;
        if (!p) return true;
        if (p.closest('.kp-popover')) return true;
        if (p.closest('pre, code')) return true;
        let cur = p;
        while (cur) {
            if (EXCLUDED_TAGS.has(cur.tagName)) return true;
            cur = cur.parentElement;
        }
        return false;
    };

    const highlightGlossaryTerms = (rootEl) => {
        const walker = document.createTreeWalker(rootEl, NodeFilter.SHOW_TEXT, {
            acceptNode: (n) => {
                if (!n.nodeValue || n.nodeValue.trim().length < 3) return NodeFilter.FILTER_REJECT;
                if (shouldSkipNode(n)) return NodeFilter.FILTER_REJECT;
                // Avoid re-processing
                if (n.parentElement && n.parentElement.classList && n.parentElement.classList.contains('kp-term')) return NodeFilter.FILTER_REJECT;
                return NodeFilter.FILTER_ACCEPT;
            }
        });

        const nodes = [];
        while (walker.nextNode()) nodes.push(walker.currentNode);

        nodes.forEach((node) => {
            let text = node.nodeValue;
            // Quick check
            let hasAny = TERM_PATTERNS.some(p => p.re.test(text));
            TERM_PATTERNS.forEach(p => { p.re.lastIndex = 0; });
            if (!hasAny) return;

            const parts = [{ type: 'text', value: text }];

            TERM_PATTERNS.forEach(({ key, re }) => {
                for (let i = 0; i < parts.length; i++) {
                    const part = parts[i];
                    if (part.type !== 'text') continue;

                    const s = part.value;
                    re.lastIndex = 0;
                    const matches = [...s.matchAll(re)];
                    if (matches.length === 0) continue;

                    const next = [];
                    let last = 0;
                    matches.forEach((m) => {
                        const start = m.index;
                        const end = start + m[0].length;
                        if (start > last) next.push({ type: 'text', value: s.slice(last, start) });
                        next.push({ type: 'term', value: m[0], key });
                        last = end;
                    });
                    if (last < s.length) next.push({ type: 'text', value: s.slice(last) });

                    parts.splice(i, 1, ...next);
                    i += next.length - 1;
                }
            });

            // If nothing changed, bail
            if (parts.length === 1 && parts[0].type === 'text') return;

            const frag = document.createDocumentFragment();
            parts.forEach((p) => {
                if (p.type === 'text') frag.appendChild(document.createTextNode(p.value));
                else frag.appendChild(createTermEl(p.value, p.key));
            });
            node.parentNode.replaceChild(frag, node);
        });
    };

    const popover = document.createElement('div');
    popover.id = 'kp-popover';
    popover.className = 'kp-popover';
    popover.setAttribute('role', 'tooltip');
    popover.setAttribute('aria-hidden', 'true');
    document.body.appendChild(popover);

    let hideTimer = null;

    const hidePopover = () => {
        popover.classList.remove('is-visible');
        popover.setAttribute('aria-hidden', 'true');
    };

    const showPopoverFor = (termEl) => {
        const key = termEl.dataset.term;
        const entry = GLOSSARY[key];
        if (!entry) return;

        popover.innerHTML = `
  <div class="kp-popover-header">${INFO_ICON_SVG}<div class="kp-popover-title">${entry.title}</div></div>
  <div class="kp-popover-body">${entry.body}</div>
`;

        const rect = termEl.getBoundingClientRect();
        // Ensure it has layout before positioning
        popover.style.left = '0px';
        popover.style.top = '0px';        popover.classList.add('is-visible');
        popover.setAttribute('aria-hidden', 'false');

        const pop = popover.getBoundingClientRect();
        const padding = 12;
        const preferredTop = rect.bottom + 10;
        const top = Math.min(
            Math.max(padding, preferredTop),
            window.innerHeight - pop.height - padding
        );
        const left = Math.min(
            Math.max(padding, rect.left + rect.width / 2 - pop.width / 2),
            window.innerWidth - pop.width - padding
        );

        popover.style.left = `${Math.round(left)}px`;
        popover.style.top = `${Math.round(top)}px`;
    };

    const attachPopoverHandlers = () => {
        document.querySelectorAll('.kp-term').forEach((el) => {
            el.addEventListener('mouseenter', () => {
                if (hideTimer) clearTimeout(hideTimer);
                showPopoverFor(el);
            });
            el.addEventListener('mouseleave', () => {
                hideTimer = setTimeout(hidePopover, 120);
            });
            el.addEventListener('focus', () => {
                if (hideTimer) clearTimeout(hideTimer);
                showPopoverFor(el);
            });
            el.addEventListener('blur', () => {
                hideTimer = setTimeout(hidePopover, 120);
            });
            el.addEventListener('click', (e) => {
                // Toggle on click (helps trackpads/touch)
                e.stopPropagation();
                const visible = popover.classList.contains('is-visible');
                if (visible) hidePopover();
                else showPopoverFor(el);
            });
        });

        popover.addEventListener('mouseenter', () => {
            if (hideTimer) clearTimeout(hideTimer);
        });
        popover.addEventListener('mouseleave', () => {
            hideTimer = setTimeout(hidePopover, 120);
        });

        document.addEventListener('click', (e) => {
            if (popover.contains(e.target)) return;
            if (e.target && e.target.classList && e.target.classList.contains('kp-term')) return;
            hidePopover();
        });

        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape') hidePopover();
        });

        window.addEventListener('scroll', () => {
            if (popover.classList.contains('is-visible')) hidePopover();
        }, { passive: true });
    };

    // Apply to main article content
    document.querySelectorAll('.content').forEach((content) => {
        highlightGlossaryTerms(content);
    });
    attachPopoverHandlers();

    // Timeline visualization scroll animations
    const timelineCards = document.querySelectorAll('.kanata-card[data-viz]');
    if (timelineCards.length > 0) {
        const observerOptions = {
            root: null,
            rootMargin: '0px 0px -10% 0px',
            threshold: 0.3
        };

        const cardObserver = new IntersectionObserver((entries) => {
            entries.forEach(entry => {
                if (entry.isIntersecting) {
                    entry.target.classList.add('in-view');
                }
            });
        }, observerOptions);

        timelineCards.forEach(card => {
            cardObserver.observe(card);
        });

        // Replay animation on hover
        timelineCards.forEach(card => {
            card.addEventListener('mouseenter', () => {
                // Only replay if already viewed
                if (card.classList.contains('in-view')) {
                    card.classList.remove('in-view');
                    // Force reflow
                    void card.offsetWidth;
                    card.classList.add('in-view');
                }
            });
        });
    }

    // Piano Roll visualization scroll animations
    const pianoRollCards = document.querySelectorAll('.pr-card[data-pr]');
    if (pianoRollCards.length > 0) {
        const prObserverOptions = {
            root: null,
            rootMargin: '0px 0px -10% 0px',
            threshold: 0.3
        };

        const prCardObserver = new IntersectionObserver((entries) => {
            entries.forEach(entry => {
                if (entry.isIntersecting) {
                    entry.target.classList.add('in-view');
                }
            });
        }, prObserverOptions);

        pianoRollCards.forEach(card => {
            prCardObserver.observe(card);
        });

        // Replay animation on hover
        pianoRollCards.forEach(card => {
            card.addEventListener('mouseenter', () => {
                // Only replay if already viewed
                if (card.classList.contains('in-view')) {
                    card.classList.remove('in-view');
                    // Force reflow
                    void card.offsetWidth;
                    card.classList.add('in-view');
                }
            });
        });
    }

    // =========================================
    // DESIGN #3: Recipe Cards
    // =========================================
    const recipeCards = document.querySelectorAll('.recipe-card[data-recipe]');
    if (recipeCards.length > 0) {
        const recipeObserver = new IntersectionObserver((entries) => {
            entries.forEach(entry => {
                if (entry.isIntersecting) {
                    entry.target.classList.add('in-view');
                }
            });
        }, { threshold: 0.1 });

        recipeCards.forEach(card => {
            recipeObserver.observe(card);
        });

        // Replay animation on hover
        recipeCards.forEach(card => {
            card.addEventListener('mouseenter', () => {
                if (card.classList.contains('in-view')) {
                    card.classList.remove('in-view');
                    void card.offsetWidth;
                    card.classList.add('in-view');
                }
            });
        });
    }

    // =========================================
    // DESIGN #4: Comic Panels
    // =========================================
    const comicStrips = document.querySelectorAll('.comic-strip[data-comic]');
    if (comicStrips.length > 0) {
        const comicObserver = new IntersectionObserver((entries) => {
            entries.forEach(entry => {
                if (entry.isIntersecting) {
                    const panels = entry.target.querySelectorAll('.panel');
                    panels.forEach((panel, index) => {
                        setTimeout(() => {
                            panel.classList.add('in-view');
                        }, index * 200);
                    });

                    // Trigger SFX pop after panels
                    const sfx = entry.target.querySelectorAll('.sfx');
                    sfx.forEach(sound => {
                        setTimeout(() => {
                            sound.classList.add('in-view');
                        }, 500);
                    });
                }
            });
        }, { threshold: 0.3 });

        comicStrips.forEach(strip => {
            comicObserver.observe(strip);
        });

        // Replay animation on hover
        comicStrips.forEach(strip => {
            strip.addEventListener('mouseenter', () => {
                const panels = strip.querySelectorAll('.panel');
                const sfx = strip.querySelectorAll('.sfx');

                // Only replay if already viewed
                if (panels[0] && panels[0].classList.contains('in-view')) {
                    panels.forEach(panel => panel.classList.remove('in-view'));
                    sfx.forEach(sound => sound.classList.remove('in-view'));
                    void strip.offsetWidth;

                    panels.forEach((panel, index) => {
                        setTimeout(() => {
                            panel.classList.add('in-view');
                        }, index * 200);
                    });

                    sfx.forEach(sound => {
                        setTimeout(() => {
                            sound.classList.add('in-view');
                        }, 500);
                    });
                }
            });
        });
    }

    // =========================================
    // DESIGN #5: Chat Bubbles
    // =========================================
    const chatContainers = document.querySelectorAll('.chat-ui-container[data-chat]');
    if (chatContainers.length > 0) {
        const chatObserver = new IntersectionObserver((entries) => {
            entries.forEach(entry => {
                if (entry.isIntersecting) {
                    playChatAnimation(entry.target);
                    chatObserver.unobserve(entry.target);
                }
            });
        }, { threshold: 0.2 });

        chatContainers.forEach(chat => {
            chatObserver.observe(chat);
        });

        function playChatAnimation(chatContainer) {
            const chatContent = chatContainer.querySelector('.chat-content');
            if (!chatContent) return;

            const items = chatContent.querySelectorAll('.chat-message, .typing-indicator, .chat-status');

            items.forEach(item => {
                const delay = parseInt(item.getAttribute('data-delay') || '0', 10);

                setTimeout(() => {
                    if (item.classList.contains('typing-indicator')) {
                        item.classList.add('active');
                        setTimeout(() => {
                            item.classList.remove('active');
                        }, 600);
                    } else {
                        item.classList.add('in-view');
                    }
                }, delay);
            });
        }

        // Replay animation on hover
        chatContainers.forEach(container => {
            container.addEventListener('mouseenter', () => {
                const chatContent = container.querySelector('.chat-content');
                if (!chatContent) return;

                const items = chatContent.querySelectorAll('.chat-message, .chat-status');
                const hasPlayed = items[0] && items[0].classList.contains('in-view');

                if (hasPlayed) {
                    items.forEach(item => item.classList.remove('in-view'));
                    void container.offsetWidth;
                    playChatAnimation(container);
                }
            });
        });
    }

    // =========================================================================
    // DESIGN #6: MINIMAL GEOMETRIC (Apple-style)
    // =========================================================================
    const geoCards = document.querySelectorAll('[data-geo]');

    if (geoCards.length > 0) {
        const geoObserver = new IntersectionObserver((entries) => {
            entries.forEach(entry => {
                if (entry.isIntersecting) {
                    entry.target.classList.add('animating');
                }
            });
        }, {
            threshold: 0.3,
            rootMargin: '0px 0px -50px 0px'
        });

        geoCards.forEach(card => {
            geoObserver.observe(card);

            // Replay animation on hover
            card.addEventListener('mouseenter', () => {
                if (card.classList.contains('animating')) {
                    card.classList.remove('animating');
                    void card.offsetWidth; // Force reflow
                    card.classList.add('animating');
                }
            });
        });
    }

    // =========================================================================
    // Home Row Mods Interactive Demo
    // =========================================================================
    const hrmDemo = document.querySelector('.hrm-demo');
    if (hrmDemo) {
        const outputText = hrmDemo.querySelector('.hrm-output-text');
        const outputBox = hrmDemo.querySelector('.hrm-output');
        const modeLabel = hrmDemo.querySelector('.hrm-demo-mode');
        const keyboard = hrmDemo.querySelector('.hrm-keyboard');
        const keyElements = {
            a: hrmDemo.querySelector('[data-key="a"]'),
            s: hrmDemo.querySelector('[data-key="s"]'),
            d: hrmDemo.querySelector('[data-key="d"]'),
            f: hrmDemo.querySelector('[data-key="f"]')
        };
        const modNames = { a: 'Ctrl+', s: 'Alt+', d: '⌘', f: 'Shift+' };

        // State
        let isInteractive = false;
        let autoAnimationId = null;
        let cancelAutoDemo = null;
        let heldKeys = new Set();
        let holdTimers = {};
        const HOLD_THRESHOLD = 200; // ms to count as hold

        // Check for reduced motion preference
        const prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

        // Flash effect for shortcuts
        function triggerShortcutFlash() {
            outputBox.classList.remove('shortcut-flash');
            void outputBox.offsetWidth; // Force reflow
            outputBox.classList.add('shortcut-flash');
        }

        // ---- Auto Demo Animation ----
        function runAutoDemo() {
            let step = 0;
            let cancelled = false;

            const sequence = [
                // Type letters "asdf"
                { action: 'mode', text: 'Tap for letters', delay: 700 },
                { action: 'tap', key: 'a', delay: 200 },
                { action: 'tap', key: 's', delay: 200 },
                { action: 'tap', key: 'd', delay: 200 },
                { action: 'tap', key: 'f', delay: 600 },
                { action: 'clear', delay: 500 },

                // ⌘S (Save)
                { action: 'mode', text: 'Hold for modifiers', delay: 400 },
                { action: 'hold', key: 'd', delay: 300 },
                { action: 'tap', key: 's', delay: 450 },
                { action: 'release', key: 'd', delay: 600 },
                { action: 'clear', delay: 400 },

                // Ctrl+A (Select All)
                { action: 'hold', key: 'a', delay: 300 },
                { action: 'tap', key: 'd', delay: 450 },
                { action: 'release', key: 'a', delay: 600 },
                { action: 'clear', delay: 400 },

                // ⌘F (Find)
                { action: 'hold', key: 'd', delay: 300 },
                { action: 'tap', key: 'f', delay: 450 },
                { action: 'release', key: 'd', delay: 600 },
                { action: 'clear', delay: 400 },

                // Shift+A (capital A)
                { action: 'hold', key: 'f', delay: 300 },
                { action: 'tap', key: 'a', delay: 450 },
                { action: 'release', key: 'f', delay: 600 },
                { action: 'clear', delay: 400 },

                // Type "dad" fast
                { action: 'mode', text: 'Fast typing still works', delay: 400 },
                { action: 'tap', key: 'd', delay: 120 },
                { action: 'tap', key: 'a', delay: 120 },
                { action: 'tap', key: 'd', delay: 600 },
                { action: 'clear', delay: 400 },

                // ⌘⇧S (Save As) - two modifiers!
                { action: 'mode', text: 'Combine modifiers', delay: 400 },
                { action: 'hold', key: 'd', delay: 250 },
                { action: 'hold', key: 'f', delay: 300 },
                { action: 'tap', key: 's', delay: 450 },
                { action: 'release', key: 'f', delay: 200 },
                { action: 'release', key: 'd', delay: 600 },
                { action: 'clear', delay: 800 },

                // Loop
                { action: 'restart', delay: 0 }
            ];

            let currentOutput = '';

            function executeStep() {
                if (cancelled || isInteractive) return;
                if (step >= sequence.length) return;

                const s = sequence[step];

                switch (s.action) {
                    case 'mode':
                        modeLabel.textContent = s.text;
                        modeLabel.classList.add('visible');
                        break;

                    case 'tap':
                        if (keyElements[s.key]) {
                            keyElements[s.key].classList.add('pressed');
                            setTimeout(() => {
                                if (!cancelled) keyElements[s.key].classList.remove('pressed');
                            }, 100);
                        }
                        // Output depends on held keys
                        if (heldKeys.size > 0) {
                            let mod = '';
                            heldKeys.forEach(k => mod += modNames[k]);
                            currentOutput = mod + s.key.toUpperCase();
                            outputBox.classList.add('shortcut');
                            triggerShortcutFlash();
                        } else {
                            currentOutput += s.key;
                            outputBox.classList.remove('shortcut');
                        }
                        outputText.textContent = currentOutput;
                        break;

                    case 'hold':
                        if (keyElements[s.key]) {
                            keyElements[s.key].classList.add('held');
                            heldKeys.add(s.key);
                        }
                        break;

                    case 'release':
                        if (keyElements[s.key]) {
                            keyElements[s.key].classList.remove('held');
                            heldKeys.delete(s.key);
                        }
                        break;

                    case 'clear':
                        currentOutput = '';
                        outputText.textContent = '';
                        outputBox.classList.remove('shortcut', 'shortcut-flash');
                        modeLabel.classList.remove('visible');
                        heldKeys.clear();
                        break;

                    case 'restart':
                        step = -1;
                        break;
                }

                step++;
                if (step < sequence.length && !cancelled && !isInteractive) {
                    autoAnimationId = setTimeout(executeStep, sequence[step - 1].delay);
                }
            }

            executeStep();

            // Return cancel function
            return () => {
                cancelled = true;
                if (autoAnimationId) {
                    clearTimeout(autoAnimationId);
                    autoAnimationId = null;
                }
            };
        }

        // ---- Interactive Mode ----
        function enterInteractiveMode() {
            if (isInteractive) return;
            isInteractive = true;

            // Stop auto animation
            if (cancelAutoDemo) {
                cancelAutoDemo();
                cancelAutoDemo = null;
            }

            // Clear state
            Object.values(keyElements).forEach(el => {
                if (el) el.classList.remove('pressed', 'held');
            });
            heldKeys.clear();
            outputText.textContent = '';
            outputBox.classList.remove('shortcut', 'shortcut-flash');

            // Show interactive hint
            modeLabel.textContent = 'Try it! Click = letter, hold = modifier';
            modeLabel.classList.add('visible');
        }

        function exitInteractiveMode() {
            if (!isInteractive) return;
            isInteractive = false;

            // Clear any held keys
            Object.keys(holdTimers).forEach(key => {
                clearTimeout(holdTimers[key].timeout);
            });
            holdTimers = {};

            // Clear state
            Object.values(keyElements).forEach(el => {
                if (el) el.classList.remove('pressed', 'held');
            });
            heldKeys.clear();
            outputText.textContent = '';
            outputBox.classList.remove('shortcut', 'shortcut-flash');
            modeLabel.classList.remove('visible');

            // Restart auto demo
            if (!prefersReducedMotion) {
                cancelAutoDemo = runAutoDemo();
            }
        }

        // Key interaction handlers
        function onKeyDown(key, element) {
            // Start hold timer
            holdTimers[key] = {
                start: Date.now(),
                timeout: setTimeout(() => {
                    // Became a hold
                    element.classList.remove('pressed');
                    element.classList.add('held');
                    heldKeys.add(key);
                }, HOLD_THRESHOLD)
            };
            element.classList.add('pressed');
        }

        function onKeyUp(key, element) {
            const timer = holdTimers[key];
            if (timer) {
                clearTimeout(timer.timeout);
                const duration = Date.now() - timer.start;

                if (duration < HOLD_THRESHOLD) {
                    // It was a tap - emit letter (or modified letter)
                    element.classList.remove('pressed');

                    if (heldKeys.size > 0) {
                        // Modified tap - shortcut!
                        let mod = '';
                        heldKeys.forEach(k => mod += modNames[k]);
                        outputText.textContent = mod + key.toUpperCase();
                        outputBox.classList.add('shortcut');
                        triggerShortcutFlash();
                    } else {
                        // Plain letter
                        outputText.textContent += key;
                        outputBox.classList.remove('shortcut', 'shortcut-flash');
                    }
                } else {
                    // It was a hold - release modifier
                    element.classList.remove('held');
                    heldKeys.delete(key);
                    if (heldKeys.size === 0) {
                        outputBox.classList.remove('shortcut', 'shortcut-flash');
                    }
                }
                delete holdTimers[key];
            }
        }

        // Attach event listeners to keys
        Object.entries(keyElements).forEach(([key, element]) => {
            if (!element) return;

            // Mouse events
            element.addEventListener('mousedown', (e) => {
                e.preventDefault();
                enterInteractiveMode();
                onKeyDown(key, element);
            });

            element.addEventListener('mouseup', (e) => {
                e.preventDefault();
                onKeyUp(key, element);
            });

            element.addEventListener('mouseleave', () => {
                // If mouse leaves while pressed, treat as release
                if (holdTimers[key]) {
                    onKeyUp(key, element);
                }
            });

            // Touch events for mobile
            element.addEventListener('touchstart', (e) => {
                e.preventDefault();
                enterInteractiveMode();
                onKeyDown(key, element);
            }, { passive: false });

            element.addEventListener('touchend', (e) => {
                e.preventDefault();
                onKeyUp(key, element);
            }, { passive: false });
        });

        // Resume auto demo when mouse leaves keyboard area
        keyboard.addEventListener('mouseleave', () => {
            // Small delay before resuming to avoid accidental triggers
            setTimeout(() => {
                if (isInteractive && Object.keys(holdTimers).length === 0) {
                    exitInteractiveMode();
                }
            }, 800);
        });

        // Clear output on click
        outputBox.addEventListener('click', () => {
            if (isInteractive) {
                outputText.textContent = '';
                outputBox.classList.remove('shortcut', 'shortcut-flash');
            }
        });

        // ---- Start Auto Demo on scroll into view ----
        let demoStarted = false;

        const hrmObserver = new IntersectionObserver((entries) => {
            entries.forEach(entry => {
                if (entry.isIntersecting && !demoStarted && !prefersReducedMotion) {
                    demoStarted = true;
                    cancelAutoDemo = runAutoDemo();
                }
            });
        }, {
            threshold: 0.5
        });

        hrmObserver.observe(hrmDemo);

        // For reduced motion: start in interactive mode
        if (prefersReducedMotion) {
            isInteractive = true;
            modeLabel.textContent = 'Click = letter, hold = modifier';
            modeLabel.classList.add('visible');
        }
    }
})();
