/**
 * DualSpine Reader Controller
 *
 * Stateless dispatcher + strategy-pattern layout engines.
 *
 *   Swift → dispatch(commandJSON) → active LayoutEngine
 *                                 ↓
 *                          postMessage(event) → Swift
 *
 * All DOM mutations happen inside a single root container `<div id="ds-reader">`.
 * The document `<body>` is left alone so publisher CSS does not fight with
 * reader CSS on specificity.
 */

(function () {
    'use strict';

    const HANDLER_NAME = 'dualSpineReader';
    const ROOT_ID = 'ds-reader';
    const STYLE_ID = 'ds-reader-style';
    const SELECTION_DEBOUNCE_MS = 180;

    // ─── Transport ────────────────────────────────────────────────────

    function postEvent(type, payload) {
        try {
            window.webkit.messageHandlers[HANDLER_NAME].postMessage({
                type: type,
                payload: payload || {}
            });
        } catch (e) {
            // no-op — Swift side not attached (e.g. preview)
        }
    }

    // ─── Root + base styles ───────────────────────────────────────────

    function ensureRoot() {
        let root = document.getElementById(ROOT_ID);
        if (root) return root;
        root = document.createElement('div');
        root.id = ROOT_ID;
        document.body.appendChild(root);
        return root;
    }

    function ensureBaseStyle() {
        if (document.getElementById(STYLE_ID)) return;
        const style = document.createElement('style');
        style.id = STYLE_ID;
        style.textContent = `
            html, body { margin: 0; padding: 0; }
            #${ROOT_ID} {
                box-sizing: border-box;
                width: 100%;
            }
            #${ROOT_ID} .ds-chapter {
                display: block;
                box-sizing: border-box;
            }
            #${ROOT_ID} .ds-page {
                box-sizing: border-box;
                overflow: hidden;
            }
            #${ROOT_ID} mark.ds-highlight {
                border-radius: 2px;
                background-color: rgba(247, 201, 72, 0.35);
            }
            #${ROOT_ID}.ds-paginated {
                position: fixed;
                top: 0; left: 0; right: 0; bottom: 0;
                overflow: hidden;
            }
            #${ROOT_ID} #ds-pages {
                display: grid;
                grid-auto-flow: column;
                grid-auto-columns: 100%;
                height: 100%;
                width: 100%;
                transform: translateX(calc(var(--ds-page-index, 0) * -100%));
                will-change: transform, opacity;
            }
            #${ROOT_ID}.ds-paginated.ds-slide #ds-pages {
                transition: transform 0.25s ease-out;
            }
            #${ROOT_ID}.ds-paginated.ds-fade #ds-pages {
                transition: opacity 0.18s ease-in-out;
            }
            #${ROOT_ID} .ds-tap-zones {
                position: fixed;
                inset: 0;
                z-index: 5;
                pointer-events: none;
                display: flex;
                justify-content: space-between;
            }
            #${ROOT_ID} .ds-tap-zones .ds-tap-zone {
                pointer-events: auto;
                width: 22%;
                background: transparent;
                border: none;
                padding: 0;
                -webkit-tap-highlight-color: transparent;
            }
            #${ROOT_ID} .ds-measure {
                position: absolute;
                visibility: hidden;
                pointer-events: none;
                left: -99999px;
                top: 0;
                box-sizing: border-box;
            }
        `;
        document.head.appendChild(style);
    }

    // ─── Shared helpers ───────────────────────────────────────────────

    function chapterIDFor(spineIndex) {
        return 'ds-chapter-' + spineIndex;
    }

    function buildChapterElement(chapter) {
        const article = document.createElement('article');
        article.className = 'ds-chapter';
        article.id = chapterIDFor(chapter.spineIndex);
        article.dataset.spineIndex = String(chapter.spineIndex);
        article.dataset.spineHref = chapter.spineHref || '';
        article.innerHTML = chapter.bodyHTML || '';
        return article;
    }

    function collectTextNodes(root) {
        const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null);
        const nodes = [];
        let offset = 0;
        let node;
        while ((node = walker.nextNode())) {
            nodes.push({ node: node, start: offset, end: offset + node.length });
            offset += node.length;
        }
        return nodes;
    }

    function applyHighlightsToScope(root, highlights) {
        // Remove previous marks within scope.
        root.querySelectorAll('mark.ds-highlight').forEach(function (mark) {
            const parent = mark.parentNode;
            while (mark.firstChild) parent.insertBefore(mark.firstChild, mark);
            parent.removeChild(mark);
            if (parent.normalize) parent.normalize();
        });
        if (!highlights || !highlights.length) return;

        // Group by spineIndex → chapter element.
        const byChapter = {};
        for (const hl of highlights) {
            const key = String(hl.spineIndex);
            if (!byChapter[key]) byChapter[key] = [];
            byChapter[key].push(hl);
        }

        Object.keys(byChapter).forEach(function (key) {
            const chapterEl = root.querySelector('#' + chapterIDFor(key));
            if (!chapterEl) return;
            const nodes = collectTextNodes(chapterEl);

            for (const hl of byChapter[key]) {
                const segments = [];
                for (const tn of nodes) {
                    if (tn.end <= hl.rangeStart) continue;
                    if (tn.start >= hl.rangeEnd) break;
                    const start = Math.max(0, hl.rangeStart - tn.start);
                    const end = Math.min(tn.node.length, hl.rangeEnd - tn.start);
                    if (end > start) segments.push({ node: tn.node, start: start, end: end });
                }
                for (let i = segments.length - 1; i >= 0; i--) {
                    const seg = segments[i];
                    try {
                        const range = document.createRange();
                        range.setStart(seg.node, seg.start);
                        range.setEnd(seg.node, seg.end);
                        const mark = document.createElement('mark');
                        mark.className = 'ds-highlight';
                        mark.dataset.highlightId = hl.id;
                        if (hl.color) mark.style.backgroundColor = hl.color;
                        range.surroundContents(mark);
                    } catch (e) {
                        // Range surround can fail across element boundaries —
                        // skip silently.
                    }
                }
            }
        });
    }

    // ─── Selection reporting ──────────────────────────────────────────

    let currentSpineHref = '';
    let currentSpineIndexForSelection = 0;

    function reportSelection() {
        const sel = window.getSelection();
        if (!sel || sel.isCollapsed || !sel.rangeCount) {
            postEvent('selectionCleared');
            return null;
        }
        const range = sel.getRangeAt(0);
        const text = sel.toString().trim();
        if (!text) {
            postEvent('selectionCleared');
            return null;
        }

        // Find the owning chapter for this selection.
        let node = range.startContainer;
        let chapterEl = null;
        while (node && node !== document.body) {
            if (node.nodeType === 1 && node.classList && node.classList.contains('ds-chapter')) {
                chapterEl = node;
                break;
            }
            node = node.parentNode;
        }
        if (!chapterEl) return null;

        const spineIndex = parseInt(chapterEl.dataset.spineIndex, 10) || 0;
        const spineHref = chapterEl.dataset.spineHref || currentSpineHref;

        const preRange = document.createRange();
        preRange.selectNodeContents(chapterEl);
        preRange.setEnd(range.startContainer, range.startOffset);
        const rangeStart = preRange.toString().length;

        const rect = range.getBoundingClientRect();
        const payload = {
            text: text,
            rangeStart: rangeStart,
            rangeEnd: rangeStart + text.length,
            rectX: rect.x,
            rectY: rect.y,
            rectWidth: rect.width,
            rectHeight: rect.height,
            spineIndex: spineIndex,
            spineHref: spineHref
        };
        postEvent('selectionChanged', payload);
        return payload;
    }

    let _selectionTimer = null;
    document.addEventListener('selectionchange', function () {
        if (_selectionTimer) clearTimeout(_selectionTimer);
        _selectionTimer = setTimeout(reportSelection, SELECTION_DEBOUNCE_MS);
    });

    // ─── Link + image interception ────────────────────────────────────

    document.addEventListener('click', function (e) {
        const link = e.target.closest && e.target.closest('a[href]');
        if (link) {
            const href = link.getAttribute('href') || '';
            const isExternal = /^https?:\/\//i.test(href);
            e.preventDefault();
            postEvent('linkTapped', { href: href, isInternal: !isExternal });
            return;
        }
        if (e.target && e.target.tagName === 'IMG') {
            const img = e.target;
            postEvent('imageTapped', {
                src: img.src,
                alt: img.alt || null,
                naturalWidth: img.naturalWidth || 0,
                naturalHeight: img.naturalHeight || 0
            });
        }
    });

    // ─── Layout engines ───────────────────────────────────────────────

    class ScrollLayout {
        constructor(root) {
            this.root = root;
            this.observer = null;
            this.resizeObserver = null;
            this.lastReportedSpine = -1;
            this._sentinelRafPending = false;
        }

        mount(chapters, anchor) {
            this.root.classList.remove('ds-paginated', 'ds-slide', 'ds-fade');
            this.root.innerHTML = '';

            const mounted = [];
            for (const chapter of chapters) {
                const article = buildChapterElement(chapter);
                this.root.appendChild(article);
                mounted.push(chapter.spineIndex);
            }
            mounted.sort(function (a, b) { return a - b; });

            this._installChapterObserver(mounted);
            this._seek(anchor);
        }

        update(chapters, anchor) {
            const wantIDs = new Set(chapters.map(function (c) { return chapterIDFor(c.spineIndex); }));
            const keepAnchorEl = anchor && anchor.elementID
                ? this.root.querySelector('#' + cssEscape(anchor.elementID))
                : null;
            const stableRef = keepAnchorEl || this._firstVisibleChapter();
            const stableOffset = stableRef ? stableRef.getBoundingClientRect().top : 0;

            // Remove chapters not in the new set.
            const existing = Array.from(this.root.querySelectorAll('article.ds-chapter'));
            for (const el of existing) {
                if (!wantIDs.has(el.id)) el.remove();
            }

            // Insert missing chapters in order.
            for (const chapter of chapters) {
                const id = chapterIDFor(chapter.spineIndex);
                if (this.root.querySelector('#' + cssEscape(id))) continue;
                const article = buildChapterElement(chapter);
                const next = this._findInsertionSuccessor(chapter.spineIndex);
                if (next) this.root.insertBefore(article, next);
                else this.root.appendChild(article);
            }

            // Restore scroll so the stable reference stays visually in place.
            if (stableRef && document.contains(stableRef)) {
                const newTop = stableRef.getBoundingClientRect().top;
                window.scrollBy(0, newTop - stableOffset);
            }

            const mounted = chapters.map(function (c) { return c.spineIndex; }).sort(function (a, b) { return a - b; });
            this._installChapterObserver(mounted);

            if (anchor && (anchor.elementID || anchor.characterOffset != null || anchor.progress != null)) {
                this._seek(anchor);
            }
        }

        unmount() {
            if (this.observer) { this.observer.disconnect(); this.observer = null; }
            if (this.resizeObserver) { this.resizeObserver.disconnect(); this.resizeObserver = null; }
            this.root.innerHTML = '';
        }

        navigate(anchor) { this._seek(anchor); }

        nextPage() {
            // Scroll by ~one viewport height.
            const vh = window.innerHeight;
            window.scrollBy({ top: vh * 0.9, behavior: 'smooth' });
        }

        prevPage() {
            const vh = window.innerHeight;
            window.scrollBy({ top: -vh * 0.9, behavior: 'smooth' });
        }

        applyHighlights(highlights) {
            applyHighlightsToScope(this.root, highlights);
        }

        removeHighlight(id) {
            const mark = this.root.querySelector('mark.ds-highlight[data-highlight-id="' + cssEscape(id) + '"]');
            if (!mark) return;
            const parent = mark.parentNode;
            while (mark.firstChild) parent.insertBefore(mark.firstChild, mark);
            parent.removeChild(mark);
            if (parent.normalize) parent.normalize();
        }

        // MARK: private

        _firstVisibleChapter() {
            const articles = this.root.querySelectorAll('article.ds-chapter');
            for (const article of articles) {
                const rect = article.getBoundingClientRect();
                if (rect.bottom > 0) return article;
            }
            return null;
        }

        _findInsertionSuccessor(spineIndex) {
            const articles = this.root.querySelectorAll('article.ds-chapter');
            for (const article of articles) {
                const idx = parseInt(article.dataset.spineIndex, 10);
                if (idx > spineIndex) return article;
            }
            return null;
        }

        _seek(anchor) {
            if (!anchor) return;
            const chapterEl = this.root.querySelector('#' + cssEscape(chapterIDFor(anchor.spineIndex)));
            if (!chapterEl) {
                const direction = anchor.spineIndex < (this.lastReportedSpine || 0) ? 'start' : 'end';
                postEvent('boundaryReached', {
                    direction: direction,
                    spineIndex: anchor.spineIndex
                });
                return;
            }
            if (anchor.elementID) {
                const target = chapterEl.querySelector('#' + cssEscape(anchor.elementID));
                if (target) {
                    target.scrollIntoView({ block: 'start', behavior: 'instant' });
                    return;
                }
            }
            if (typeof anchor.characterOffset === 'number') {
                const nodes = collectTextNodes(chapterEl);
                for (const tn of nodes) {
                    if (tn.end >= anchor.characterOffset) {
                        const range = document.createRange();
                        range.setStart(tn.node, anchor.characterOffset - tn.start);
                        range.collapse(true);
                        const rect = range.getBoundingClientRect();
                        window.scrollTo({
                            top: window.scrollY + rect.top - 60,
                            behavior: 'instant'
                        });
                        return;
                    }
                }
            }
            if (typeof anchor.progress === 'number') {
                const rect = chapterEl.getBoundingClientRect();
                const top = window.scrollY + rect.top + rect.height * Math.max(0, Math.min(1, anchor.progress));
                window.scrollTo({ top: top, behavior: 'instant' });
                return;
            }
            const top = window.scrollY + chapterEl.getBoundingClientRect().top;
            window.scrollTo({ top: top, behavior: 'instant' });
        }

        _installChapterObserver(mounted) {
            if (this.observer) this.observer.disconnect();

            const options = {
                root: null,
                rootMargin: '0px 0px -45% 0px',
                threshold: 0
            };

            this.observer = new IntersectionObserver((entries) => {
                let bestIndex = -1;
                let bestTop = Infinity;
                entries.forEach(function (entry) {
                    if (!entry.isIntersecting) return;
                    const idx = parseInt(entry.target.dataset.spineIndex, 10);
                    const top = entry.boundingClientRect.top;
                    if (top < bestTop) {
                        bestTop = top;
                        bestIndex = idx;
                    }
                });
                if (bestIndex >= 0 && bestIndex !== this.lastReportedSpine) {
                    this.lastReportedSpine = bestIndex;
                    postEvent('chapterChanged', { spineIndex: bestIndex });
                }
                this._scheduleBoundaryCheck(mounted);
                this._reportProgress();
            }, options);

            const articles = this.root.querySelectorAll('article.ds-chapter');
            articles.forEach((article) => this.observer.observe(article));

            // Resize → recompute progress (no re-mount needed).
            if (this.resizeObserver) this.resizeObserver.disconnect();
            this.resizeObserver = new ResizeObserver(() => this._reportProgress());
            this.resizeObserver.observe(this.root);
        }

        _scheduleBoundaryCheck(mounted) {
            if (this._sentinelRafPending) return;
            this._sentinelRafPending = true;
            requestAnimationFrame(() => {
                this._sentinelRafPending = false;
                this._checkBoundaries(mounted);
            });
        }

        _checkBoundaries(mounted) {
            if (!mounted.length) return;
            const first = mounted[0];
            const last = mounted[mounted.length - 1];
            const firstEl = this.root.querySelector('#' + cssEscape(chapterIDFor(first)));
            const lastEl = this.root.querySelector('#' + cssEscape(chapterIDFor(last)));
            const vh = window.innerHeight;
            if (firstEl) {
                const rect = firstEl.getBoundingClientRect();
                if (rect.top > -vh * 0.5 && first > 0) {
                    postEvent('boundaryReached', { direction: 'start', spineIndex: first });
                }
            }
            if (lastEl) {
                const rect = lastEl.getBoundingClientRect();
                if (rect.bottom < vh * 1.5) {
                    postEvent('boundaryReached', { direction: 'end', spineIndex: last });
                }
            }
        }

        _reportProgress() {
            const docH = document.documentElement.scrollHeight;
            const vh = window.innerHeight;
            const max = Math.max(docH - vh, 1);
            const overall = Math.min(1, Math.max(0, window.scrollY / max));
            postEvent('progressUpdated', { overall: overall });
        }
    }

    class PaginatedLayout {
        constructor(root) {
            this.root = root;
            this.transition = 'slide';
            this.chapters = []; // [{spineIndex, pageCount}]
            this.absolutePageCount = 0;
            this.absolutePageIndex = 0;
            this.pagesEl = null;
            this.tapZonesEl = null;
            this._resizeHandler = null;
        }

        mount(chapters, anchor) {
            this.root.innerHTML = '';
            this.root.classList.add('ds-paginated');
            this._setTransitionClass();

            this.pagesEl = document.createElement('div');
            this.pagesEl.id = 'ds-pages';
            this.root.appendChild(this.pagesEl);

            this._installTapZones();

            this.chapters = this._buildPages(chapters);
            this.absolutePageCount = this.chapters.reduce(function (sum, c) { return sum + c.pageCount; }, 0);
            this._seek(anchor);

            this._resizeHandler = () => this._rebuild();
            window.addEventListener('resize', this._resizeHandler, { passive: true });

            postEvent('ready'); // engine-level ready: controller already ready but re-signal on mode change
        }

        update(chapters, anchor) {
            const currentIndex = this.absolutePageIndex;
            const currentChapter = this._chapterAtAbsolutePage(currentIndex);
            const fallbackAnchor = anchor || (currentChapter
                ? { spineIndex: currentChapter.spineIndex, progress: this._chapterProgressAt(currentIndex) }
                : null);

            this.pagesEl.innerHTML = '';
            this.chapters = this._buildPages(chapters);
            this.absolutePageCount = this.chapters.reduce(function (sum, c) { return sum + c.pageCount; }, 0);
            this._seek(fallbackAnchor);
        }

        unmount() {
            if (this._resizeHandler) {
                window.removeEventListener('resize', this._resizeHandler);
                this._resizeHandler = null;
            }
            this.root.classList.remove('ds-paginated', 'ds-slide', 'ds-fade');
            this.root.innerHTML = '';
            this.chapters = [];
            this.pagesEl = null;
            this.tapZonesEl = null;
            this.absolutePageCount = 0;
            this.absolutePageIndex = 0;
        }

        setTransition(transition) {
            this.transition = transition || 'slide';
            this._setTransitionClass();
        }

        navigate(anchor) { this._seek(anchor); }

        nextPage() {
            if (this.absolutePageIndex >= this.absolutePageCount - 1) {
                const last = this.chapters[this.chapters.length - 1];
                postEvent('boundaryReached', {
                    direction: 'end',
                    spineIndex: last ? last.spineIndex : 0
                });
                return;
            }
            this._goTo(this.absolutePageIndex + 1);
        }

        prevPage() {
            if (this.absolutePageIndex <= 0) {
                const first = this.chapters[0];
                postEvent('boundaryReached', {
                    direction: 'start',
                    spineIndex: first ? first.spineIndex : 0
                });
                return;
            }
            this._goTo(this.absolutePageIndex - 1);
        }

        applyHighlights(highlights) {
            applyHighlightsToScope(this.root, highlights);
        }

        removeHighlight(id) {
            const mark = this.root.querySelector('mark.ds-highlight[data-highlight-id="' + cssEscape(id) + '"]');
            if (!mark) return;
            const parent = mark.parentNode;
            while (mark.firstChild) parent.insertBefore(mark.firstChild, mark);
            parent.removeChild(mark);
            if (parent.normalize) parent.normalize();
        }

        // MARK: private

        _setTransitionClass() {
            this.root.classList.remove('ds-slide', 'ds-fade');
            this.root.classList.add(this.transition === 'fade' ? 'ds-fade' : 'ds-slide');
        }

        _installTapZones() {
            this.tapZonesEl = document.createElement('div');
            this.tapZonesEl.className = 'ds-tap-zones';
            this.tapZonesEl.setAttribute('aria-hidden', 'false');

            const isRTL = (document.documentElement.getAttribute('dir') || '').toLowerCase() === 'rtl';

            const left = document.createElement('button');
            left.type = 'button';
            left.className = 'ds-tap-zone';
            left.setAttribute('aria-label', isRTL ? 'Next page' : 'Previous page');
            left.addEventListener('click', (e) => {
                if (window.getSelection && window.getSelection().toString().length > 0) return;
                e.preventDefault();
                isRTL ? this.nextPage() : this.prevPage();
            });

            const right = document.createElement('button');
            right.type = 'button';
            right.className = 'ds-tap-zone';
            right.setAttribute('aria-label', isRTL ? 'Previous page' : 'Next page');
            right.addEventListener('click', (e) => {
                if (window.getSelection && window.getSelection().toString().length > 0) return;
                e.preventDefault();
                isRTL ? this.prevPage() : this.nextPage();
            });

            this.tapZonesEl.appendChild(left);
            this.tapZonesEl.appendChild(right);
            this.root.appendChild(this.tapZonesEl);
        }

        _buildPages(chapterDescriptors) {
            const vw = this.root.clientWidth || window.innerWidth;
            const vh = this.root.clientHeight || window.innerHeight;

            const chapterRecords = [];
            for (const descriptor of chapterDescriptors) {
                const pages = this._paginateChapter(descriptor, vw, vh);
                chapterRecords.push({
                    spineIndex: descriptor.spineIndex,
                    spineHref: descriptor.spineHref || '',
                    pageCount: pages.length
                });
                for (const pageEl of pages) {
                    pageEl.dataset.spineIndex = String(descriptor.spineIndex);
                    this.pagesEl.appendChild(pageEl);
                }
            }
            return chapterRecords;
        }

        _paginateChapter(descriptor, vw, vh) {
            // Measurement container (hidden, laid out at actual page size).
            const measureRoot = document.createElement('div');
            measureRoot.className = 'ds-measure';
            measureRoot.style.width = vw + 'px';
            measureRoot.style.height = 'auto';

            const measureChapter = buildChapterElement(descriptor);
            measureRoot.appendChild(measureChapter);
            document.body.appendChild(measureRoot);

            const pages = [];
            try {
                const nodes = Array.from(measureChapter.childNodes);
                // Depth-1 block list — we slice at block boundaries for simplicity
                // and predictability. Inline-only content falls back to a single
                // page per chapter.
                let currentPage = this._createPageElement(vw, vh);
                let currentPageContent = document.createElement('article');
                currentPageContent.className = 'ds-chapter';
                currentPageContent.id = chapterIDFor(descriptor.spineIndex);
                currentPageContent.dataset.spineIndex = String(descriptor.spineIndex);
                currentPageContent.dataset.spineHref = descriptor.spineHref || '';
                currentPage.appendChild(currentPageContent);

                const cloneIntoPage = (node) => {
                    const clone = node.cloneNode(true);
                    currentPageContent.appendChild(clone);
                };

                const commitPage = () => {
                    pages.push(currentPage);
                    currentPage = this._createPageElement(vw, vh);
                    currentPageContent = document.createElement('article');
                    currentPageContent.className = 'ds-chapter';
                    currentPageContent.id = chapterIDFor(descriptor.spineIndex);
                    currentPageContent.dataset.spineIndex = String(descriptor.spineIndex);
                    currentPageContent.dataset.spineHref = descriptor.spineHref || '';
                    currentPage.appendChild(currentPageContent);
                };

                // Temporarily reset measure container height to viewport so
                // overflow tests reflect real pagination geometry.
                measureRoot.style.height = 'auto';

                for (const node of nodes) {
                    cloneIntoPage(node);
                    // Temporarily attach this page to measurement DOM to probe.
                    measureRoot.appendChild(currentPage);
                    const overflowed = currentPageContent.scrollHeight > vh;
                    measureRoot.removeChild(currentPage);

                    if (overflowed) {
                        // Remove the just-added clone to keep prior page valid.
                        const last = currentPageContent.lastChild;
                        if (last) currentPageContent.removeChild(last);

                        // Only commit if the page has real content; otherwise
                        // the node itself is taller than one page — accept the
                        // overflow and move on.
                        if (currentPageContent.childNodes.length > 0) {
                            commitPage();
                            cloneIntoPage(node);
                        } else {
                            // Oversize single node — keep it and commit anyway.
                            cloneIntoPage(node);
                            commitPage();
                        }
                    }
                }
                // Always commit the trailing page (even if empty — chapter must
                // contribute ≥ 1 page to make pagination math well-defined).
                pages.push(currentPage);
            } finally {
                if (measureRoot.parentNode) measureRoot.parentNode.removeChild(measureRoot);
            }

            return pages;
        }

        _createPageElement(vw, vh) {
            const page = document.createElement('div');
            page.className = 'ds-page';
            page.style.width = '100%';
            page.style.height = vh + 'px';
            page.style.maxHeight = vh + 'px';
            page.style.overflow = 'hidden';
            return page;
        }

        _chapterAtAbsolutePage(abs) {
            let running = 0;
            for (const c of this.chapters) {
                if (abs < running + c.pageCount) {
                    return { spineIndex: c.spineIndex, localPage: abs - running, pageCount: c.pageCount };
                }
                running += c.pageCount;
            }
            return null;
        }

        _chapterProgressAt(abs) {
            const info = this._chapterAtAbsolutePage(abs);
            if (!info || info.pageCount <= 1) return 0;
            return info.localPage / (info.pageCount - 1);
        }

        _absolutePageForAnchor(anchor) {
            if (!anchor) return 0;
            let running = 0;
            for (const c of this.chapters) {
                if (c.spineIndex === anchor.spineIndex) {
                    if (anchor.elementID) {
                        const el = this.pagesEl.querySelector('#' + cssEscape(anchor.elementID));
                        if (el) {
                            const pageEl = el.closest('.ds-page');
                            if (pageEl) {
                                const pages = Array.from(this.pagesEl.children);
                                return pages.indexOf(pageEl);
                            }
                        }
                    }
                    if (typeof anchor.characterOffset === 'number') {
                        const chapterPages = this._pagesForChapter(c.spineIndex);
                        let offset = 0;
                        for (let i = 0; i < chapterPages.length; i++) {
                            const text = chapterPages[i].textContent || '';
                            if (offset + text.length >= anchor.characterOffset) {
                                return running + i;
                            }
                            offset += text.length;
                        }
                    }
                    if (typeof anchor.progress === 'number') {
                        const local = Math.min(c.pageCount - 1, Math.floor(anchor.progress * c.pageCount));
                        return running + Math.max(0, local);
                    }
                    return running;
                }
                running += c.pageCount;
            }
            // Anchor outside window.
            return -1;
        }

        _pagesForChapter(spineIndex) {
            const all = Array.from(this.pagesEl.children);
            return all.filter(function (page) {
                return parseInt(page.dataset.spineIndex, 10) === spineIndex;
            });
        }

        _rebuild() {
            // On resize, re-paginate using the same descriptors. Descriptors
            // are not retained verbatim — rebuild from the current DOM pages.
            const current = this.absolutePageIndex;
            const info = this._chapterAtAbsolutePage(current);
            const anchor = info ? { spineIndex: info.spineIndex, progress: this._chapterProgressAt(current) } : null;
            const descriptors = this.chapters.map((c) => {
                const pages = this._pagesForChapter(c.spineIndex);
                const bodyHTML = pages.map(function (p) {
                    const article = p.querySelector('article.ds-chapter');
                    return article ? article.innerHTML : '';
                }).join('');
                return { spineIndex: c.spineIndex, spineHref: c.spineHref, bodyHTML: bodyHTML };
            });
            this.pagesEl.innerHTML = '';
            this.chapters = this._buildPages(descriptors);
            this.absolutePageCount = this.chapters.reduce(function (sum, c) { return sum + c.pageCount; }, 0);
            this._seek(anchor);
        }

        _seek(anchor) {
            const target = this._absolutePageForAnchor(anchor);
            if (target < 0) {
                // Anchor outside mounted window — surface via boundary event.
                if (anchor) {
                    const first = this.chapters[0];
                    const last = this.chapters[this.chapters.length - 1];
                    if (first && anchor.spineIndex < first.spineIndex) {
                        postEvent('boundaryReached', { direction: 'start', spineIndex: first.spineIndex });
                    } else if (last && anchor.spineIndex > last.spineIndex) {
                        postEvent('boundaryReached', { direction: 'end', spineIndex: last.spineIndex });
                    }
                }
                this._goTo(0);
                return;
            }
            this._goTo(target);
        }

        _goTo(index) {
            const max = Math.max(0, this.absolutePageCount - 1);
            const clamped = Math.max(0, Math.min(max, index));
            this.absolutePageIndex = clamped;

            if (this.transition === 'fade') {
                this.pagesEl.style.opacity = '0';
                setTimeout(() => {
                    this.root.style.setProperty('--ds-page-index', String(clamped));
                    this.pagesEl.style.opacity = '1';
                }, 180);
            } else {
                this.root.style.setProperty('--ds-page-index', String(clamped));
            }

            const info = this._chapterAtAbsolutePage(clamped);
            if (info && info.spineIndex !== currentSpineIndexForSelection) {
                currentSpineIndexForSelection = info.spineIndex;
                postEvent('chapterChanged', { spineIndex: info.spineIndex });
            }
            postEvent('progressUpdated', {
                overall: this.absolutePageCount > 1 ? clamped / (this.absolutePageCount - 1) : 0,
                pageIndex: clamped,
                pageCount: this.absolutePageCount
            });
        }
    }

    // ─── Controller ───────────────────────────────────────────────────

    class ReaderController {
        constructor() {
            this.root = null;
            this.layout = null;
            this.mode = { mode: 'scroll', transition: null };
        }

        init() {
            ensureBaseStyle();
            this.root = ensureRoot();
            this._ensureLayout();
            postEvent('ready');
        }

        dispatch(jsonString) {
            let command;
            try {
                command = JSON.parse(jsonString);
            } catch (e) {
                return;
            }
            if (!command || !command.type) return;
            const payload = command.payload || {};

            switch (command.type) {
                case 'setMode':
                    this._setMode(payload.mode, payload.anchor);
                    break;
                case 'mountChapters':
                    this._mount(payload.chapters || [], payload.anchor);
                    break;
                case 'navigate':
                    if (this.layout) this.layout.navigate(payload.anchor);
                    break;
                case 'nextPage':
                    if (this.layout) this.layout.nextPage();
                    break;
                case 'prevPage':
                    if (this.layout) this.layout.prevPage();
                    break;
                case 'applyHighlights':
                    if (this.layout) this.layout.applyHighlights(payload.highlights || []);
                    break;
                case 'removeHighlight':
                    if (this.layout) this.layout.removeHighlight(payload.id);
                    break;
                case 'applyTheme':
                    this._applyTheme(payload.css || '');
                    break;
                case 'updateStyle':
                    this._updateStyle(payload.variables || {});
                    break;
                case 'setSpineHref':
                    currentSpineHref = payload.href || '';
                    break;
                case 'showHighlightPicker':
                    this._showHighlightPicker();
                    break;
                case 'unmount':
                    this._unmount();
                    break;
                default:
                    break;
            }
        }

        // MARK: private

        _ensureLayout() {
            if (this.layout) return;
            this.layout = new ScrollLayout(this.root);
        }

        _setMode(modeDescriptor, anchor) {
            const nextMode = (modeDescriptor && modeDescriptor.mode) || 'scroll';
            const transition = (modeDescriptor && modeDescriptor.transition) || 'slide';
            this.mode = { mode: nextMode, transition: transition };

            if (this.layout) this.layout.unmount();
            this.layout = nextMode === 'paginated'
                ? new PaginatedLayout(this.root)
                : new ScrollLayout(this.root);
            if (this.layout instanceof PaginatedLayout) {
                this.layout.setTransition(transition);
            }
            // No content yet — the Swift side will follow with mountChapters.
        }

        _mount(chapters, anchor) {
            if (!this.layout) this._ensureLayout();
            if (this.layout._mounted) {
                this.layout.update(chapters, anchor);
            } else {
                this.layout.mount(chapters, anchor);
                this.layout._mounted = true;
            }
        }

        _unmount() {
            if (this.layout) {
                this.layout.unmount();
                this.layout._mounted = false;
            }
        }

        _applyTheme(css) {
            let el = document.getElementById('ds-theme');
            if (!el) {
                el = document.createElement('style');
                el.id = 'ds-theme';
                document.head.appendChild(el);
            }
            el.textContent = css;
        }

        _updateStyle(variables) {
            const root = document.documentElement;
            Object.keys(variables).forEach(function (key) {
                root.style.setProperty(key, variables[key]);
            });
        }

        _showHighlightPicker() {
            _hidePicker();
            const sel = window.getSelection();
            if (!sel || sel.isCollapsed || !sel.rangeCount) return;
            const range = sel.getRangeAt(0);
            const rect = range.getBoundingClientRect();
            if (rect.width === 0 && rect.height === 0) return;

            const colors = [
                { hex: '#F7C948' },
                { hex: '#69DB7C' },
                { hex: '#74C0FC' },
                { hex: '#FFA8A8' },
                { hex: '#B197FC' }
            ];
            const bar = document.createElement('div');
            bar.id = 'ds-picker';
            const barWidth = 298;
            const barHeight = 44;
            const left = Math.max(8, Math.min(window.innerWidth - barWidth - 8, rect.left + rect.width / 2 - barWidth / 2));
            const top = rect.bottom + 6 + barHeight > window.innerHeight
                ? rect.top - barHeight - 6
                : rect.bottom + 6;
            bar.style.cssText = [
                'position:fixed', 'z-index:99999',
                'display:flex', 'align-items:center', 'justify-content:center', 'gap:16px',
                'width:' + barWidth + 'px',
                'height:' + barHeight + 'px',
                'top:' + top + 'px', 'left:' + left + 'px',
                'pointer-events:auto', 'border-radius:14px',
                'background:rgba(30,30,30,0.9)',
                'box-shadow:0 2px 16px rgba(0,0,0,0.35)'
            ].join(';');

            const selectionSnapshot = reportSelection();

            colors.forEach(function (c) {
                const dot = document.createElement('button');
                dot.type = 'button';
                dot.setAttribute('aria-label', 'Highlight ' + c.hex);
                dot.style.cssText = [
                    'width:28px', 'height:28px', 'border-radius:50%', 'border:none',
                    'padding:0', 'margin:0', 'cursor:pointer',
                    'background:' + c.hex, 'flex-shrink:0',
                    '-webkit-tap-highlight-color:transparent'
                ].join(';');
                dot.addEventListener('click', function (e) {
                    e.preventDefault();
                    if (selectionSnapshot) {
                        postEvent('highlightRequested', {
                            selection: selectionSnapshot,
                            tintHex: c.hex
                        });
                    }
                    _hidePicker();
                });
                bar.appendChild(dot);
            });

            document.body.appendChild(bar);
            _pickerEl = bar;
        }
    }

    // ─── Picker helpers ───────────────────────────────────────────────

    let _pickerEl = null;
    function _hidePicker() {
        if (_pickerEl && _pickerEl.parentNode) _pickerEl.parentNode.removeChild(_pickerEl);
        _pickerEl = null;
    }
    window.addEventListener('scroll', _hidePicker, { passive: true });

    // ─── CSS.escape polyfill (WKWebView lacks it for older builds) ────

    function cssEscape(value) {
        if (window.CSS && window.CSS.escape) return window.CSS.escape(value);
        return String(value).replace(/([\0-\x1f\x7f!"$%&'()*+,./:;<=>?@[\\\]^`{|}~ ])/g, '\\$1');
    }

    // ─── Boot ─────────────────────────────────────────────────────────

    const controller = new ReaderController();
    window.__dsReader = controller;

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', function () { controller.init(); });
    } else {
        controller.init();
    }

})();
