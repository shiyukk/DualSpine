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
    @State private var currentTheme: EPUBTheme = .dark
    @State private var showTOC = false
    @State private var showThemePicker = false
    @State private var showSearch = false
    @State private var currentProgress: Double = 0
    @State private var lastSelection: EPUBBridgeMessage.SelectionPayload?
    @State private var highlights: [HighlightRecord] = []
    @State private var showHighlightPicker = false
    @State private var isPaginated = false
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
                .sheet(isPresented: $showThemePicker) { themeSheet }
                .sheet(isPresented: $showSearch) { searchSheet }
                .sheet(isPresented: $showHighlightPicker) { highlightColorSheet }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if let document, let resourceActor {
            ReaderContentView(
                document: document,
                resourceActor: resourceActor,
                spineIndex: $spineIndex,
                currentTheme: currentTheme,
                isPaginated: isPaginated,
                currentProgress: $currentProgress,
                lastSelection: $lastSelection,
                currentPage: $currentPage,
                totalPages: $totalPages,
                highlights: highlights,
                onHighlightRequest: { showHighlightPicker = true },
                onProgressSave: { savePosition(document: document) }
            )
        } else if let errorMessage {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle).foregroundStyle(.red)
                Text(errorMessage).multilineTextAlignment(.center).padding()
            }
        } else {
            ProgressView("Loading EPUB...")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { showTOC = true } label: { Image(systemName: "list.bullet") }
                .disabled(document == nil)
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { showSearch = true } label: { Image(systemName: "magnifyingglass") }
                .disabled(document == nil)
            Button { showThemePicker = true } label: { Image(systemName: "textformat.size") }
        }
    }

    // MARK: - Sheets

    private var tocSheet: some View {
        NavigationStack {
            TOCListView(document: document, spineIndex: spineIndex) { entry in
                navigateToTOCEntry(entry)
                showTOC = false
            }
            .navigationTitle("Table of Contents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { showTOC = false } }
            }
        }
    }

    private var themeSheet: some View {
        NavigationStack {
            ThemePickerView(currentTheme: $currentTheme, isPaginated: $isPaginated)
                .navigationTitle("Appearance")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { Button("Done") { showThemePicker = false } }
                }
        }
        .presentationDetents([.medium])
    }

    private var searchSheet: some View {
        NavigationStack {
            SearchView(document: document, archive: archive) { result in
                spineIndex = result.spineIndex
                showSearch = false
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { showSearch = false } }
            }
        }
    }

    private var highlightColorSheet: some View {
        NavigationStack {
            HighlightColorView { hex in
                createHighlight(tintHex: hex)
                showHighlightPicker = false
            }
            .navigationTitle("Highlight Color")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { showHighlightPicker = false } }
            }
        }
        .presentationDetents([.height(250)])
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

            self.document = doc
            self.archive = arch
            self.resourceActor = actor

            // Restore position
            let bookID = doc.package.metadata.identifier ?? doc.title
            if let saved = positionStore.load(forBook: bookID) {
                spineIndex = saved.spineIndex
                currentProgress = saved.overallProgress
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func savePosition(document: EPUBDocument) {
        let bookID = document.package.metadata.identifier ?? document.title
        let position = ReadingPosition(
            spineIndex: spineIndex,
            spineHref: document.package.resolvedSpine[safe: spineIndex]?.1.href ?? "",
            chapterProgress: 0,
            overallProgress: currentProgress
        )
        positionStore.save(position: position, forBook: bookID)
    }

    private func navigateToTOCEntry(_ entry: FlatTOCEntry) {
        guard let document, let href = entry.href else { return }
        for (i, (_, manifest)) in document.package.resolvedSpine.enumerated() {
            if manifest.href == href || manifest.href.hasSuffix(href) || href.hasSuffix(manifest.href) {
                spineIndex = i; return
            }
        }
    }

    private func createHighlight(tintHex: String) {
        guard let sel = lastSelection else { return }
        let record = HighlightRecord(
            spineIndex: spineIndex,
            spineHref: sel.spineHref,
            selectedText: sel.text,
            rangeStart: sel.rangeStart,
            rangeEnd: sel.rangeEnd,
            tintHex: tintHex
        )
        highlights.append(record)
    }
}

