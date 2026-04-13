# DualSpine: Dual-Track EPUB Engine

## Overview

DualSpine is a custom EPUB engine built from scratch to serve two masters simultaneously:

1. **Visual Track (DualSpineRender):** Blazingly fast EPUB rendering via `WKWebView` + custom `WKURLSchemeHandler`, bypassing GCDWebServer entirely.
2. **Semantic Track (DualSpineSemantic):** RAG-ready knowledge extraction — semantic chunking, vector embeddings, and hybrid retrieval — adapted from Karpathy's "Repomap" concept for books.

Built for integration into [ReBabel](https://github.com/shiyukk/ReBabel), replacing Readium.

## Architecture

```
DualSpine/
├── DualSpineCore        # EPUB parsing, models (no UI dependency)
│   ├── Archive/         # ZIP reading via ZIPFoundation
│   ├── Parser/          # container.xml → OPF → TOC parsing
│   └── Models/          # EPUBDocument, EPUBPackage, TOCNode, etc.
├── DualSpineRender      # WKWebView rendering (iOS/macOS)
│   ├── SchemeHandler/   # WKURLSchemeHandler serving from ZIP
│   ├── Bridge/          # JS ↔ Swift message bridge
│   └── View/            # SwiftUI EPUBReaderView
└── DualSpineSemantic    # AI/RAG pipeline
    ├── Chunking/        # SwiftSoup-based semantic chunker
    ├── Models/          # SemanticChunk, BookRepomap
    └── Retrieval/       # Vector index, hybrid retrieval, context assembly
```

## Key Design Decisions

### Why WKWebView over TextKit 2?
EPUB's core contract is styled XHTML. Publisher EPUBs use real CSS (flexbox, float, media queries, complex tables, embedded fonts, MathML). TextKit 2 cannot replicate any of this. WKWebView uses the same WebKit engine — CSS fidelity is 100% guaranteed.

### Why WKURLSchemeHandler over GCDWebServer?
`WKURLSchemeHandler` serves resources in-process directly from the ZIP archive. No HTTP server, no port binding, no localhost security issues. Strictly superior.

### Why SwiftSoup over XMLParser?
EPUB XHTML in the wild is frequently not well-formed XML. SwiftSoup handles malformed HTML gracefully and provides CSS selector API for semantic boundary detection.

### Why brute-force cosine similarity?
At book scale (~5,000 chunks × 384 dimensions = 7.5MB), brute-force with vDSP runs in ~2ms on A15. No need for FAISS/Annoy.

## Prompt Strategy (Three-Tier Context)

```
Tier 1: Book Repomap (~500-1500 tokens, always included)
  → TOC with section summaries, global entities, classification

Tier 2: Retrieved Chunks (~2000-4000 tokens, query-dependent)
  → Top-K from hybrid retrieval (vector + BM25 via Reciprocal Rank Fusion)

Tier 3: Local Context (~500-1000 tokens, selection-dependent)
  → Current paragraph + surrounding text from reading position
```

## Dependencies

- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) — ZIP archive reading
- [SwiftSoup](https://github.com/scinfu/SwiftSoup) — HTML/XHTML parsing

## Phased Roadmap

| Phase | Focus | Status |
|-------|-------|--------|
| 0 | EPUB parsing (ZIP + OPF + Spine + TOC) | ✅ Scaffolded |
| 1 | Visual rendering (WKWebView + SchemeHandler + JS bridge) | ✅ Scaffolded |
| 2 | Semantic parsing (chunker + repomap) | ✅ Scaffolded |
| 3 | Vector embeddings (CoreML + vDSP index) | 🔲 Planned |
| 4 | Readium removal from ReBabel | 🔲 Planned |
| 5 | Cross-book knowledge graph | 🔲 Planned |
