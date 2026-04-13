import SwiftUI
import WebKit
import DualSpineCore
import DualSpineRender

struct ContentView: View {
    @State private var document: EPUBDocument?
    @State private var resourceActor: EPUBResourceActor?
    @State private var spineIndex = 0
    @State private var errorMessage: String?
    @State private var currentTheme: EPUBTheme = .dark
    @State private var showTOC = false
    @State private var showThemePicker = false
    @State private var currentProgress: Double = 0
    @State private var lastSelection: String?

    private let epubPath = "/Users/shiyuliu/Documents/DualSpine/books"

    var body: some View {
        NavigationStack {
            mainContent
                .navigationTitle(document?.title ?? "DualSpine")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { showTOC = true } label: {
                            Image(systemName: "list.bullet")
                        }
                        .disabled(document == nil)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showThemePicker = true } label: {
                            Image(systemName: "textformat.size")
                        }
                    }
                }
                .task { await loadEPUB() }
                .sheet(isPresented: $showTOC) { tocSheet }
                .sheet(isPresented: $showThemePicker) { themeSheet }
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
                currentProgress: $currentProgress,
                lastSelection: $lastSelection
            )
        } else if let errorMessage {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.red)
                Text(errorMessage)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        } else {
            ProgressView("Loading EPUB...")
        }
    }

    // MARK: - TOC Sheet

    private var tocSheet: some View {
        NavigationStack {
            TOCListView(
                document: document,
                spineIndex: spineIndex,
                onSelect: { entry in
                    navigateToTOCEntry(entry)
                    showTOC = false
                }
            )
            .navigationTitle("Table of Contents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showTOC = false }
                }
            }
        }
    }

    // MARK: - Theme Sheet

    private var themeSheet: some View {
        NavigationStack {
            ThemePickerView(
                currentTheme: $currentTheme
            )
            .navigationTitle("Appearance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showThemePicker = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Logic

    private func loadEPUB() async {
        do {
            let booksURL = URL(fileURLWithPath: epubPath)
            let contents = try FileManager.default.contentsOfDirectory(
                at: booksURL, includingPropertiesForKeys: nil
            )
            guard let epubURL = contents.first(where: {
                $0.pathExtension == "epub" && $0.lastPathComponent.contains("First Love")
            }) ?? contents.first(where: { $0.pathExtension == "epub" }) else {
                errorMessage = "No EPUB files found"
                return
            }
            let doc = try EPUBParser.parse(at: epubURL)
            let actor = EPUBResourceActor(archiveURL: epubURL, contentBasePath: doc.contentBasePath)
            self.document = doc
            self.resourceActor = actor
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func navigateToTOCEntry(_ entry: FlatTOCEntry) {
        guard let document, let href = entry.href else { return }
        let resolved = document.package.resolvedSpine
        for (i, (_, manifest)) in resolved.enumerated() {
            if manifest.href == href || manifest.href.hasSuffix(href) || href.hasSuffix(manifest.href) {
                spineIndex = i
                return
            }
        }
    }
}

// MARK: - Reader Content View

struct ReaderContentView: View {
    let document: EPUBDocument
    let resourceActor: EPUBResourceActor
    @Binding var spineIndex: Int
    let currentTheme: EPUBTheme
    @Binding var currentProgress: Double
    @Binding var lastSelection: String?

    var body: some View {
        VStack(spacing: 0) {
            EPUBReaderView(
                document: document,
                resourceActor: resourceActor,
                spineIndex: $spineIndex,
                themeCSS: currentTheme.toCSS(),
                onMessage: { handleMessage($0) }
            )

            progressBar
            navigationBar

            if let selection = lastSelection {
                Text("Selected: \"\(selection)\"")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGroupedBackground))
            }
        }
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
            }
            .disabled(spineIndex == 0)

            Spacer()

            VStack(spacing: 2) {
                Text("\(spineIndex + 1) / \(document.spineCount)")
                    .font(.caption)
                Text("\(Int(currentProgress * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button { if spineIndex < document.spineCount - 1 { spineIndex += 1 } } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(spineIndex >= document.spineCount - 1)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func handleMessage(_ message: EPUBBridgeMessage) {
        switch message {
        case .progressUpdated(let payload):
            currentProgress = ReadingPosition.computeOverallProgress(
                spineIndex: spineIndex,
                chapterProgress: payload.chapterProgress,
                totalSpineItems: document.spineCount
            )
        case .selectionChanged(let payload):
            lastSelection = String(payload.text.prefix(80))
        case .selectionCleared:
            lastSelection = nil
        case .contentReady:
            currentProgress = ReadingPosition.computeOverallProgress(
                spineIndex: spineIndex, chapterProgress: 0, totalSpineItems: document.spineCount
            )
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
                let entries = document.flatTableOfContents
                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
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
                Text(entry.displayTitle)
                    .foregroundStyle(.primary)
                Spacer()
                if isCurrent {
                    Image(systemName: "bookmark.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.caption)
                }
            }
        }
    }
}

// MARK: - Theme Picker View

struct ThemePickerView: View {
    @Binding var currentTheme: EPUBTheme

    var body: some View {
        List {
            Section("Theme") {
                ForEach(EPUBTheme.allPresets) { theme in
                    themeRow(theme)
                }
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
                Circle()
                    .fill(Color(hex: theme.backgroundColor))
                    .overlay(Circle().stroke(Color.gray, lineWidth: 1))
                    .frame(width: 28, height: 28)
                Text(theme.name)
                    .foregroundStyle(.primary)
                Spacer()
                if theme.id == currentTheme.id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    private var fontSizeControl: some View {
        HStack {
            Button("A-") { updateFontSize(currentTheme.fontSize - 2) }
                .disabled(currentTheme.fontSize <= 12)
            Spacer()
            Text("Aa").font(.system(size: CGFloat(currentTheme.fontSize)))
            Spacer()
            Button("A+") { updateFontSize(currentTheme.fontSize + 2) }
                .disabled(currentTheme.fontSize >= 32)
        }
        .padding(.vertical, 4)
    }

    private func updateFontSize(_ newSize: Int) {
        currentTheme = EPUBTheme(
            id: currentTheme.id, name: currentTheme.name,
            backgroundColor: currentTheme.backgroundColor, textColor: currentTheme.textColor,
            linkColor: currentTheme.linkColor, selectionColor: currentTheme.selectionColor,
            fontSize: newSize
        )
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
