/**
 * DualSpine EPUB Bridge
 *
 * Thin JavaScript layer injected into WKWebView to bridge EPUB content events
 * back to Swift via window.webkit.messageHandlers.dualSpine.postMessage().
 *
 * Responsibilities:
 * - Text selection tracking (coordinates + range offsets)
 * - Scroll progress reporting (debounced)
 * - Link interception (internal vs external)
 * - Theme/style injection
 * - Highlight overlay rendering
 * - Content-ready signaling
 */

(function() {
    'use strict';

    const HANDLER_NAME = 'dualSpine';
    const SCROLL_DEBOUNCE_MS = 100;
    const PROGRESS_DEBOUNCE_MS = 150;

    // ─── Messaging ───────────────────────────────────────────────────

    function postMessage(type, payload) {
        try {
            window.webkit.messageHandlers[HANDLER_NAME].postMessage({
                type: type,
                payload: payload || {}
            });
        } catch (e) {
            console.warn('[DualSpine] postMessage failed:', e);
        }
    }

    // ─── Selection Tracking ──────────────────────────────────────────

    function getSelectionInfo() {
        const sel = window.getSelection();
        if (!sel || sel.isCollapsed || !sel.rangeCount) return null;

        const range = sel.getRangeAt(0);
        const text = sel.toString().trim();
        if (!text) return null;

        const rect = range.getBoundingClientRect();

        // Calculate character offsets within the document body
        const preRange = document.createRange();
        preRange.selectNodeContents(document.body);
        preRange.setEnd(range.startContainer, range.startOffset);
        const rangeStart = preRange.toString().length;

        return {
            text: text,
            rangeStart: rangeStart,
            rangeEnd: rangeStart + text.length,
            rectX: rect.x,
            rectY: rect.y,
            rectWidth: rect.width,
            rectHeight: rect.height,
            spineHref: window.__dualSpine_spineHref || ''
        };
    }

    document.addEventListener('selectionchange', debounce(function() {
        const info = getSelectionInfo();
        if (info) {
            postMessage('selectionChanged', info);
        } else {
            postMessage('selectionCleared');
        }
    }, 200));

    // ─── Scroll & Progress Tracking ──────────────────────────────────

    function getProgressInfo() {
        const scrollTop = window.scrollY || document.documentElement.scrollTop;
        const docHeight = document.documentElement.scrollHeight;
        const viewportHeight = window.innerHeight;
        const maxScroll = Math.max(docHeight - viewportHeight, 1);
        const progress = Math.min(scrollTop / maxScroll, 1.0);

        return {
            chapterProgress: progress,
            scrollOffset: scrollTop,
            contentHeight: docHeight,
            isAtEnd: (scrollTop + viewportHeight) >= (docHeight - 10)
        };
    }

    window.addEventListener('scroll', debounce(function() {
        postMessage('progressUpdated', getProgressInfo());
    }, PROGRESS_DEBOUNCE_MS), { passive: true });

    // ─── Link Interception ───────────────────────────────────────────

    document.addEventListener('click', function(e) {
        const link = e.target.closest('a[href]');
        if (!link) return;

        const href = link.getAttribute('href');
        if (!href) return;

        // External links open in Safari
        const isExternal = /^https?:\/\//i.test(href);

        e.preventDefault();
        postMessage('linkTapped', {
            href: href,
            isInternal: !isExternal
        });
    });

    // ─── Image Tapping ───────────────────────────────────────────────

    document.addEventListener('click', function(e) {
        if (e.target.tagName === 'IMG') {
            const img = e.target;
            postMessage('imageTapped', {
                src: img.src,
                alt: img.alt || null,
                naturalWidth: img.naturalWidth,
                naturalHeight: img.naturalHeight
            });
        }
    });

    // ─── Theme Injection ─────────────────────────────────────────────

    /**
     * Apply a theme stylesheet. Called from Swift via evaluateJavaScript.
     * @param {string} css - Full CSS string to inject/replace.
     */
    window.__dualSpine_applyTheme = function(css) {
        let style = document.getElementById('dualspine-theme');
        if (!style) {
            style = document.createElement('style');
            style.id = 'dualspine-theme';
            document.head.appendChild(style);
        }
        style.textContent = css;
    };

    /**
     * Set a CSS custom property on the root element.
     * @param {string} name - CSS variable name (e.g. '--ds-bg-color').
     * @param {string} value - CSS value.
     */
    window.__dualSpine_setCSSVar = function(name, value) {
        document.documentElement.style.setProperty(name, value);
    };

    // ─── Highlight Rendering ─────────────────────────────────────────

    /**
     * Apply highlight overlays to the content.
     * @param {Array} highlights - Array of { id, rangeStart, rangeEnd, color }.
     */
    window.__dualSpine_applyHighlights = function(highlights) {
        // Remove existing highlights
        document.querySelectorAll('.dualspine-highlight').forEach(el => el.remove());

        if (!highlights || !highlights.length) return;

        const treeWalker = document.createTreeWalker(
            document.body,
            NodeFilter.SHOW_TEXT,
            null
        );

        // Build a flat list of text nodes with their document offsets
        const textNodes = [];
        let offset = 0;
        let node;
        while ((node = treeWalker.nextNode())) {
            textNodes.push({ node: node, start: offset, end: offset + node.length });
            offset += node.length;
        }

        for (const hl of highlights) {
            const range = document.createRange();
            let startSet = false;

            for (const tn of textNodes) {
                // Find the text node containing the start offset
                if (!startSet && tn.end > hl.rangeStart) {
                    range.setStart(tn.node, hl.rangeStart - tn.start);
                    startSet = true;
                }
                // Find the text node containing the end offset
                if (startSet && tn.end >= hl.rangeEnd) {
                    range.setEnd(tn.node, hl.rangeEnd - tn.start);
                    break;
                }
            }

            if (!startSet) continue;

            // Wrap the range with a highlight span
            try {
                const mark = document.createElement('mark');
                mark.className = 'dualspine-highlight';
                mark.dataset.highlightId = hl.id;
                mark.style.backgroundColor = hl.color || 'rgba(247, 201, 72, 0.35)';
                mark.style.borderRadius = '2px';
                range.surroundContents(mark);
            } catch (e) {
                // surroundContents fails on partial selections spanning elements.
                // Fall back to using CSS Highlight API or individual text node wrapping
                // if available. For now, skip this highlight.
                console.warn('[DualSpine] Highlight wrap failed for id:', hl.id, e);
            }
        }
    };

    /**
     * Remove a specific highlight by ID.
     * @param {string} highlightId
     */
    window.__dualSpine_removeHighlight = function(highlightId) {
        const mark = document.querySelector(
            '.dualspine-highlight[data-highlight-id="' + highlightId + '"]'
        );
        if (mark) {
            const parent = mark.parentNode;
            while (mark.firstChild) {
                parent.insertBefore(mark.firstChild, mark);
            }
            parent.removeChild(mark);
            parent.normalize();
        }
    };

    // ─── Navigation ──────────────────────────────────────────────────

    /**
     * Scroll to a specific character offset in the document.
     * @param {number} charOffset
     */
    window.__dualSpine_scrollToOffset = function(charOffset) {
        const treeWalker = document.createTreeWalker(
            document.body,
            NodeFilter.SHOW_TEXT,
            null
        );

        let offset = 0;
        let node;
        while ((node = treeWalker.nextNode())) {
            if (offset + node.length >= charOffset) {
                const range = document.createRange();
                range.setStart(node, charOffset - offset);
                range.collapse(true);
                const rect = range.getBoundingClientRect();
                window.scrollTo({ top: window.scrollY + rect.top - 60, behavior: 'smooth' });
                return;
            }
            offset += node.length;
        }
    };

    /**
     * Scroll to a DOM element by fragment ID.
     * @param {string} fragmentId
     */
    window.__dualSpine_scrollToFragment = function(fragmentId) {
        const el = document.getElementById(fragmentId);
        if (el) {
            el.scrollIntoView({ behavior: 'smooth', block: 'start' });
        }
    };

    // ─── Content Ready ───────────────────────────────────────────────

    function signalContentReady() {
        postMessage('contentReady', {
            spineHref: window.__dualSpine_spineHref || '',
            contentHeight: document.documentElement.scrollHeight,
            characterCount: (document.body.textContent || '').length
        });
    }

    // Fire on DOMContentLoaded or immediately if already loaded
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', signalContentReady);
    } else {
        signalContentReady();
    }

    // ─── Utilities ───────────────────────────────────────────────────

    function debounce(fn, delay) {
        let timer;
        return function() {
            clearTimeout(timer);
            timer = setTimeout(fn, delay);
        };
    }

})();
