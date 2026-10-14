import Foundation

/// Zahlen für die Oberfläche – je nach Sprache korrekt formatiert
/// (z. B. „93 %“ auf Deutsch, „93%“ auf Englisch, „%93“ auf Türkisch).
enum UIFormat {
    static func percent(_ score: Float) -> String {
        Double(score).formatted(.percent.precision(.fractionLength(0)))
    }

    static func seconds(_ value: Double, decimals: Int = 0) -> String {
        value.formatted(.number.precision(.fractionLength(decimals)))
    }
}
