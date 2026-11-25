import Foundation

// International starter packs for KeyDo v5.0.
// These complement the Indian packs in EzMeStarterPack.swift.
// All use neutral USD pricing, international names, and no region-specific tax.
// installOnce() is called at first launch (after the Indian packs) if not already installed.

enum StarterPackIntl {
    static let collectionName = "International Starter Pack"
    static let flagKey = "keydoIntlPackInstalled"

    // seeded inside seedDefaultShortcuts() — see flagKey check there

    static var allClips: [Clip] {
        [
            // Email replies
            Clip(key: "/thanks", name: "Thank you email", text: "Thank you for reaching out! I appreciate your message and will get back to you within 24 hours.", group: collectionName),
            Clip(key: "/follow", name: "Follow-up email", text: "I wanted to follow up on my previous message. Please let me know if you have any questions or need additional information.", group: collectionName),
            Clip(key: "/sorry", name: "Apology email", text: "I sincerely apologize for the inconvenience. We are working to resolve this as quickly as possible and will keep you updated.", group: collectionName),
            Clip(key: "/ooo", name: "Out of office", text: "I am currently out of the office and will return on [DATE]. For urgent matters, please contact [NAME] at [EMAIL].", group: collectionName),

            // Professional signatures
            Clip(key: "/sig", name: "Email signature", text: """
[Your Name]
[Your Title] | [Company Name]
[Phone] | [Email]
[Website]
""", group: collectionName),

            // Sales
            Clip(key: "/intro", name: "Sales intro", text: "Hi [Name], I noticed you [CONTEXT] and thought our solution could help you [BENEFIT]. Would you be open to a quick 15-minute call this week?", group: collectionName),
            Clip(key: "/demo", name: "Demo request", text: "I'd love to show you a quick demo of how [PRODUCT] works. I have availability on [DATE] at [TIME]. Does that work for you?", group: collectionName),
            Clip(key: "/proposal", name: "Proposal follow-up", text: "Following up on the proposal I sent over — did you get a chance to review it? Happy to walk you through it or answer any questions.", group: collectionName),
            Clip(key: "/disc", name: "Discount offer", text: "As a valued customer, I'd like to offer you an exclusive [X]% discount on your next order if you decide before [DATE].", group: collectionName),

            // Customer support
            Clip(key: "/greet", name: "Support greeting", text: "Hello [Name], thank you for contacting [Company] support. I'm [Agent Name] and I'll be helping you today. How can I assist you?", group: collectionName),
            Clip(key: "/resolve", name: "Issue resolved", text: "I'm glad we could resolve this for you! Is there anything else I can help you with today?", group: collectionName),
            Clip(key: "/escalate", name: "Escalation notice", text: "I've escalated your issue to our specialist team. You'll hear back within [X] business hours with a resolution.", group: collectionName),
            Clip(key: "/refund", name: "Refund confirmation", text: "Your refund of $[AMOUNT] has been processed. Please allow 3–5 business days for it to appear in your account.", group: collectionName),

            // HR / People
            Clip(key: "/offer", name: "Offer letter opening", text: """
Dear [Candidate Name],

We are pleased to offer you the position of [ROLE] at [COMPANY].

Start date: [DATE]
Compensation: $[SALARY] per year
Reports to: [MANAGER NAME]

Please sign and return this letter by [DATE].
""", group: collectionName),
            Clip(key: "/interview", name: "Interview invite", text: "We'd like to invite you for an interview for the [ROLE] position on [DATE] at [TIME]. The interview will take approximately [DURATION] and will be conducted [via Zoom / at our office].", group: collectionName),
            Clip(key: "/reject", name: "Rejection letter", text: "Thank you for your interest in the [ROLE] position. After careful consideration, we have decided to move forward with other candidates. We encourage you to apply for future openings.", group: collectionName),
            Clip(key: "/leave", name: "Leave request", text: "I am writing to request [X] days of [annual/sick/personal] leave from [START DATE] to [END DATE]. I have made arrangements to ensure my responsibilities are covered during this time.", group: collectionName),

            // Developer shortcuts
            Clip(key: "/todo", name: "TODO comment", text: "// TODO: [description] — [your name], {=TODAY()}", group: collectionName),
            Clip(key: "/fixme", name: "FIXME comment", text: "// FIXME: [description]", group: collectionName),
            Clip(key: "/prlink", name: "PR description", text: """
## What changed
- [describe the change]

## Why
[explain the motivation]

## How to test
1. [step 1]
2. [step 2]
""", group: collectionName),
            Clip(key: "/standupd", name: "Daily standup", text: """
Yesterday: [what I completed]
Today: [what I'm working on]
Blockers: [any impediments]
""", group: collectionName),

            // Finance / business
            Clip(key: "/invoice", name: "Invoice template", text: """
INVOICE #[NUMBER]
Date: {=TODAY()}
Due: {=Date+30}

Bill to:
[Client Name]
[Address]

Description            Amount
[Service/Product]      $[AMOUNT]

Subtotal:              $[SUBTOTAL]
Tax ([X]%):            $[TAX]
Total:                 $[TOTAL]

Payment due by {=Date+30}.
Bank: [BANK NAME] | Account: [ACCOUNT]
""", group: collectionName),
            Clip(key: "/quote", name: "Quotation", text: """
QUOTATION #[NUMBER]
Date: {=TODAY()}
Valid until: {=Date+15}

Prepared for: [Client Name]
Prepared by: [Your Name / Company]

Item                   Qty    Unit Price    Total
[ITEM]                 [QTY]  $[PRICE]      $[TOTAL]

Subtotal: $[SUBTOTAL]
Total: $[TOTAL]
""", group: collectionName),

            // Meetings
            Clip(key: "/agenda", name: "Meeting agenda", text: """
Meeting: [TITLE]
Date: {=TODAY()} [TIME]
Attendees: [NAMES]

Agenda:
1. [Topic 1] — [X] mins
2. [Topic 2] — [X] mins
3. Action items & next steps — [X] mins
""", group: collectionName),
            Clip(key: "/minutes", name: "Meeting minutes", text: """
Meeting Minutes — {=TODAY()}
Attendees: [NAMES]
Facilitator: [NAME]

Decisions made:
1. [Decision]

Action items:
- [Name]: [Task] by [Date]
""", group: collectionName),

            // Live values
            Clip(key: "/today", name: "Today's date", text: "{=TODAY()}", group: collectionName),
            Clip(key: "/now", name: "Current date & time", text: "{=DATETIME()}", group: collectionName),
            Clip(key: "/+30", name: "30 days from now", text: "{=Date+30}", group: collectionName),
            Clip(key: "/+7", name: "7 days from now", text: "{=Date+7}", group: collectionName),
        ]
    }
}
