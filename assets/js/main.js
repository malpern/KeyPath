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
    
    // Copy code block button
    document.querySelectorAll('pre code').forEach(block => {
        const pre = block.parentElement;
        if (pre.querySelector('.copy-button')) return;
        
        const button = document.createElement('button');
        button.className = 'copy-button';
        button.textContent = 'Copy';
        button.addEventListener('click', async () => {
            await navigator.clipboard.writeText(block.textContent);
            button.textContent = 'Copied!';
            setTimeout(() => {
                button.textContent = 'Copy';
            }, 2000);
        });
        pre.style.position = 'relative';
        pre.appendChild(button);
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
})();
