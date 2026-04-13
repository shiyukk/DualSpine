import Foundation

/// A complete visual theme for EPUB rendering.
/// Generates the CSS injected into WKWebView via the JS bridge.
public struct EPUBTheme: Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String

    // Colors
    public let backgroundColor: String    // CSS color
    public let textColor: String          // CSS color
    public let linkColor: String          // CSS color
    public let selectionColor: String     // CSS color (background for ::selection)

    // Typography
    public let fontFamily: String         // CSS font-family value
    public let fontSize: Int              // px
    public let lineHeight: Double         // unitless multiplier
    public let textAlign: TextAlign

    // Layout
    public let contentPadding: Int        // px, horizontal
    public let maxContentWidth: Int?      // px, nil = full width
    public let paragraphSpacing: Int      // px

    // Publisher styles
    public let respectPublisherStyles: Bool

    public init(
        id: String,
        name: String,
        backgroundColor: String = "#FFFFFF",
        textColor: String = "#1A1A1A",
        linkColor: String = "#0066CC",
        selectionColor: String = "rgba(100, 181, 246, 0.35)",
        fontFamily: String = "-apple-system, system-ui, Georgia, serif",
        fontSize: Int = 18,
        lineHeight: Double = 1.7,
        textAlign: TextAlign = .start,
        contentPadding: Int = 20,
        maxContentWidth: Int? = nil,
        paragraphSpacing: Int = 12,
        respectPublisherStyles: Bool = true
    ) {
        self.id = id
        self.name = name
        self.backgroundColor = backgroundColor
        self.textColor = textColor
        self.linkColor = linkColor
        self.selectionColor = selectionColor
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.lineHeight = lineHeight
        self.textAlign = textAlign
        self.contentPadding = contentPadding
        self.maxContentWidth = maxContentWidth
        self.paragraphSpacing = paragraphSpacing
        self.respectPublisherStyles = respectPublisherStyles
    }

    public enum TextAlign: String, Sendable, Hashable, Codable {
        case start
        case justify
        case left
        case center
    }

    /// Generate the full CSS string for injection into the EPUB content.
    public func toCSS() -> String {
        var css = """
        :root {
            --ds-bg: \(backgroundColor);
            --ds-text: \(textColor);
            --ds-link: \(linkColor);
            --ds-font: \(fontFamily);
            --ds-font-size: \(fontSize)px;
            --ds-line-height: \(lineHeight);
            --ds-padding: \(contentPadding)px;
            --ds-paragraph-spacing: \(paragraphSpacing)px;
        }
        """

        if !respectPublisherStyles {
            // Override all publisher styles
            css += """

            * {
                font-family: var(--ds-font) !important;
                color: var(--ds-text) !important;
                background-color: transparent !important;
                border-color: var(--ds-text) !important;
            }
            """
        }

        css += """

        html, body {
            background-color: var(--ds-bg) !important;
            color: var(--ds-text);
            font-family: var(--ds-font);
            font-size: var(--ds-font-size);
            line-height: var(--ds-line-height);
            text-align: \(textAlign.rawValue);
            padding: 0 var(--ds-padding);
            margin: 0;
            word-wrap: break-word;
            overflow-wrap: break-word;
            -webkit-text-size-adjust: 100%;
        }
        a, a:visited {
            color: var(--ds-link);
        }
        p {
            margin-bottom: var(--ds-paragraph-spacing);
        }
        img, svg {
            max-width: 100%;
            height: auto;
        }
        table {
            max-width: 100%;
            overflow-x: auto;
            display: block;
        }
        pre, code {
            white-space: pre-wrap;
            word-wrap: break-word;
            overflow-x: auto;
        }
        ::selection {
            background-color: \(selectionColor);
        }
        """

        if let maxWidth = maxContentWidth {
            css += """

            body {
                max-width: \(maxWidth)px;
                margin-left: auto;
                margin-right: auto;
            }
            """
        }

        return css
    }
}
