import SwiftUI
import WebKit
import DualSpineCore
import DualSpineRender

struct ContentView: View {
    @State private var document: EPUBDocument?
    @State private var resourceActor: EPUBResourceActor?
    @State private var spineIndex = 0
    @State private var errorMessage: String?
    @State private var bridgeLog: [String] = []

    // Point this at any EPUB in the books/ directory
    private let epubPath = "/Users/shiyuliu/Documents/DualSpine/books"

    var body: some View {
        NavigationStack {
            Group {
                if let document, let resourceActor {
                    readerView(document: document, resourceActor: resourceActor)
                } else if let errorMessage {
                    errorView(errorMessage)
                } else {
                    ProgressView("Loading EPUB...")
                }
            }
            .navigationTitle(document?.title ?? "DualSpine Test")
            .navigationBarTitleDisplayMode(.inline)
            .task { await loadEPUB() }
        }
    }

    @ViewBuilder
    private func readerView(document: EPUBDocument, resourceActor: EPUBResourceActor) -> some View {
        VStack(spacing: 0) {
            // Reader
            EPUBReaderView(
                document: document,
                resourceActor: resourceActor,
                spineIndex: $spineIndex,
                themeCSS: themeCSS,
                onMessage: { message in handleMessage(message) }
            )

            // Navigation bar
            HStack {
                Button("← Prev") {
                    if spineIndex > 0 { spineIndex -= 1 }
                }
                .disabled(spineIndex == 0)

                Spacer()

                Text("\(spineIndex + 1) / \(document.spineCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Next →") {
                    if spineIndex < document.spineCount - 1 { spineIndex += 1 }
                }
                .disabled(spineIndex >= document.spineCount - 1)
            }
            .padding()
            .background(.bar)

            // Debug log
            if !bridgeLog.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(bridgeLog.suffix(5), id: \.self) { log in
                            Text(log)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(height: 60)
                .background(Color(.systemGroupedBackground))
            }
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.red)
            Text(message)
                .multilineTextAlignment(.center)
                .padding()
        }
    }

    // MARK: - Theme CSS

    private var themeCSS: String {
        """
        :root {
            color-scheme: light dark;
        }
        body {
            font-family: -apple-system, system-ui, Georgia, serif;
            font-size: 18px;
            line-height: 1.7;
            padding: 16px 20px;
            max-width: 100%;
            word-wrap: break-word;
            overflow-wrap: break-word;
        }
        img {
            max-width: 100%;
            height: auto;
        }
        table {
            max-width: 100%;
            overflow-x: auto;
            display: block;
        }
        """
    }

    // MARK: - EPUB Loading

    private func loadEPUB() async {
        do {
            // Find the first EPUB in the books directory
            let booksURL = URL(fileURLWithPath: epubPath)
            let contents = try FileManager.default.contentsOfDirectory(
                at: booksURL,
                includingPropertiesForKeys: nil
            )

            // Pick "First Love" for the initial test (small, fast)
            guard let epubURL = contents.first(where: {
                $0.pathExtension == "epub" && $0.lastPathComponent.contains("First Love")
            }) ?? contents.first(where: { $0.pathExtension == "epub" }) else {
                errorMessage = "No EPUB files found in \(epubPath)"
                return
            }

            let doc = try EPUBParser.parse(at: epubURL)
            let actor = EPUBResourceActor(
                archiveURL: epubURL,
                contentBasePath: doc.contentBasePath
            )

            self.document = doc
            self.resourceActor = actor

            bridgeLog.append("Loaded: \(doc.title) (\(doc.spineCount) spine items)")
        } catch {
            errorMessage = "Failed to load EPUB: \(error.localizedDescription)"
        }
    }

    // MARK: - Bridge Messages

    private func handleMessage(_ message: EPUBBridgeMessage) {
        switch message {
        case .contentReady(let payload):
            bridgeLog.append("Ready: \(payload.spineHref) (\(payload.characterCount) chars, \(Int(payload.contentHeight))pt)")
        case .progressUpdated(let payload):
            bridgeLog.append("Progress: \(String(format: "%.0f%%", payload.chapterProgress * 100))")
        case .selectionChanged(let payload):
            bridgeLog.append("Selected: \"\(String(payload.text.prefix(50)))\"")
        case .selectionCleared:
            bridgeLog.append("Selection cleared")
        case .linkTapped(let payload):
            bridgeLog.append("Link: \(payload.href) (internal: \(payload.isInternal))")
        case .imageTapped(let payload):
            bridgeLog.append("Image: \(payload.src) (\(payload.naturalWidth)×\(payload.naturalHeight))")
        }
    }
}
