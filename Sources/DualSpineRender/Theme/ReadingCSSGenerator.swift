import Foundation

/// Generates the CSS string injected into WKWebView, matching ReBabel's
/// semantic merge CSS output. Covers theme colors, typography, layout,
/// spacing, headings, blockquotes, code, tables, and CJK support.
public enum ReadingCSSGenerator {

    /// Generate the full CSS for injection based on appearance settings.
    /// - Parameters:
    ///   - settings: The current reading appearance configuration.
    ///   - containerWidth: The WKWebView's width in points (for page width calculation).
    public static func generateCSS(
        for settings: ReadingAppearanceSettings,
        containerWidth: Double = 402
    ) -> String {
        let s = settings.clamped()
        let theme = s.theme
        let imp = s.usesPublisherStyles ? "" : " !important"
        let layoutImp = " !important" // Layout always forced

        // Typography computations
        let lineHeight = computeLineHeight(s)
        let blockSpacing = computeBlockSpacing(s)
        let headingScale = computeHeadingScale()
        let widthPreset = ReadingPageWidth.from(sliderValue: s.pageWidthValue)
        let widthPercent = Int(widthPreset.viewportFraction * 100)
        let fontFamily = s.fontStyle.cssFontFamily

        return """
        /* DualSpine Reading Appearance — Generated CSS */
        :root {
            color-scheme: \(theme.isDark ? "dark" : "light");
            --ds-bg: \(theme.backgroundColor);
            --ds-text: \(theme.textColor);
            --ds-link: \(theme.linkColor);
            --ds-muted: \(theme.mutedTextColor);
        }

        html, body {
            background-color: \(theme.backgroundColor)\(layoutImp);
            color: \(theme.textColor)\(imp);
            font-family: \(fontFamily)\(imp);
            font-size: \(String(format: "%.1f", s.fontSize))px\(imp);
            line-height: \(String(format: "%.3f", lineHeight))\(imp);
            text-align: \(s.textAlignment.cssValue)\(imp);
            -webkit-text-size-adjust: 100%;
            word-wrap: break-word;
            overflow-wrap: break-word;
            transition: background-color 0.26s ease, color 0.26s ease;
        }

        /* Force typography on all text-containing elements to override publisher CSS */
        body, body p, body div, body span, body li, body td, body th,
        body h1, body h2, body h3, body h4, body h5, body h6, body blockquote {
            font-family: \(fontFamily)\(imp);
            color: \(theme.textColor)\(imp);
        }

        body p, body div, body li, body td, body th, body blockquote, body span {
            line-height: \(String(format: "%.3f", lineHeight))\(imp);
            text-align: \(s.textAlignment.cssValue)\(imp);
        }

        body {
            width: \(widthPercent)%\(layoutImp);
            max-width: 100%\(layoutImp);
            margin-left: auto\(layoutImp);
            margin-right: auto\(layoutImp);
            padding: 0 \(widthPreset == .full ? 12 : 8)px\(layoutImp);
            box-sizing: border-box\(layoutImp);
        }

        a, a:visited {
            color: \(theme.linkColor)\(imp);
        }

        /* Paragraph spacing */
        body :where(p) {
            margin-block: \(String(format: "%.2f", blockSpacing))rem\(imp);
        }

        body :where(h1, h2, h3, h4, h5, h6) {
            margin-block: \(String(format: "%.2f", blockSpacing))rem calc(\(String(format: "%.2f", blockSpacing))rem * 0.68)\(imp);
        }

        /* Heading scale */
        h1 { font-size: \(String(format: "%.2f", 1.72 * headingScale))em\(imp); }
        h2 { font-size: \(String(format: "%.2f", 1.46 * headingScale))em\(imp); }
        h3 { font-size: \(String(format: "%.2f", 1.28 * headingScale))em\(imp); }
        h4 { font-size: 1.12em\(imp); }
        h5 { font-size: 1.0em\(imp); }
        h6 { font-size: 0.92em\(imp); }

        /* Blockquotes */
        blockquote {
            border-left: 3px solid \(theme.mutedTextColor)\(imp);
            padding-left: 1em\(imp);
            margin-left: 0.5em\(imp);
            color: \(theme.mutedTextColor)\(imp);
            font-style: italic\(imp);
        }

        /* Code blocks */
        pre, code {
            font-family: "Courier New", Courier, monospace\(imp);
            font-size: 0.9em\(imp);
            background-color: \(theme.isDark ? "rgba(255,255,255,0.06)" : "rgba(0,0,0,0.04)")\(imp);
            border-radius: 4px\(imp);
            padding: 0.15em 0.3em\(imp);
            white-space: pre-wrap\(imp);
            word-wrap: break-word\(imp);
        }
        pre {
            padding: 0.8em 1em\(imp);
            overflow-x: auto\(imp);
        }
        pre code {
            background: none\(imp);
            padding: 0\(imp);
        }

        /* Tables */
        table {
            width: 100%\(imp);
            border-collapse: collapse\(imp);
            max-width: 100%\(imp);
            overflow-x: auto\(imp);
            display: block\(imp);
        }
        th, td {
            border: 1px solid \(theme.isDark ? "rgba(255,255,255,0.15)" : "rgba(0,0,0,0.12)")\(imp);
            padding: 0.5em 0.75em\(imp);
            text-align: left\(imp);
        }
        th {
            font-weight: 600\(imp);
            background-color: \(theme.isDark ? "rgba(255,255,255,0.04)" : "rgba(0,0,0,0.03)")\(imp);
        }

        /* Images & media */
        img, svg {
            max-width: 100%\(imp);
            height: auto\(imp);
        }
        figure {
            margin: 1em 0\(imp);
            text-align: center\(imp);
        }
        figcaption {
            font-size: 0.85em\(imp);
            color: \(theme.mutedTextColor)\(imp);
            margin-top: 0.5em\(imp);
        }

        /* Lists */
        ul, ol {
            padding-left: 1.8em\(imp);
        }
        li {
            margin-bottom: 0.3em\(imp);
        }

        /* Selection */
        ::selection {
            background-color: \(theme.isDark ? "rgba(100,181,246,0.25)" : "rgba(0,122,255,0.2)");
        }

        /* CJK ruby annotations */
        ruby {
            ruby-align: center;
        }
        rt {
            font-size: 0.5em;
        }

        /* Horizontal rules */
        hr {
            border: none\(imp);
            border-top: 1px solid \(theme.isDark ? "rgba(255,255,255,0.12)" : "rgba(0,0,0,0.1)")\(imp);
            margin: 1.5em 0\(imp);
        }
        """
    }