// MARK: - Safe Collection Access

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
    let currentTheme: EPUBTheme
    let isPaginated: Bool
    @Binding var currentProgress: Double
    @Binding var lastSelection: EPUBBridgeMessage.SelectionPayload?
    @Binding var currentPage: Int
    @Binding var totalPages: Int
    let highlights: [HighlightRecord]
    let onHighlightRequest: () -> Void
    let onProgressSave: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            EPUBReaderView(
                document: document,
                resourceActor: resourceActor,
                spineIndex: $spineIndex,
                themeCSS: currentTheme.toCSS(),
                isPaginated: isPaginated,
                onMessage: { handleMessage($0) }
            )

            if lastSelection != nil {
                selectionBar
            }

            progressBar
            navigationBar
        }
    }

    private var selectionBar: some View {
        HStack {
            Text("\"\(String(lastSelection?.text.prefix(40) ?? ""))...\"")
                .font(.caption)
                .lineLimit(1)
            Spacer()
            Button("Highlight") { onHighlightRequest() }
                .font(.caption.bold())
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color(.systemGroupedBackground))
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.gray.opacity(0.3))
                Rectangle().fill(Color.accentColor)
                    .frame(width: geo.size.width * currentProgress)
            }
        }
        .frame(height: 3)
    }

    private var navigationBar: some View {
        HStack {
            Button { if spineIndex > 0 { spineIndex -= 1 } } label: {
                Image(systemName: "chevron.left")
            }.disabled(spineIndex == 0)

            Spacer()

            VStack(spacing: 2) {
                if isPaginated {
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
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func handleMessage(_ message: EPUBBridgeMessage) {
        switch message {
        case .progressUpdated(let payload):
            currentProgress = ReadingPosition.computeOverallProgress(
                spineIndex: spineIndex, chapterProgress: payload.chapterProgress,
                totalSpineItems: document.spineCount
            )
            onProgressSave()
        case .selectionChanged(let payload):
            lastSelection = payload
        case .selectionCleared:
            lastSelection = nil
        case .contentReady:
            currentProgress = ReadingPosition.computeOverallProgress(
                spineIndex: spineIndex, chapterProgress: 0, totalSpineItems: document.spineCount
            )
            onProgressSave()
        case .pageChanged(let payload):
            currentPage = payload.currentPage
            totalPages = payload.totalPages
            currentProgress = ReadingPosition.computeOverallProgress(
                spineIndex: spineIndex, chapterProgress: payload.progress,
                totalSpineItems: document.spineCount
            )
            onProgressSave()
        default:
            break
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
                    TOCRowView(entry: entry, isCurrent: isCurrentEntry(entry), onTap: { onSelect(entry) })
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

struct TOCRowView: View {
    let entry: FlatTOCEntry
    let isCurrent: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(entry.displayTitle).foregroundStyle(.primary)
                Spacer()
                if isCurrent {
                    Image(systemName: "bookmark.fill").foregroundStyle(Color.accentColor).font(.caption)
                }
            }
        }
    }
}

// MARK: - Theme Picker View

struct ThemePickerView: View {
    @Binding var currentTheme: EPUBTheme
    @Binding var isPaginated: Bool

    var body: some View {
        List {
            Section("Theme") {
                ForEach(EPUBTheme.allPresets) { theme in
                    themeRow(theme)
                }
            }
            Section("Layout") {
                Toggle("Paginated", isOn: $isPaginated)
                Text(isPaginated
                     ? "Tap left/right edges to turn pages"
                     : "Scroll vertically through content")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Font Size: \(currentTheme.fontSize)px") {
                fontSizeControl
            }
        }
    }

    private func themeRow(_ theme: EPUBTheme) -> some View {
        Button {
            currentTheme = EPUBTheme(
                id: theme.id, name: theme.name,
                backgroundColor: theme.backgroundColor, textColor: theme.textColor,
                linkColor: theme.linkColor, selectionColor: theme.selectionColor,
                fontSize: currentTheme.fontSize
            )
        } label: {
            HStack {
                Circle().fill(Color(hex: theme.backgroundColor))
                    .overlay(Circle().stroke(Color.gray, lineWidth: 1))
                    .frame(width: 28, height: 28)
                Text(theme.name).foregroundStyle(.primary)
                Spacer()
                if theme.id == currentTheme.id {
                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    private var fontSizeControl: some View {
        HStack {
            Button("A-") { updateSize(currentTheme.fontSize - 2) }.disabled(currentTheme.fontSize <= 12)
            Spacer()
            Text("Aa").font(.system(size: CGFloat(currentTheme.fontSize)))
            Spacer()
            Button("A+") { updateSize(currentTheme.fontSize + 2) }.disabled(currentTheme.fontSize >= 32)
        }
        .padding(.vertical, 4)
    }

    private func updateSize(_ newSize: Int) {
        currentTheme = EPUBTheme(
            id: currentTheme.id, name: currentTheme.name,
            backgroundColor: currentTheme.backgroundColor, textColor: currentTheme.textColor,
            linkColor: currentTheme.linkColor, selectionColor: currentTheme.selectionColor,
            fontSize: newSize
        )
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
        VStack(spacing: 0) {
            searchResults
        }
        .searchable(text: $query, prompt: "Search in book")
        .onSubmit(of: .search) { performSearch() }
    }

    private var searchResults: some View {
        List {
            if isSearching {
                ProgressView("Searching...")
            } else if results.isEmpty && !query.isEmpty {
                Text("No results found").foregroundStyle(.secondary)
            } else {
                ForEach(results) { result in
                    Button { onSelect(result) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            if let section = result.sectionTitle {
                                Text(section).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(result.context)
                                .font(.callout)
                                .lineLimit(3)
                                .foregroundStyle(.primary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private func performSearch() {
        guard let document, let archive, !query.isEmpty else { return }
        isSearching = true
        let q = query
        let doc = document
        let arch = archive
        Task {
            let r = BookSearchEngine.search(query: q, in: doc, archive: arch, maxResults: 30)
            results = r
            isSearching = false
        }
    }
}

// MARK: - Highlight Color Picker

struct HighlightColorView: View {
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Choose highlight color").font(.headline)
            HStack(spacing: 16) {
                ForEach(HighlightTint.palette, id: \.hex) { item in
                    Button {
                        onSelect(item.hex)
                    } label: {
                        VStack(spacing: 6) {
                            Circle()
                                .fill(Color(hex: item.hex))
                                .frame(width: 44, height: 44)
                            Text(item.name)
                                .font(.caption2)
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
        }
        .padding()
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
