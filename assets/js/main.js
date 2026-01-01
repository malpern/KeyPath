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
})();
