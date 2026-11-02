import Foundation

/// Encodes dictated text as a YAML string, never as YAML syntax or a typed scalar.
public enum TranscriptPropertyMapping {
    public static func normalizedKey(_ name: String) -> String? {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        guard !key.isEmpty, key.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return key
    }

    public static func yamlString(_ text: String) -> String {
        // JSON quoted strings are also valid YAML quoted strings.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return String(decoding: try! encoder.encode(text), as: UTF8.self)
    }
}
