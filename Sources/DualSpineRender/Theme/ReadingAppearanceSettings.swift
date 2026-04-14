import Foundation

/// Complete reading appearance configuration matching ReBabel's system.
/// Generates CSS for injection into the WKWebView EPUB renderer.
public struct ReadingAppearanceSettings: Sendable, Hashable, Codable {

    // MARK: - Theme

    public var theme: ReadingTheme = .sepia

    // MARK: - Typography

    /// Font size in points. Range: [12, 40]. Default: 20.
    public var fontSize: Double = 20

    /// Line spacing in points. Range: [0, 20]. Default: 6.
    /// Converted to CSS line-height via: 1.35 + (lineSpacing / 20.0)
    public var lineSpacing: Double = 6

    /// Font family style.
    public var fontStyle: ReadingFontStyle = .serif

    /// Text alignment.
    public var textAlignment: ReadingTextAlignment = .left

    // MARK: - Layout

    /// Scroll (true) or paginated (false) reading mode.
    public var isScrollEnabled: Bool = true

    /// Whether to respect the publisher's embedded CSS styles.
    public var usesPublisherStyles: Bool = false

    /// Page width preset. Range: [0, 1]. Default: 0 (book).
    /// 0 = book (52 CPL), 0.333 = balanced (62 CPL), 0.667 = wide (74 CPL), 1 = full (88 CPL)
    public var pageWidthValue: Double = 0

    public init() {}

    // MARK: - Clamped

    /// Returns a copy with all values clamped to valid ranges.
    public func clamped() -> ReadingAppearanceSettings {
        var s = self
        s.fontSize = max(12, min(40, s.fontSize))
        s.lineSpacing = max(0, min(20, s.lineSpacing))
        s.pageWidthValue = max(0, min(1, s.pageWidthValue))
        return s
    }
}

// MARK: - Theme

public enum ReadingTheme: String, Sendable, Hashable, Codable, CaseIterable, Identifiable {
    case system = "system"
    case sepia = "sepia"
    case dark = "dark"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: return "Paper"
        case .sepia: return "Sepia"
        case .dark: return "Night"
        }
    }

    /// Background color hex.
    public var backgroundColor: String {
        switch self {
        case .system: return "#FFFFFF"
        case .sepia: return "#F4ECD8"
        case .dark: return "#1A1A1A"
        }
    }

    /// Text color hex.
    public var textColor: String {
        switch self {
        case .system: return "#1C1C1E"
        case .sepia: return "#5B4636"
        case .dark: return "#D1D1D1"
        }
    }

    /// Link color hex.
    public var linkColor: String {
        switch self {
        case .system: return "#007AFF"
        case .sepia: return "#8B5E3C"
        case .dark: return "#64B5F6"
        }
    }

    /// Muted/secondary text color hex.
    public var mutedTextColor: String {
        switch self {
        case .system: return "#8E8E93"
        case .sepia: return "#7A6451"
        case .dark: return "#A7A7A7"
        }
    }

    /// Panel background color hex (for UI elements overlaid on content).
    public var panelBackground: String {
        switch self {
        case .system: return "#F2F2F7"
        case .sepia: return "#FBF3E4"
        case .dark: return "#252525"
        }
    }

    public var isDark: Bool {
        self == .dark
    }
}

// MARK: - Font Style

public enum ReadingFontStyle: String, Sendable, Hashable, Codable, CaseIterable, Identifiable {
    case serif
    case sans
    case monospaced

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .serif: return "Serif"
        case .sans: return "Sans"
        case .monospaced: return "Mono"
        }
    }

    /// CSS font-family value (with CJK-aware fallbacks).
    public var cssFontFamily: String {
        switch self {
        case .serif:
            return "\"Palatino\", Georgia, \"Times New Roman\", \"SongtiSC-Regular\", \"STSongti-SC-Regular\", serif"
        case .sans:
            return "-apple-system, \"Helvetica Neue\", Arial, \"PingFangSC-Regular\", sans-serif"
        case .monospaced:
            return "\"Courier New\", Courier, monospace"
        }
    }
}

// MARK: - Text Alignment

public enum ReadingTextAlignment: String, Sendable, Hashable, Codable, CaseIterable, Identifiable {
    case left
    case justified

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .left: return "Left"
        case .justified: return "Justified"
        }
    }

    public var cssValue: String {
        switch self {
        case .left: return "start"
        case .justified: return "justify"
        }
    }
}

// MARK: - Page Width Preset

public enum ReadingPageWidth: String, Sendable, Hashable, Codable, CaseIterable, Identifiable {
    case book
    case balanced
    case wide
    case full

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .book: return "Book"
        case .balanced: return "Balanced"
        case .wide: return "Wide"
        case .full: return "Full"
        }
    }

    public var sliderValue: Double {
        switch self {
        case .book: return 0
        case .balanced: return 0.333
        case .wide: return 0.667
        case .full: return 1.0
        }
    }

    /// Target characters per line.
    public var targetCPL: Double {
        switch self {
        case .book: return 52
        case .balanced: return 62
        case .wide: return 74
        case .full: return 88
        }
    }

    /// Fraction of viewport width used by this preset.
    /// Produces visible differences on any screen size.
    public var viewportFraction: Double {
        switch self {
        case .book: return 0.72      // Narrow, comfortable for long reading
        case .balanced: return 0.84  // Default — slight margin each side
        case .wide: return 0.93      // Near full width
        case .full: return 1.00      // Edge-to-edge
        }
    }

    /// Best-match preset from a slider value.
    public static func from(sliderValue: Double) -> ReadingPageWidth {
        if sliderValue < 0.17 { return .book }
        if sliderValue < 0.5 { return .balanced }
        if sliderValue < 0.83 { return .wide }
        return .full
    }
}

// MARK: - Appearance Presets

public enum ReadingAppearancePreset: String, Sendable, CaseIterable, Identifiable {
    case classicBook
    case modernArticle
    case nightFocus

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .classicBook: return "Classic Book"
        case .modernArticle: return "Modern Article"
        case .nightFocus: return "Night Focus"
        }
    }

    public var description: String {
        switch self {
        case .classicBook: return "Sepia surface with classic serif type"
        case .modernArticle: return "Neutral paper surface with modern sans type"
        case .nightFocus: return "Dark surface with classic serif type"
        }
    }

    /// Apply this preset to settings.
    public func apply(to settings: inout ReadingAppearanceSettings) {
        switch self {
        case .classicBook:
            settings.theme = .sepia
            settings.fontStyle = .serif
        case .modernArticle:
            settings.theme = .system
            settings.fontStyle = .sans
        case .nightFocus:
            settings.theme = .dark
            settings.fontStyle = .serif
        }
    }
}
