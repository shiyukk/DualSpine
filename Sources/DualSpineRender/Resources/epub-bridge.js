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

        // If color bar is visible, update its background to match new theme
        requestAnimationFrame(function() {
            _updateDotStripTheme();
        });
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
        // Remove existing highlights by unwrapping (preserving text content)
        document.querySelectorAll('.dualspine-highlight').forEach(function(mark) {
            var parent = mark.parentNode;
            while (mark.firstChild) {
                parent.insertBefore(mark.firstChild, mark);
            }
            parent.removeChild(mark);
            parent.normalize();
        });

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
            // Collect text nodes that fall within the highlight range
            var nodesToWrap = [];
            for (const tn of textNodes) {
                if (tn.end <= hl.rangeStart) continue;  // before range
                if (tn.start >= hl.rangeEnd) break;      // past range

                var wrapStart = Math.max(0, hl.rangeStart - tn.start);
                var wrapEnd = Math.min(tn.node.length, hl.rangeEnd - tn.start);
                nodesToWrap.push({ node: tn.node, start: wrapStart, end: wrapEnd });
            }

            // Wrap each text node segment individually (handles cross-element spans)
            for (var i = nodesToWrap.length - 1; i >= 0; i--) {
                var item = nodesToWrap[i];
                try {
                    var range = document.createRange();
                    range.setStart(item.node, item.start);
                    range.setEnd(item.node, item.end);

                    var mark = document.createElement('mark');
                    mark.className = 'dualspine-highlight';
                    mark.dataset.highlightId = hl.id;
                    mark.style.backgroundColor = hl.color || 'rgba(247, 201, 72, 0.35)';
                    mark.style.borderRadius = '2px';
                    range.surroundContents(mark);
                } catch (e) {
                    console.warn('[DualSpine] Highlight wrap failed for node:', e);
                }
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

    // ─── Color Dot Strip (shown after tapping Highlight) ───────────

    var _dotStrip = null;

    /**
     * Show color dot strip below the current selection.
     * Called from Swift when user taps "Highlight" in the system menu.
     */
    window.__dualSpine_showColorPicker = function() {
        _hideDotStrip();

        const sel = window.getSelection();
        if (!sel || sel.isCollapsed || !sel.rangeCount) return;

        const range = sel.getRangeAt(0);
        const rect = range.getBoundingClientRect();
        if (rect.width === 0 && rect.height === 0) return;

        // 5 color dots in a pill bar matching the system callout size
        var colors = [
            { hex: '#F7C948', name: 'Yellow' },
            { hex: '#69DB7C', name: 'Green' },
            { hex: '#74C0FC', name: 'Blue' },
            { hex: '#FFA8A8', name: 'Pink' },
            { hex: '#B197FC', name: 'Purple' }
        ];

        _dotStrip = document.createElement('div');
        _dotStrip.id = 'dualspine-dot-strip';

        // Match system callout dimensions: ~298px wide, 44px tall, centered
        var barWidth = 298;
        var barHeight = 44;
        var dotSize = 28;

        var left = Math.max(8, rect.left + rect.width / 2 - barWidth / 2);
        if (left + barWidth > window.innerWidth - 8) left = window.innerWidth - barWidth - 8;
        var top = rect.bottom + 6;
        if (top + barHeight > window.innerHeight) top = rect.top - barHeight - 6;

        _dotStrip.style.cssText = [
            'position:fixed', 'z-index:99999',
            'display:flex', 'align-items:center',
            'justify-content:center',
            'gap:16px',
            'width:' + barWidth + 'px',
            'height:' + barHeight + 'px',
            'top:' + top + 'px', 'left:' + left + 'px',
            'pointer-events:auto',
            'border-radius:14px'
        ].join(';');

        // Apply theme-matched background
        _updateDotStripTheme();

        colors.forEach(function(c) {
            var dot = document.createElement('button');
            dot.style.cssText = [
                'width:' + dotSize + 'px',
                'height:' + dotSize + 'px',
                'border-radius:50%',
                'border:none',
                'padding:0', 'margin:0',
                'cursor:pointer',
                'background:' + c.hex,
                'flex-shrink:0',
                '-webkit-tap-highlight-color:transparent'
            ].join(';');
            dot.addEventListener('click', function(e) {
                e.preventDefault(); e.stopPropagation();
                postMessage('highlightRequest', { tintHex: c.hex });
                _hideDotStrip();
            });
            _dotStrip.appendChild(dot);
        });

        document.body.appendChild(_dotStrip);
    };

    function _hideDotStrip() {
        if (_dotStrip) { _dotStrip.remove(); _dotStrip = null; }
    }

    /**
     * Update the dot strip's background/shadow to match the current theme.
     * Called on initial show and whenever the theme changes while visible.
     */
    function _updateDotStripTheme() {
        if (!_dotStrip) return;

        var computedBg = getComputedStyle(document.body).backgroundColor;
        var bgColor = computedBg || '#111111';
        var lum = _colorLuminance(bgColor);
        var isDark = lum < 0.5;
        var base = _parseColor(bgColor);
        var barBg, barShadow;

        if (isDark) {
            var r = Math.min(255, base.r + 40);
            var g = Math.min(255, base.g + 40);
            var b = Math.min(255, base.b + 40);
            barBg = 'rgba(' + r + ',' + g + ',' + b + ',0.85)';
            barShadow = '0 2px 16px rgba(0,0,0,0.5), 0 0 0 0.5px rgba(255,255,255,0.08)';
        } else {
            var r = Math.max(0, base.r - 8);
            var g = Math.max(0, base.g - 8);
            var b = Math.max(0, base.b - 8);
            barBg = 'rgba(' + r + ',' + g + ',' + b + ',0.88)';
            barShadow = '0 2px 16px rgba(0,0,0,0.12), 0 0 0 0.5px rgba(0,0,0,0.08)';
        }

        _dotStrip.style.background = barBg;
        _dotStrip.style.boxShadow = barShadow;
    }

    window.addEventListener('scroll', _hideDotStrip, { passive: true });
    document.addEventListener('touchstart', function(e) {
        if (_dotStrip && !_dotStrip.contains(e.target)) _hideDotStrip();
    }, { passive: true });

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

    /**
     * Parse a CSS color string (hex, rgb, rgba) into {r, g, b} 0-255.
     */
    function _parseColor(str) {
        str = (str || '').trim();
        // hex
        if (str.charAt(0) === '#') {
            var hex = str.substring(1);
            if (hex.length === 3) hex = hex[0]+hex[0]+hex[1]+hex[1]+hex[2]+hex[2];
            return {
                r: parseInt(hex.substring(0,2), 16),
                g: parseInt(hex.substring(2,4), 16),
                b: parseInt(hex.substring(4,6), 16)
            };
        }
        // rgb(a)
        var m = str.match(/rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)/);
        if (m) return { r: parseInt(m[1]), g: parseInt(m[2]), b: parseInt(m[3]) };
        // fallback dark
        return { r: 17, g: 17, b: 17 };
    }

    /**
     * Compute relative luminance (0=black, 1=white) from a CSS color string.
     */
    function _colorLuminance(colorStr) {
        var c = _parseColor(colorStr);
        // sRGB luminance
        return (0.299 * c.r + 0.587 * c.g + 0.114 * c.b) / 255;
    }

    /**
     * Adjust brightness of a CSS color. amount: -1 to 1 (negative=darken, positive=lighten).
     * Returns an rgb() string.
     */
    function _adjustBrightness(colorStr, amount) {
        var c = _parseColor(colorStr);
        var adjust = function(v) {
            if (amount > 0) {
                return Math.min(255, Math.round(v + (255 - v) * amount));
            } else {
                return Math.max(0, Math.round(v * (1 + amount)));
            }
        };
        return 'rgb(' + adjust(c.r) + ',' + adjust(c.g) + ',' + adjust(c.b) + ')';
    }

})();
