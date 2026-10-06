import Foundation
import VoxboardShared

/// Ephemeral editor state only. Header values are persisted by the existing
/// endpoint-bound Keychain credentials store, never by the preset encoder.
struct URLDeliveryHeadersDraft: Equatable {
    struct Row: Identifiable, Equatable {
        let id: UUID
        var name: String
        var value: String

        init(id: UUID = UUID(), name: String = "", value: String = "") {
            self.id = id
            self.name = name
            self.value = value
        }

        var isBlank: Bool {
            name.trimmingCharacters(in: .whitespaces).isEmpty
                && value.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    var rows: [Row]

    init(headers: [String: String] = [:]) {
        rows = headers.sorted { $0.key.lowercased() < $1.key.lowercased() }
            .map { Row(name: $0.key, value: $0.value) }
        if rows.isEmpty { rows = [Row()] }
    }

    @discardableResult
    mutating func addRow() -> UUID {
        let row = Row()
        rows.append(row)
        return row.id
    }

    mutating func removeRow(id: UUID) {
        rows.removeAll { $0.id == id }
        if rows.isEmpty { rows = [Row()] }
    }

    func validatedHeaders() throws -> [String: String] {
        var headers: [String: String] = [:]
        var names: Set<String> = []
        for row in rows where !row.isBlank {
            // Never trim newlines: pasted CR/LF must fail validation, not be
            // silently normalized into a different header.
            let name = row.name.trimmingCharacters(in: .whitespaces)
            let value = row.value.trimmingCharacters(in: .whitespaces)
            guard names.insert(name.lowercased()).inserted else {
                throw URLDeliveryValidationError.invalidHeaders
            }
            headers[name] = value
        }
        try URLDeliveryValidator.validateHeaders(headers)
        return headers
    }

    func hasUnsavedChanges(comparedTo savedHeaders: [String: String]) -> Bool {
        (try? validatedHeaders()) != savedHeaders
    }
}