    // MARK: - Computations

    /// CSS line-height from lineSpacing setting.
    /// Formula: 1.35 + (lineSpacing / 20.0), clamped to [1.2, 2.35].
    static func computeLineHeight(_ s: ReadingAppearanceSettings) -> Double {
        let base = 1.35 + (s.lineSpacing / 20.0)
        return max(1.2, min(2.35, base))
    }

    /// Block spacing (paragraph margins) in rem.
    static func computeBlockSpacing(_ s: ReadingAppearanceSettings) -> Double {
        let base = 0.6 + (s.lineSpacing / 20.0) * 0.8
        return max(0.3, min(1.8, base))
    }

    /// Heading type scale multiplier.
    static func computeHeadingScale() -> Double {
        1.0 // Can be adjusted per typography profile
    }

    /// Content width in points from pageWidthValue + container width.
    static func computeContentWidth(
        _ s: ReadingAppearanceSettings,
        containerWidth: Double
    ) -> Double {
        let preset = ReadingPageWidth.from(sliderValue: s.pageWidthValue)
        let targetCPL = preset.targetCPL
        let charWidthFactor = 0.54
        let baselineFontSize = 18.0
        let baselineWidth = targetCPL * baselineFontSize * charWidthFactor

        let maxAvailable = max(0, containerWidth - 32) // 16px padding each side
        return min(maxAvailable, max(baselineWidth, containerWidth * 0.85))
    }
}
