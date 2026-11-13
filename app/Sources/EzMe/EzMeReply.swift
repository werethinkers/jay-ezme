// \reply: copy a message (an email, a chat, a review, an enquiry), type \reply and Space, and the
// reply is written for you and pasted. Add a style after it, for example \reply-short or \reply-firm.
import Foundation

enum BusinessReply {
    struct Style {
        let label: String
        let guidance: String
    }

    /// Styles by the word typed after \reply- (or \reply.). Plain \reply is Professional.
    private static let styles: [String: Style] = [
        "": Style(label: "Professional", guidance: "Professional, polite and clear, the way a good business would answer."),
        "pro": Style(label: "Professional", guidance: "Professional, polite and clear, the way a good business would answer."),
        "short": Style(label: "Short", guidance: "Very short: two to four sentences. Answer first, then the next step."),
        "s": Style(label: "Short", guidance: "Very short: two to four sentences. Answer first, then the next step."),
        "warm": Style(label: "Warm", guidance: "Warm and friendly while staying professional. Appreciate the person."),
        "w": Style(label: "Warm", guidance: "Warm and friendly while staying professional. Appreciate the person."),
        "firm": Style(label: "Firm", guidance: "Calm and firm. Hold the position politely, state the policy or limit plainly, and offer the next step. Never rude."),
        "f": Style(label: "Firm", guidance: "Calm and firm. Hold the position politely, state the policy or limit plainly, and offer the next step. Never rude."),
        "sales": Style(label: "Sales", guidance: "Helpful sales reply. Answer the enquiry, highlight the benefit, and end with one clear call to action."),
        "support": Style(label: "Support", guidance: "Customer-support reply. Acknowledge the issue, give the fix or the steps, and say what happens next."),
        "sorry": Style(label: "Apology", guidance: "Sincere apology for the problem without making excuses, then what will be done to put it right."),
        "apology": Style(label: "Apology", guidance: "Sincere apology for the problem without making excuses, then what will be done to put it right."),
        "no": Style(label: "Polite decline", guidance: "Politely decline. Give a brief reason if the message allows, keep the relationship warm, and offer an alternative if one is natural."),
        "decline": Style(label: "Polite decline", guidance: "Politely decline. Give a brief reason if the message allows, keep the relationship warm, and offer an alternative if one is natural."),
        "followup": Style(label: "Follow-up", guidance: "A courteous follow-up that refers to the earlier message, asks for the pending item, and suggests a time."),
        "thanks": Style(label: "Thanks", guidance: "A gracious thank-you reply that confirms what was received or done and the next step, if any."),
    ]

    /// The style for a typed command such as "\reply", "\reply-short" or "/reply.firm". Nil when it is not a reply command.
    static func style(for raw: String) -> Style? {
        let value = raw.trimmingCharacters(in: CharacterSet(charactersIn: "/\\ ")).lowercased()
        guard value == "reply" || value.hasPrefix("reply-") || value.hasPrefix("reply.") else { return nil }
        let suffix = String(value.dropFirst(5)).trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        return styles[suffix]
    }

    static func prompt(context: String, style: Style) -> String {
        """
        You write replies for a busy business owner. Below is a message they received (it may be an email, a chat, a review, a quotation request or a whole thread). Write the reply they will send.

        Style: \(style.guidance)

        Rules:
        - Answer every question and request in the message.
        - Use only facts that appear in the message. Do not invent prices, dates, names, policies or promises. Where a needed detail is missing, put a short placeholder in square brackets, such as [delivery date].
        - Reply in the same language as the message.
        - Start directly with the greeting or the answer. No preamble, no explanation of what you did, no subject line unless the message is clearly an email thread.
        - Sign off with a short closing but leave the name for the sender to add.

        Message received:
        \(context)
        """
    }
}
