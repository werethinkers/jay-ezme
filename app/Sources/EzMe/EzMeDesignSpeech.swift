// AppDesigner voice commands in Hindi script. When the mic listens in Hindi, English command words come back in
// Devanagari ("टेक्स्ट बॉक्स", "मेक इट"). This turns them back into the English words the command parser knows,
// and understands the common Hindi command words too. Anything unknown is spelled out in Latin letters.
import Foundation

enum DesignSpeech {
    /// The command mic listens in English (India) even when dictation elsewhere is set to Hindi. English with Hindi
    /// words mixed in is understood much better that way, and the words below cover the rest.
    static func commandLocale(chosen: String) -> String { chosen.lowercased().hasPrefix("en") ? chosen : "en-IN" }

    static func hasDevanagari(_ text: String) -> Bool { text.unicodeScalars.contains { (0x0900...0x097F).contains($0.value) } }

    static func normalize(_ raw: String) -> String {
        guard hasDevanagari(raw) else { return raw }
        var out: [String] = []
        for token in raw.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init) {
            let bare = token.trimmingCharacters(in: CharacterSet(charactersIn: ",.!?\"'\u{0964}\u{0965}"))
            guard !bare.isEmpty else { continue }
            if !hasDevanagari(bare) { out.append(bare); continue }
            out.append(words[fold(bare)] ?? transliterate(bare))
        }
        return out.joined(separator: " ")
    }

    /// Spelling variants (nukta, chandrabindu) are treated as the same word.
    private static func fold(_ word: String) -> String {
        var kept = String.UnicodeScalarView()
        for scalar in word.unicodeScalars where scalar.value != 0x093C {
            kept.append(scalar.value == 0x0901 ? Unicode.Scalar(UInt32(0x0902)) ?? scalar : scalar)
        }
        return String(kept)
    }

    private static let words: [String: String] = {
        var map: [String: String] = [:]
        for (hindi, english) in entries { map[fold(hindi)] = english }
        return map
    }()

    private static let entries: [(String, String)] = [
        // Boxes and pages
        ("टेक्स्ट", "text"), ("टेकस्ट", "text"), ("बॉक्स", "box"), ("बाक्स", "box"), ("मेक", "make"), ("इट", "it"), ("एड", "add"), ("ऐड", "add"), ("आड", "add"),
        ("पेज", "page"), ("टेम्प्लेट", "template"), ("टेम्पलेट", "template"), ("कैटेगरी", "category"), ("केटेगरी", "category"), ("कैटगरी", "category"),
        ("इमेज", "image"), ("पिक्चर", "picture"), ("फोटो", "photo"), ("तस्वीर", "picture"), ("लोगो", "logo"), ("आइकन", "icon"), ("आइकॉन", "icon"),
        ("वीडियो", "video"), ("मीडिया", "media"), ("वेरिएबल", "variable"), ("वेरियबल", "variable"), ("वैरिएबल", "variable"), ("फंक्शन", "function"),
        ("ड्रॉपडाउन", "dropdown"), ("ड्रॉप", "drop"), ("कलेक्शन", "collection"), ("शॉर्टकट", "shortcut"), ("शॉर्टकट्स", "shortcuts"),
        ("विशेज", "wishes"), ("विश", "wish"), ("एचबीडी", "hbd"), ("डेट", "date"), ("टाइम", "time"), ("टुडे", "today"), ("मंथ", "month"), ("ईयर", "year"),
        // Look
        ("बैकग्राउंड", "background"), ("कलर", "color"), ("कलर्स", "colors"), ("रंग", "color"), ("फॉन्ट", "font"), ("फोंट", "font"), ("साइज", "size"),
        ("बोल्ड", "bold"), ("इटैलिक", "italic"), ("सेंटर", "center"), ("सेन्टर", "center"), ("लेफ्ट", "left"), ("राइट", "right"), ("अप", "up"), ("डाउन", "down"),
        ("मूव", "move"), ("रोटेट", "rotate"), ("बिग", "big"), ("बिगर", "bigger"), ("बड़ा", "bigger"), ("बड़ी", "bigger"), ("बढ़ाओ", "bigger"),
        ("छोटा", "smaller"), ("छोटी", "smaller"), ("घटाओ", "smaller"), ("स्मॉल", "small"), ("स्मॉलर", "smaller"), ("इंक्रीस", "increase"), ("डिक्रीस", "decrease"),
        ("सर्कल", "circle"), ("राउंड", "round"), ("स्क्वायर", "square"), ("रेक्टेंगल", "rectangle"), ("ट्रायंगल", "triangle"), ("कैपिटल", "capital"),
        ("अपरकेस", "uppercase"), ("लोअरकेस", "lowercase"), ("अलाइन", "align"), ("मिडल", "middle"), ("थीम", "theme"), ("मोड", "mode"),
        // Actions
        ("पब्लिश", "publish"), ("रिलीज", "release"), ("सेव", "save"), ("अंडू", "undo"), ("अनडू", "undo"), ("डिलीट", "delete"), ("रिमूव", "remove"),
        ("सिलेक्ट", "select"), ("चेंज", "change"), ("रिप्लेस", "replace"), ("नेक्स्ट", "next"), ("प्रीवियस", "previous"), ("फर्स्ट", "first"), ("लास्ट", "last"),
        ("प्रिव्यू", "preview"), ("ट्राई", "try"), ("टेस्ट", "test"), ("नेम", "name"), ("ऐप", "app"), ("एप", "app"), ("कमांड", "command"), ("वर्ड", "word"),
        ("आउटपुट", "output"), ("पीडीएफ", "pdf"), ("पीएनजी", "png"), ("जीआईएफ", "gif"), ("एचटीएमएल", "html"), ("डिज़ाइन", "design"), ("डिजाइन", "design"),
        // Small English words
        ("टू", "to"), ("द", "the"), ("ए", "a"), ("एंड", "and"), ("विद", "with"), ("फ्रॉम", "from"), ("ऑफ", "of"), ("फॉर", "for"), ("इन", "in"), ("ऑन", "on"),
        ("दिस", "this"), ("दैट", "that"), ("इज", "is"), ("एज", "as"), ("नॉट", "not"), ("नो", "no"), ("ऑल", "all"), ("एवरी", "every"), ("आउट", "out"),
        // Hindi command words
        ("जोड़ो", "add"), ("जोड़ें", "add"), ("जोड़", "add"), ("जोड़िए", "add"), ("बनाओ", "make"), ("बनाइए", "make"), ("बनाएं", "make"), ("बना", "make"),
        ("हटाओ", "delete"), ("हटाएं", "delete"), ("हटा", "delete"), ("मिटाओ", "delete"), ("बदलो", "change"), ("बदलें", "change"), ("बदल", "change"),
        ("में", "in"), ("का", "of"), ("की", "of"), ("के", "of"), ("को", "to"), ("से", "from"), ("और", "and"), ("फिर", "then"), ("पर", "on"),
        ("पिछला", "previous"), ("अगला", "next"), ("पहला", "first"), ("पहली", "first"),
        ("एक", "1"), ("दो", "2"), ("तीन", "3"), ("चार", "4"), ("पांच", "5"), ("पाँच", "5"), ("छह", "6"), ("सात", "7"), ("आठ", "8"), ("नौ", "9"), ("दस", "10"),
        // Colours
        ("रेड", "red"), ("लाल", "red"), ("ब्लू", "blue"), ("नीला", "blue"), ("ग्रीन", "green"), ("हरा", "green"), ("येलो", "yellow"), ("पीला", "yellow"),
        ("ब्लैक", "black"), ("काला", "black"), ("व्हाइट", "white"), ("वाइट", "white"), ("सफेद", "white"), ("पिंक", "pink"), ("गुलाबी", "pink"),
        ("ऑरेंज", "orange"), ("नारंगी", "orange"), ("पर्पल", "purple"), ("बैंगनी", "purple"), ("ब्राउन", "brown"), ("भूरा", "brown"), ("गोल्ड", "gold"),
        ("सुनहरा", "gold"), ("सिल्वर", "silver"), ("ग्रे", "grey"), ("नेवी", "navy"), ("मैरून", "maroon"), ("टील", "teal"), ("क्रीम", "cream"), ("पीच", "peach"),
        ("लैवेंडर", "lavender"), ("मिंट", "mint"), ("मैजेंटा", "magenta"), ("वायलेट", "violet"), ("लाइट", "light"), ("डार्क", "dark"), ("हॉट", "hot"), ("स्काई", "sky")
    ]

    // MARK: Spelling out an unknown word

    private static let consonants: [UInt32: String] = [
        0x0915: "k", 0x0916: "kh", 0x0917: "g", 0x0918: "gh", 0x0919: "ng", 0x091A: "ch", 0x091B: "chh", 0x091C: "j", 0x091D: "jh", 0x091E: "ny",
        0x091F: "t", 0x0920: "th", 0x0921: "d", 0x0922: "dh", 0x0923: "n", 0x0924: "t", 0x0925: "th", 0x0926: "d", 0x0927: "dh", 0x0928: "n",
        0x092A: "p", 0x092B: "f", 0x092C: "b", 0x092D: "bh", 0x092E: "m", 0x092F: "y", 0x0930: "r", 0x0932: "l", 0x0933: "l", 0x0935: "v",
        0x0936: "sh", 0x0937: "sh", 0x0938: "s", 0x0939: "h"
    ]
    private static let vowels: [UInt32: String] = [
        0x0905: "a", 0x0906: "aa", 0x0907: "i", 0x0908: "ee", 0x0909: "u", 0x090A: "oo", 0x090B: "ri", 0x090F: "e", 0x0910: "ai", 0x0911: "o", 0x0913: "o", 0x0914: "au"
    ]
    private static let matras: [UInt32: String] = [
        0x093E: "aa", 0x093F: "i", 0x0940: "ee", 0x0941: "u", 0x0942: "oo", 0x0943: "ri", 0x0945: "e", 0x0947: "e", 0x0948: "ai", 0x0949: "o", 0x094B: "o", 0x094C: "au"
    ]

    static func transliterate(_ word: String) -> String {
        let scalars = Array(word.unicodeScalars)
        var result = ""
        var index = 0
        while index < scalars.count {
            let value = scalars[index].value
            if let consonant = consonants[value] {
                result += consonant
                index += 1
                if index < scalars.count, scalars[index].value == 0x093C { index += 1 }
                if index < scalars.count, let matra = matras[scalars[index].value] { result += matra; index += 1 }
                else if index < scalars.count, scalars[index].value == 0x094D { index += 1 }
                else if index < scalars.count { result += "a" }
            } else if let vowel = vowels[value] {
                result += vowel; index += 1
            } else if value == 0x0902 || value == 0x0901 {
                result += "n"; index += 1
            } else if value == 0x0903 {
                result += "h"; index += 1
            } else if (0x0966...0x096F).contains(value) {
                result += String(value - 0x0966); index += 1
            } else if (0x0900...0x097F).contains(value) {
                index += 1
            } else {
                result.unicodeScalars.append(scalars[index]); index += 1
            }
        }
        return result
    }
}
