import SwiftUI
import WebKit
import DualSpineCore
import DualSpineRender

struct ContentView: View {
    @State private var document: EPUBDocument?
    @State private var archive: EPUBArchive?
    @State private var resourceActor: EPUBResourceActor?
    @State private var spineIndex = 0
    @State private var errorMessage: String?
    @State private var appearance = ReadingAppearanceSettings()
    @State private var showTOC = false
    @State private var showAppearance = false
    @State private var showSearch = false
    @State private var currentProgress: Double = 0
    @State private var highlights: [HighlightRecord] = []
    @State private var currentPage = 0
    @State private var totalPages = 1

    private let epubPath = "/Users/shiyuliu/Documents/DualSpine/books"
    private let positionStore = PositionStore()

    var body: some View {
        NavigationStack {
            mainContent
                .navigationTitle(document?.title ?? "DualSpine")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .task { await loadEPUB() }
                .sheet(isPresented: $showTOC) { tocSheet }
                .sheet(isPresented: $showAppearance) { appearanceSheet }
                .sheet(isPresented: $showSearch) { searchSheet }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if let document, let resourceActor {
            ReaderContentView(
                document: document,
                resourceActor: resourceActor,
                spineIndex: $spineIndex,
                appearance: appearance,
                currentProgress: $currentProgress,
                currentPage: $currentPage,
                totalPages: $totalPages,
                highlights: highlights,
                onHighlightRequest: { sel, hex in createHighlight(selection: sel, tintHex: hex) },
                onRemoveHighlightRequest: { id in highlights.removeAll { $0.id.uuidString == id } },
                onProgressSave: { savePosition(document: document) }
            )
        } else if let errorMessage {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.red)
                Text(errorMessage).multilineTextAlignment(.center).padding()
            }
        } else {
            ProgressView("Loading EPUB...")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { showTOC = true } label: { Image(systemName: "list.bullet") }
                .disabled(document == nil)
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { showSearch = true } label: { Image(systemName: "magnifyingglass") }
                .disabled(document == nil)
            Button { showAppearance = true } label: { Image(systemName: "textformat.size") }
        }
    }

    // MARK: - Sheets

    private var tocSheet: some View {
        NavigationStack {
            TOCListView(document: document, spineIndex: spineIndex) { entry in
                navigateToTOCEntry(entry); showTOC = false
            }
            .navigationTitle("Table of Contents").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showTOC = false } } }
        }
    }

    private var appearanceSheet: some View {
        NavigationStack {
            AppearanceSettingsView(appearance: $appearance)
                .navigationTitle("Appearance").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showAppearance = false } } }
        }
        .presentationDetents([.medium, .large])
    }

    private var searchSheet: some View {
        NavigationStack {
            SearchView(document: document, archive: archive) { result in
                spineIndex = result.spineIndex; showSearch = false
            }
            .navigationTitle("Search").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showSearch = false } } }
        }
    }

    // MARK: - Logic

    private func loadEPUB() async {
        do {
            let booksURL = URL(fileURLWithPath: epubPath)
            let contents = try FileManager.default.contentsOfDirectory(at: booksURL, includingPropertiesForKeys: nil)
            guard let epubURL = contents.first(where: {
                $0.pathExtension == "epub" && $0.lastPathComponent.contains("First Love")
            }) ?? contents.first(where: { $0.pathExtension == "epub" }) else {
                errorMessage = "No EPUB files found"; return
            }
            let doc = try EPUBParser.parse(at: epubURL)
            let arch = try EPUBArchive(at: epubURL)
            let actor = EPUBResourceActor(archiveURL: epubURL, contentBasePath: doc.contentBasePath)
            self.document = doc; self.archive = arch; self.resourceActor = actor

            let bookID = doc.package.metadata.identifier ?? doc.title
            if let saved = positionStore.load(forBook: bookID) {
                spineIndex = saved.spineIndex; currentProgress = saved.overallProgress
            }
        } catch { errorMessage = error.localizedDescription }
    }

    private func savePosition(document: EPUBDocument) {
        let bookID = document.package.metadata.identifier ?? document.title
        let pos = ReadingPosition(
            spineIndex: spineIndex,
            spineHref: document.package.resolvedSpine[safe: spineIndex]?.1.href ?? "",
            chapterProgress: 0, overallProgress: currentProgress
        )
        positionStore.save(position: pos, forBook: bookID)
    }

    private func navigateToTOCEntry(_ entry: FlatTOCEntry) {
        guard let document, let href = entry.href else { return }
        for (i, (_, m)) in document.package.resolvedSpine.enumerated() {
            if m.href == href || m.href.hasSuffix(href) || href.hasSuffix(m.href) { spineIndex = i; return }
        }
    }

    private func createHighlight(selection: EPUBBridgeMessage.SelectionPayload, tintHex: String) {
        highlights.append(HighlightRecord(
            spineIndex: spineIndex, spineHref: selection.spineHref,
            selectedText: selection.text, rangeStart: selection.rangeStart,
            rangeEnd: selection.rangeEnd, tintHex: tintHex
        ))
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Reader Content View

struct ReaderContentView: View {
    let document: EPUBDocument
    let resourceActor: EPUBResourceActor
    @Binding var spineIndex: Int
    let appearance: ReadingAppearanceSettings
    @Binding var currentProgress: Double
    @Binding var currentPage: Int
    @Binding var totalPages: Int
    let highlights: [HighlightRecord]
    let onHighlightRequest: (EPUBBridgeMessage.SelectionPayload, String) -> Void
    let onRemoveHighlightRequest: (String) -> Void
    let onProgressSave: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            EPUBReaderView(
                document: document,
                resourceActor: resourceActor,
                spineIndex: $spineIndex,
                themeCSS: ReadingCSSGenerator.generateCSS(for: appearance),
                isPaginated: !appearance.isScrollEnabled,
                highlights: highlights,
                onMessage: { handleMessage($0) },
                onHighlightRequest: { sel, hex in onHighlightRequest(sel, hex) },
                onRemoveHighlightRequest: { id in onRemoveHighlightRequest(id) }
            )

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.gray.opacity(0.3))
                    Rectangle().fill(Color.accentColor).frame(width: geo.size.width * currentProgress)
                }
            }.frame(height: 3)

            HStack {
                Button { if spineIndex > 0 { spineIndex -= 1 } } label: {
                    Image(systemName: "chevron.left")
                }.disabled(spineIndex == 0)
                Spacer()
                VStack(spacing: 2) {
                    if !appearance.isScrollEnabled {
                        Text("Page \(currentPage + 1) of \(totalPages)").font(.caption)
                    }
                    Text("Ch \(spineIndex + 1)/\(document.spineCount) · \(Int(currentProgress * 100))%")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Button { if spineIndex < document.spineCount - 1 { spineIndex += 1 } } label: {
                    Image(systemName: "chevron.right")
                }.disabled(spineIndex >= document.spineCount - 1)
            }
            .padding(.horizontal).padding(.vertical, 8).background(.bar)
        }
    }

    private func handleMessage(_ message: EPUBBridgeMessage) {
        switch message {
        case .progressUpdated(let p):
            currentProgress = ReadingPosition.computeOverallProgress(
                spineIndex: spineIndex, chapterProgress: p.chapterProgress, totalSpineItems: document.spineCount)
            onProgressSave()
        case .contentReady:
            currentProgress = ReadingPosition.computeOverallProgress(
                spineIndex: spineIndex, chapterProgress: 0, totalSpineItems: document.spineCount)
            onProgressSave()
        case .pageChanged(let p):
            currentPage = p.currentPage; totalPages = p.totalPages
            currentProgress = ReadingPosition.computeOverallProgress(
                spineIndex: spineIndex, chapterProgress: p.progress, totalSpineItems: document.spineCount)
            onProgressSave()
        default: break
        }
    }
}

