// Words that mean "send this to a site", shared by typed and spoken commands.
import Foundation

extension Notification.Name {
    static let keydoPromptSpoken = Notification.Name("KeyDoPromptSpoken")
}

enum SpokenCommands {
    /// A whole spoken sentence such as "KeyDo, please send it to ChatGPT": the site name, when the words are a send command.
    static func sendTarget(inSpoken raw: String) -> String? {
        var text = raw.lowercased().replacingOccurrences(of: "[^a-z0-9 ]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        for _ in 0..<3 {
            for lead in ["in keydo ", "keydo ", "key do ", "ezme ", "please ", "can you ", "could you "] where text.hasPrefix(lead) { text = String(text.dropFirst(lead.count)) }
        }
        for tail in [" please", " now"] where text.hasSuffix(tail) { text = String(text.dropLast(tail.count)) }
        return sendTarget(in: text)
    }

    /// "send to chatgpt" and its variants: the site name, when the words are a send command.
    static func sendTarget(in normalized: String) -> String? {
        for lead in ["enter ", "inter ", "entre "] where normalized.hasPrefix(lead) {
            let rest = String(normalized.dropFirst(lead.count)).trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty, rest.split(separator: " ").count <= 3 { return rest }
        }
        for lead in ["send this to ", "send it to ", "send prompt to ", "send to ", "share with ", "share to ", "paste this in ", "paste it in ", "paste in ", "paste into ", "share this with ", "share it with ", "post to ", "submit to "] {
            if normalized.hasPrefix(lead) { return String(normalized.dropFirst(lead.count)).trimmingCharacters(in: .whitespaces) }
        }
        return nil
    }
}
