import Foundation

extension EPUBTheme {

    /// Light theme — clean white background with dark text.
    public static let light = EPUBTheme(
        id: "light",
        name: "Light",
        backgroundColor: "#FFFFFF",
        textColor: "#1A1A1A",
        linkColor: "#0066CC",
        selectionColor: "rgba(100, 181, 246, 0.35)"
    )

    /// Dark theme — deep black background with light text.
    public static let dark = EPUBTheme(
        id: "dark",
        name: "Dark",
        backgroundColor: "#111111",
        textColor: "#E0E0E0",
        linkColor: "#64B5F6",
        selectionColor: "rgba(100, 181, 246, 0.25)"
    )

    /// Sepia theme — warm parchment tone, easy on the eyes.
    public static let sepia = EPUBTheme(
        id: "sepia",
        name: "Sepia",
        backgroundColor: "#F5EDDA",
        textColor: "#3E2C1C",
        linkColor: "#8B5E3C",
        selectionColor: "rgba(139, 94, 60, 0.25)"
    )

    /// Solarized theme — based on Ethan Schoonover's Solarized Dark.
    public static let solarized = EPUBTheme(
        id: "solarized",
        name: "Solarized",
        backgroundColor: "#002B36",
        textColor: "#93A1A1",
        linkColor: "#268BD2",
        selectionColor: "rgba(38, 139, 210, 0.25)"
    )

    /// All built-in theme presets.
    public static let allPresets: [EPUBTheme] = [.light, .dark, .sepia, .solarized]
}
