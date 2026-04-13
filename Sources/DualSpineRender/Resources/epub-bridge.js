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

    /**
     * Check if the current selection overlaps an existing highlight.
     * Returns the highlight ID if overlapping, or empty string if not.
     */
    window.__dualSpine_getSelectionHighlightId = function() {
        const sel = window.getSelection();
        if (!sel || sel.isCollapsed || !sel.rangeCount) return '';

        // Walk up from the selection's anchor/focus nodes to find a highlight <mark>
        var node = sel.anchorNode;
        while (node && node !== document.body) {
            if (node.nodeType === 1 && node.classList &&
                node.classList.contains('dualspine-highlight')) {
                return node.dataset.highlightId || '';
            }
            node = node.parentNode;
        }

        // Also check focus node
        node = sel.focusNode;
        while (node && node !== document.body) {
            if (node.nodeType === 1 && node.classList &&
                node.classList.contains('dualspine-highlight')) {
                return node.dataset.highlightId || '';
            }
            node = node.parentNode;
        }

        return '';
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

    // ─── Scroll Position Restoration ─────────────────────────────────

    /**
     * Scroll to a percentage of the document (0.0–1.0).
     * Used for restoring reading position.
     * @param {number} progress - 0.0 to 1.0
     */
    window.__dualSpine_scrollToProgress = function(progress) {
        const docHeight = document.documentElement.scrollHeight;
        const viewportHeight = window.innerHeight;
        const maxScroll = Math.max(docHeight - viewportHeight, 0);
        const target = maxScroll * Math.min(Math.max(progress, 0), 1);
        window.scrollTo({ top: target, behavior: 'instant' });
    };

    /**
     * Get surrounding text context for a selection (for highlight anchoring).
     * Returns { textBefore, textAfter } with ~50 chars each.
     */
    window.__dualSpine_getSelectionContext = function() {
        const sel = window.getSelection();
        if (!sel || sel.isCollapsed || !sel.rangeCount) return null;

        const range = sel.getRangeAt(0);
        const bodyText = document.body.textContent || '';

        // Calculate character offset
        const preRange = document.createRange();
        preRange.selectNodeContents(document.body);
        preRange.setEnd(range.startContainer, range.startOffset);
        const startOffset = preRange.toString().length;
        const endOffset = startOffset + sel.toString().length;

        return {
            textBefore: bodyText.substring(Math.max(0, startOffset - 50), startOffset),
            textAfter: bodyText.substring(endOffset, endOffset + 50),
            rangeStart: startOffset,
            rangeEnd: endOffset
        };
    };

    // ─── Pagination (Column Layout) ─────────────────────────────────

    var _pagination = {
        enabled: false,
        currentPage: 0,
        totalPages: 1,
        pageWidth: 0,
        gap: 40
    };

    /**
     * Enable paginated (column) layout.
     * @param {number} gap - Gap between pages in pixels (default 40).
     */
    window.__dualSpine_enablePagination = function(gap) {
        _pagination.enabled = true;
        _pagination.gap = gap || 40;
        _pagination.currentPage = 0;

        const vw = window.innerWidth;
        const vh = window.innerHeight;
        _pagination.pageWidth = vw;

        // Inject pagination CSS
        let style = document.getElementById('dualspine-pagination');
        if (!style) {
            style = document.createElement('style');
            style.id = 'dualspine-pagination';
            document.head.appendChild(style);
        }

        const colWidth = vw - _pagination.gap;
        style.textContent = `
            html {
                height: ${vh}px !important;
                overflow: hidden !important;
            }
            body {
                height: ${vh - 40}px !important;
                margin: 20px 0 !important;
                padding: 0 ${_pagination.gap / 2}px !important;
                column-width: ${colWidth}px !important;
                column-gap: ${_pagination.gap}px !important;
                column-fill: auto !important;
                overflow: hidden !important;
                box-sizing: border-box !important;
                -webkit-transform: translateX(0px);
                transform: translateX(0px);
                transition: transform 0.25s ease-out;
            }
        `;

        // Disable vertical scrolling
        document.documentElement.style.overflow = 'hidden';
        document.body.style.overflow = 'hidden';
        window.scrollTo(0, 0);

        // Calculate pages after layout settles
        requestAnimationFrame(function() {
            requestAnimationFrame(function() {
                _recalcPages();
                _goToPage(0);
                _reportPageChange();
            });
        });

        // Set up tap-to-turn zones
        _setupTapZones();
    };

    /**
     * Disable pagination, return to scroll layout.
     */
    window.__dualSpine_disablePagination = function() {
        _pagination.enabled = false;
        _pagination.currentPage = 0;

        const style = document.getElementById('dualspine-pagination');
        if (style) style.remove();

        document.documentElement.style.overflow = '';
        document.body.style.overflow = '';
        document.body.style.transform = '';
        document.body.style.webkitTransform = '';

        _removeTapZones();
        postMessage('paginationDisabled');
    };

    /**
     * Navigate to a specific page (0-indexed).
     */
    window.__dualSpine_goToPage = function(pageIndex) {
        if (!_pagination.enabled) return;
        _goToPage(pageIndex);
        _reportPageChange();
    };

    /**
     * Go to next page. Returns true if turned, false if at end.
     */
    window.__dualSpine_nextPage = function() {
        if (!_pagination.enabled) return false;
        if (_pagination.currentPage >= _pagination.totalPages - 1) {
            postMessage('paginationAtEnd');
            return false;
        }
        _goToPage(_pagination.currentPage + 1);
        _reportPageChange();
        return true;
    };

    /**
     * Go to previous page. Returns true if turned, false if at beginning.
     */
    window.__dualSpine_previousPage = function() {
        if (!_pagination.enabled) return false;
        if (_pagination.currentPage <= 0) {
            postMessage('paginationAtStart');
            return false;
        }
        _goToPage(_pagination.currentPage - 1);
        _reportPageChange();
        return true;
    };

    /**
     * Get current pagination state.
     */
    window.__dualSpine_getPaginationState = function() {
        return {
            enabled: _pagination.enabled,
            currentPage: _pagination.currentPage,
            totalPages: _pagination.totalPages,
            pageWidth: _pagination.pageWidth
        };
    };

    /**
     * Navigate to a progress percentage (0.0-1.0) in paginated mode.
     */
    window.__dualSpine_goToProgress = function(progress) {
        if (!_pagination.enabled) {
            window.__dualSpine_scrollToProgress(progress);
            return;
        }
        _recalcPages();
        const targetPage = Math.floor(progress * _pagination.totalPages);
        _goToPage(Math.min(targetPage, _pagination.totalPages - 1));
        _reportPageChange();
    };

    function _recalcPages() {
        if (!_pagination.enabled) return;
        const scrollW = document.body.scrollWidth;
        const pw = _pagination.pageWidth;
        _pagination.totalPages = Math.max(Math.ceil(scrollW / pw), 1);
    }

    function _goToPage(index) {
        index = Math.max(0, Math.min(index, _pagination.totalPages - 1));
        _pagination.currentPage = index;
        const offset = -index * _pagination.pageWidth;
        document.body.style.transform = 'translateX(' + offset + 'px)';
        document.body.style.webkitTransform = 'translateX(' + offset + 'px)';
    }

    function _reportPageChange() {
        postMessage('pageChanged', {
            currentPage: _pagination.currentPage,
            totalPages: _pagination.totalPages,
            progress: _pagination.totalPages > 1
                ? _pagination.currentPage / (_pagination.totalPages - 1)
                : 0
        });
    }

    // ─── Tap-to-Turn Zones ───────────────────────────────────────────

    var _tapOverlay = null;

    function _setupTapZones() {
        _removeTapZones();

        _tapOverlay = document.createElement('div');
        _tapOverlay.id = 'dualspine-tap-overlay';
        _tapOverlay.style.cssText = `
            position: fixed; top: 0; left: 0; right: 0; bottom: 0;
            z-index: 99998; pointer-events: none;
        `;

        // Left zone (previous page) — 25% of screen width
        const leftZone = document.createElement('div');
        leftZone.style.cssText = `
            position: absolute; top: 0; left: 0; width: 25%; height: 100%;
            pointer-events: auto; -webkit-tap-highlight-color: transparent;
        `;
        leftZone.addEventListener('click', function(e) {
            // Don't interfere with text selection
            if (window.getSelection().toString().length > 0) return;
            e.preventDefault();
            e.stopPropagation();
            window.__dualSpine_previousPage();
        });

        // Right zone (next page) — 25% of screen width
        const rightZone = document.createElement('div');
        rightZone.style.cssText = `
            position: absolute; top: 0; right: 0; width: 25%; height: 100%;
            pointer-events: auto; -webkit-tap-highlight-color: transparent;
        `;
        rightZone.addEventListener('click', function(e) {
            if (window.getSelection().toString().length > 0) return;
            e.preventDefault();
            e.stopPropagation();
            window.__dualSpine_nextPage();
        });

        _tapOverlay.appendChild(leftZone);
        _tapOverlay.appendChild(rightZone);
        document.body.appendChild(_tapOverlay);
    }

    function _removeTapZones() {
        if (_tapOverlay) {
            _tapOverlay.remove();
            _tapOverlay = null;
        }
    }

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