// MARK: - Appearance Settings View

struct AppearanceSettingsView: View {
    @Binding var appearance: ReadingAppearanceSettings

    var body: some View {
        List {
            // Presets
            Section("Presets") {
                ForEach(ReadingAppearancePreset.allCases) { preset in
                    Button {
                        preset.apply(to: &appearance)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.displayName).foregroundStyle(.primary)
                            Text(preset.description).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // Theme
            Section("Theme") {
                Picker("Theme", selection: $appearance.theme) {
                    ForEach(ReadingTheme.allCases) { theme in
                        HStack {
                            Circle().fill(Color(hex: theme.backgroundColor))
                                .overlay(Circle().stroke(Color.gray, lineWidth: 1))
                                .frame(width: 22, height: 22)
                            Text(theme.displayName)
                        }.tag(theme)
                    }
                }.pickerStyle(.segmented)
            }

            // Typography
            Section("Typography") {
                // Font style
                Picker("Font", selection: $appearance.fontStyle) {
                    ForEach(ReadingFontStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }.pickerStyle(.segmented)

                // Font size
                HStack {
                    Text("A").font(.system(size: 14))
                    Slider(value: $appearance.fontSize, in: 12...40, step: 1)
                    Text("A").font(.system(size: 24))
                }

                // Line spacing
                HStack {
                    Image(systemName: "text.alignleft")
                    Slider(value: $appearance.lineSpacing, in: 0...20, step: 1)
                    Image(systemName: "text.alignleft").imageScale(.large)
                }

                // Text alignment
                Picker("Alignment", selection: $appearance.textAlignment) {
                    ForEach(ReadingTextAlignment.allCases) { align in
                        Text(align.displayName).tag(align)
                    }
                }.pickerStyle(.segmented)
            }

            // Layout
            Section("Layout") {
                // Reading mode
                Toggle("Scroll Mode", isOn: $appearance.isScrollEnabled)

                // Page width
                VStack(alignment: .leading, spacing: 4) {
                    Text("Page Width: \(ReadingPageWidth.from(sliderValue: appearance.pageWidthValue).displayName)")
                        .font(.caption).foregroundStyle(.secondary)
                    Slider(value: $appearance.pageWidthValue, in: 0...1)
                }

                // Publisher styles
                Toggle("Publisher Styles", isOn: $appearance.usesPublisherStyles)
            }
        }
    }
}

// MARK: - TOC List View

struct TOCListView: View {
    let document: EPUBDocument?
    let spineIndex: Int
    let onSelect: (FlatTOCEntry) -> Void

    var body: some View {
        List {
            if let document {
                ForEach(Array(document.flatTableOfContents.enumerated()), id: \.offset) { _, entry in
                    Button { onSelect(entry) } label: {
                        HStack {
                            Text(entry.displayTitle).foregroundStyle(.primary)
                            Spacer()
                            if isCurrentEntry(entry) {
                                Image(systemName: "bookmark.fill").foregroundStyle(Color.accentColor).font(.caption)
                            }
                        }
                    }
                }
            }
        }
    }

    private func isCurrentEntry(_ entry: FlatTOCEntry) -> Bool {
        guard let document, let href = entry.href else { return false }
        let resolved = document.package.resolvedSpine
        guard spineIndex < resolved.count else { return false }
        let currentHref = resolved[spineIndex].1.href
        return currentHref == href || currentHref.hasSuffix(href) || href.hasSuffix(currentHref)
    }
}

// MARK: - Search View

struct SearchView: View {
    let document: EPUBDocument?
    let archive: EPUBArchive?
    let onSelect: (BookSearchEngine.SearchResult) -> Void

    @State private var query = ""
    @State private var results: [BookSearchEngine.SearchResult] = []
    @State private var isSearching = false

    var body: some View {
        List {
            if isSearching {
                ProgressView("Searching...")
            } else if results.isEmpty && !query.isEmpty {
                Text("No results found").foregroundStyle(.secondary)
            } else {
                ForEach(results) { result in
                    Button { onSelect(result) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            if let s = result.sectionTitle { Text(s).font(.caption).foregroundStyle(.secondary) }
                            Text(result.context).font(.callout).lineLimit(3).foregroundStyle(.primary)
                        }.padding(.vertical, 2)
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Search in book")
        .onSubmit(of: .search) { performSearch() }
    }

    private func performSearch() {
        guard let document, let archive, !query.isEmpty else { return }
        isSearching = true
        let q = query; let doc = document; let arch = archive
        Task {
            let r = BookSearchEngine.search(query: q, in: doc, archive: arch, maxResults: 30)
            results = r; isSearching = false
        }
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
