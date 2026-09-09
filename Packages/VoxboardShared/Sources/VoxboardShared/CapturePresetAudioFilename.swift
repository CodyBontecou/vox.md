import Foundation

/// Stable recording identity and calendrical inputs used to render a Capture
/// Preset's generated-audio filename. Production callers may use the defaults;
/// tests can inject fixed dependencies for deterministic token output.
public struct CapturePresetAudioFilenameContext: Equatable, Sendable {
    public var identifier: String
    public var createdAt: Date
    public var presetName: String
    public var originalFilename: String
    public var calendar: Calendar
    public var locale: Locale
    public var timeZone: TimeZone

    public init(
        identifier: String,
        createdAt: Date,
        presetName: String,
        originalFilename: String,
        calendar: Calendar = Calendar(identifier: .gregorian),
        locale: Locale = Locale(identifier: "en_US_POSIX"),
        timeZone: TimeZone = .autoupdatingCurrent
    ) {
        var configuredCalendar = calendar
        configuredCalendar.locale = locale
        configuredCalendar.timeZone = timeZone
        self.identifier = identifier
        self.createdAt = createdAt
        self.presetName = presetName
        self.originalFilename = originalFilename
        self.calendar = configuredCalendar
        self.locale = locale
        self.timeZone = timeZone
    }
}

/// Renders one safe filename component for generated Capture audio. Empty
/// templates deliberately return nil so each caller can retain its legacy name.
public enum CapturePresetAudioFilename {
    public static let maximumBaseUTF8ByteCount = 180

    enum SanitizationMode {
        case graphemeSafe
        case watchRecordingCompatibility
    }

    private static let invalidFilenameCharacters = CharacterSet(
        charactersIn: "/\\?%*|\"<>:\n\r\t"
    ).union(.controlCharacters)

    static func containsUnsafeFilenameCharacters(
        _ value: String,
        mode: SanitizationMode
    ) -> Bool {
        value.unicodeScalars.contains { scalar in
            switch mode {
            case .graphemeSafe:
                return isUnsafeFilenameScalar(scalar)
            case .watchRecordingCompatibility:
                return invalidFilenameCharacters.contains(scalar)
            }
        }
    }

    /// Returns nil for an empty/whitespace-only template. Otherwise the typed
    /// extension is discarded and the actual encoded or copied extension wins.
    /// Unsupported brace tokens remain literal, then pass through the same path
    /// sanitization as every other character.
    public static func preferredFilename(
        template: String,
        context: CapturePresetAudioFilenameContext,
        sourceExtension: String
    ) -> String? {
        guard !template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let baseName = renderedFilenameBase(template: template, context: context)
        let pathExtension = sanitizedExtension(sourceExtension)
        return pathExtension.isEmpty ? baseName : "\(baseName).\(pathExtension)"
    }

    static func renderedFilenameBase(
        template: String,
        context: CapturePresetAudioFilenameContext,
        emptyTemplate: String? = nil,
        sanitizationMode: SanitizationMode = .graphemeSafe
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = context.calendar
        formatter.locale = context.locale
        formatter.timeZone = context.timeZone
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let timestamp = formatter.string(from: context.createdAt)
        let date = String(timestamp.prefix(10))
        let shortYear = String(timestamp.prefix(4).suffix(2))
        let time = String(timestamp.suffix(6))
        let identifier = context.identifier.lowercased()
        let id8 = String(identifier.prefix(8))
        let original = (context.originalFilename as NSString).deletingPathExtension

        let configured = template.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedTemplate = configured.isEmpty ? (emptyTemplate ?? "") : configured
        let rendered = selectedTemplate
            .replacingOccurrences(of: "{timestamp}", with: timestamp)
            .replacingOccurrences(of: "{date}", with: date)
            .replacingOccurrences(of: "{YR}", with: shortYear)
            .replacingOccurrences(of: "{time}", with: time)
            .replacingOccurrences(of: "{id}", with: identifier)
            .replacingOccurrences(of: "{id8}", with: id8)
            .replacingOccurrences(of: "{preset}", with: context.presetName)
            .replacingOccurrences(of: "{original}", with: original)

        let contextualFallback = sanitizeFilenameBase(
            "recording-\(timestamp)-\(id8)",
            fallback: "recording",
            mode: sanitizationMode
        )
        return sanitizeFilenameBase(
            rendered,
            fallback: contextualFallback,
            mode: sanitizationMode
        )
    }

    static func sanitizeFilenameBase(
        _ raw: String,
        fallback: String,
        mode: SanitizationMode
    ) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !(value as NSString).pathExtension.isEmpty {
            value = (value as NSString).deletingPathExtension
        }
        let replaced: String
        switch mode {
        case .graphemeSafe:
            replaced = value.map { character in
                character.unicodeScalars.contains(where: isUnsafeFilenameScalar)
                    ? "-"
                    : String(character)
            }.joined()
        case .watchRecordingCompatibility:
            replaced = value.unicodeScalars.map { scalar in
                invalidFilenameCharacters.contains(scalar) ? "-" : String(scalar)
            }.joined()
        }
        let cleaned = replaced
            .replacingOccurrences(of: " ", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-._"))
        let bounded = utf8Prefix(cleaned, maximumByteCount: maximumBaseUTF8ByteCount)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-._"))
        return bounded.isEmpty ? fallback : bounded
    }

    private static func isUnsafeFilenameScalar(_ scalar: Unicode.Scalar) -> Bool {
        guard invalidFilenameCharacters.contains(scalar) else { return false }
        // Foundation groups Unicode format controls with control characters.
        // Preserve only the format scalars that form legitimate extended emoji
        // graphemes; bidi/invisible controls and C0/C1 controls remain rejected.
        switch scalar.value {
        case 0x200D, 0xFE00...0xFE0F, 0xE0020...0xE007F, 0xE0100...0xE01EF:
            return false
        default:
            return true
        }
    }

    private static func sanitizedExtension(_ raw: String) -> String {
        raw.unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .prefix(12)
            .map(String.init)
            .joined()
            .lowercased()
    }

    private static func utf8Prefix(_ value: String, maximumByteCount: Int) -> String {
        var result = ""
        var byteCount = 0
        for character in value {
            let rendered = String(character)
            let characterByteCount = rendered.utf8.count
            guard byteCount + characterByteCount <= maximumByteCount else { break }
            result.append(character)
            byteCount += characterByteCount
        }
        return result
    }
}
