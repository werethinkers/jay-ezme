// Gifting: the sender's message. A few honest, warm starting texts per occasion and tone, with what is in the box woven in.
import Foundation

enum GiftMessages {
    static let occasions: [(id: String, name: String, words: [String])] = [
        ("birthday", "Birthday", ["birthday", "bday", "born day"]),
        ("anniversary", "Anniversary", ["anniversary"]),
        ("thanks", "Thank you", ["thank you", "thanks", "thank"]),
        ("congrats", "Congratulations", ["congratulations", "congrats", "well done", "promotion"]),
        ("diwali", "Diwali", ["diwali", "festival", "deepavali"]),
        ("getwell", "Get well", ["get well", "recovery", "feel better"]),
        ("friendship", "Friendship", ["friendship", "friend", "miss you"]),
        ("love", "Love", ["love", "romantic", "i love you"]),
    ]

    static let tones: [(id: String, name: String, words: [String])] = [
        ("heartfelt", "Heartfelt", ["heartfelt", "emotional", "deep", "full of feeling"]),
        ("warm", "Warm and short", ["warm", "short", "simple", "brief"]),
        ("poetic", "Poetic", ["poetic", "beautiful", "lyrical"]),
    ]

    static func giftLine(_ c: GiftConfig) -> String {
        var names: [String] = []
        for j in c.jars {
            let n = GiftCatalogue.content(j.contentID)
            if n.id != "none" && !names.contains(n.name.lowercased()) { names.append(n.name.lowercased()) }
        }
        var list = ""
        if names.count == 1 { list = names[0] }
        if names.count > 1 { list = names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "") }
        var s = list.isEmpty ? "I packed this box with care" : "I filled this box with \(list)"
        let fl = GiftCatalogue.flower(c.flowerID)
        if fl.id != "none" { s += ", and decorated the lid with \(fl.name.lowercased())" }
        return s
    }

    private static let templates: [String: [String: String]] = [
        "birthday": [
            "heartfelt": "Dear {to}, happy birthday. {gift}, because you deserve a day that feels as warm as you make everyone else feel. May this year bring you more laughter, more calm and every wish you have kept quiet. With all my love, {from}",
            "warm": "Happy birthday, {to}! {gift}. Wishing you a year full of good things. {from}",
            "poetic": "Dear {to}, another year has opened like this lid, slowly and full of small surprises. {gift}, so that each one feels like a gift. Happy birthday. {from}",
        ],
        "anniversary": [
            "heartfelt": "Dear {to}, happy anniversary. {gift}, because every year with you has been a gift I did not know how to wrap. Thank you for staying, for laughing, for the ordinary days that turned into a life. Always yours, {from}",
            "warm": "Happy anniversary, {to}. {gift}. Here is to us, and to many more years. {from}",
            "poetic": "Dear {to}, some years pass like pages, ours like a long, warm song. {gift}, to keep it playing. Happy anniversary. {from}",
        ],
        "thanks": [
            "heartfelt": "Dear {to}, thank you. {gift}, because words alone were never going to be enough for what you did for me. You showed up when it mattered, and I will not forget it. With gratitude, {from}",
            "warm": "Thank you so much, {to}. {gift}, with my warmest thanks. {from}",
            "poetic": "Dear {to}, kindness like yours leaves a glow, like a candle lit in a quiet room. {gift}, so that the glow can stay a little longer. Thank you. {from}",
        ],
        "congrats": [
            "heartfelt": "Dear {to}, congratulations! I have watched the effort behind this, and it is wonderful to see it rewarded. {gift}, so that you take a moment to celebrate yourself. I am so proud of you. {from}",
            "warm": "Congratulations, {to}! {gift}, to celebrate you. Well done. {from}",
            "poetic": "Dear {to}, you planted this a long time ago, and today it blooms. {gift}, in honour of the day. Congratulations. {from}",
        ],
        "diwali": [
            "heartfelt": "Dear {to}, Happy Diwali. {gift}, so that your home glows with the light and sweetness this festival brings. May this festival bring you and your family health, joy and peace. With love, {from}",
            "warm": "Happy Diwali, {to}! {gift}. May your home be full of light. {from}",
            "poetic": "Dear {to}, may every diya you light carry a wish, and every wish find its way home. {gift}, for the festival of lights. Happy Diwali. {from}",
        ],
        "getwell": [
            "heartfelt": "Dear {to}, I have been thinking of you every day. {gift}, so that something soft and kind sits beside you while you rest. Please take all the time you need. I am only a call away. {from}",
            "warm": "Get well soon, {to}. {gift}, to brighten your days. Thinking of you. {from}",
            "poetic": "Dear {to}, rest is also a kind of strength, like a garden in winter getting ready to bloom. {gift}, until you are back on your feet. {from}",
        ],
        "friendship": [
            "heartfelt": "Dear {to}, I do not say it often, but you matter to me more than I show. {gift}, because friends like you are rare and I never want to take you for granted. Thank you for being you. {from}",
            "warm": "Dear {to}, just a little something to say I am thinking of you. {gift}. {from}",
            "poetic": "Dear {to}, a good friend is like a lantern in a long street: you do not notice it until you need it, and then it is everything. {gift}, from one lantern to another. {from}",
        ],
        "love": [
            "heartfelt": "My dearest {to}, {gift}, because I wanted you to open something that feels like I do when I think of you. You make ordinary days feel like festivals. I love you, today and always. {from}",
            "warm": "To {to}, with all my love. {gift}. {from}",
            "poetic": "My dearest {to}, you are the quiet light in every room I walk into. {gift}, a small piece of what I feel. Forever yours, {from}",
        ],
    ]

    static func compose(occasion: String, tone: String, to: String, from: String, config: GiftConfig) -> String {
        let set = templates[occasion] ?? templates["birthday"] ?? [:]
        let t = set[tone] ?? set["heartfelt"] ?? ""
        let toName = to.trimmingCharacters(in: .whitespaces).isEmpty ? "friend" : to
        let fromName = from.trimmingCharacters(in: .whitespaces).isEmpty ? "" : from
        var out = t.replacingOccurrences(of: "{to}", with: toName)
        out = out.replacingOccurrences(of: "{gift}", with: giftLine(config))
        out = out.replacingOccurrences(of: "{from}", with: fromName)
        return out.trimmingCharacters(in: .whitespaces)
    }
}
