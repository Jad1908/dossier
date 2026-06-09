import Foundation

// Decodes the `dossier forge --format json` payload (DESKTOP_APP_SPEC §3).
// Mirrors src/dossier/report.py; the contract test keeps them honest.

struct ForgeResult: Codable, Equatable {
    var ok: Bool
    var prompt: String?
    var tokenEstimate: Int?
    var encoding: String
    var sections: [ForgeSection]
    var errors: [ForgeError]

    enum CodingKeys: String, CodingKey {
        case ok, prompt, encoding, sections, errors
        case tokenEstimate = "token_estimate"
    }
}

struct ForgeSection: Codable, Equatable, Identifiable {
    var name: String
    var type: String
    var content: String
    var id: String { name + "|" + type }
}

struct ForgeError: Codable, Equatable, Identifiable {
    /// Stable enum the app switches on (report.py ErrorKind).
    var kind: String
    var detail: String
    var section: String?
    var id: String { kind + "|" + detail + "|" + (section ?? "") }

    /// A human sentence for the error banner — never a raw traceback.
    var message: String {
        switch kind {
        case "missing_file":
            return "Missing file: \(detail)"
        case "unknown_prompt":
            return "Unknown prompt “\(detail)” — not in the prompt library."
        case "invalid_spec":
            return "Invalid spec: \(detail)"
        case "spec_not_found":
            return "Spec not found: \(detail)"
        default:
            return detail
        }
    }
}
