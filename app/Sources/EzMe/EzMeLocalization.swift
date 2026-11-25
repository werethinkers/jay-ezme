import Foundation

// KeyDo v5.0 localization infrastructure.
// Supported languages: English (default), Spanish, Portuguese-BR, French,
// Arabic, Japanese, German.
// Strings are keyed by L10n enum cases; each language provides a Dictionary<String,String>.
// Falls back to English when a key is missing in a non-English bundle.
//
// Usage:  Text(L10n.homeWelcome.localized)
//         or the shorter alias:  L10n.homeWelcome.s

enum L10n: String, CaseIterable {

    // MARK: - Home
    case homeWelcome            = "home.welcome"
    case homeSearchPlaceholder  = "home.search.placeholder"
    case homeAskKeyDo           = "home.ask_keydo"

    // MARK: - Subscription
    case subFree                = "sub.free"
    case subPro                 = "sub.pro"
    case subTeams               = "sub.teams"
    case subUpgradeTitle        = "sub.upgrade.title"
    case subUpgradeBody         = "sub.upgrade.body"
    case subPerMonth            = "sub.per_month"
    case subPerYear             = "sub.per_year"
    case subGetPro              = "sub.get_pro"
    case subGetTeams            = "sub.get_teams"
    case subCurrentPlan         = "sub.current_plan"

    // MARK: - Challenge
    case challengeTitle         = "challenge.title"
    case challengeDay           = "challenge.day"              // "Day %d"
    case challengeComplete      = "challenge.complete"
    case challengeBadgeTitle    = "challenge.badge.title"
    case challengeShareText     = "challenge.share.text"

    // MARK: - KeyDo Store
    case storeTitle             = "store.title"
    case storeInstall           = "store.install"
    case storeInstalled         = "store.installed"
    case storePublish           = "store.publish"
    case storeSearchPlaceholder = "store.search.placeholder"
    case storeFree              = "store.free"

    // MARK: - Wall
    case wallTitle              = "wall.title"
    case wallShare              = "wall.share"
    case wallFilterAll          = "wall.filter.all"
    case wallFilterOfficial     = "wall.filter.official"
    case wallFilterTips         = "wall.filter.tips"
    case wallFilterShowcase     = "wall.filter.showcase"
    case wallFilterExperience   = "wall.filter.experience"
    case wallSubmit             = "wall.submit"
    case wallPendingApproval    = "wall.pending_approval"

    // MARK: - Common
    case commonSignIn           = "common.sign_in"
    case commonSignOut          = "common.sign_out"
    case commonClose            = "common.close"
    case commonDone             = "common.done"
    case commonCancel           = "common.cancel"
    case commonRetry            = "common.retry"
    case commonLoading          = "common.loading"

    // MARK: - Localised string access

    var localized: String { KeyDoStrings.shared.string(for: self) }
    var s: String { localized }
}

// MARK: - Runtime

final class KeyDoStrings: ObservableObject {
    static let shared = KeyDoStrings()

    @Published private(set) var language: String = "en"

    private let bundles: [String: [String: String]] = [
        "en": English.strings,
        "es": Spanish.strings,
        "pt-BR": PortugueseBR.strings,
        "fr": French.strings,
        "ar": Arabic.strings,
        "ja": Japanese.strings,
        "de": German.strings,
    ]

    private init() {
        let preferred = Locale.preferredLanguages.first ?? "en"
        for lang in bundles.keys {
            if preferred.hasPrefix(lang) { language = lang; break }
        }
    }

    func string(for key: L10n) -> String {
        bundles[language]?[key.rawValue] ?? bundles["en"]?[key.rawValue] ?? key.rawValue
    }

    func set(language: String) {
        guard bundles[language] != nil else { return }
        self.language = language
    }
}

// MARK: - English (base)

private enum English {
    static let strings: [String: String] = [
        "home.welcome":             "Welcome to KeyDo",
        "home.search.placeholder":  "Find shortcuts, collections, apps…",
        "home.ask_keydo":           "Ask KeyDo",
        "sub.free":                 "Free",
        "sub.pro":                  "Pro",
        "sub.teams":                "Teams",
        "sub.upgrade.title":        "Unlock the full KeyDo",
        "sub.upgrade.body":         "Get unlimited collections, cloud sync, AI features and the Template Marketplace.",
        "sub.per_month":            "/mo",
        "sub.per_year":             "/yr",
        "sub.get_pro":              "Get Pro",
        "sub.get_teams":            "Get Teams",
        "sub.current_plan":         "Current plan",
        "challenge.title":          "7-Day KeyDo Challenge",
        "challenge.day":            "Day %d",
        "challenge.complete":       "Mark complete",
        "challenge.badge.title":    "You earned the KeyDo Pro badge!",
        "challenge.share.text":     "I just completed the 7-Day KeyDo Challenge 🏆 — saving hours every week with keyboard shortcuts. Try it free at keydo.app",
        "store.title":              "KeyDo Store",
        "store.install":            "Install",
        "store.installed":          "Installed",
        "store.publish":            "Publish a pack",
        "store.search.placeholder": "Search packs…",
        "store.free":               "Free",
        "wall.title":               "KeyDo Wall",
        "wall.share":               "Share your experience",
        "wall.filter.all":          "All",
        "wall.filter.official":     "From KeyDo",
        "wall.filter.tips":         "Tips",
        "wall.filter.showcase":     "Showcases",
        "wall.filter.experience":   "Experiences",
        "wall.submit":              "Submit",
        "wall.pending_approval":    "Posts are reviewed before appearing.",
        "common.sign_in":           "Sign in",
        "common.sign_out":          "Sign out",
        "common.close":             "Close",
        "common.done":              "Done",
        "common.cancel":            "Cancel",
        "common.retry":             "Retry",
        "common.loading":           "Loading…",
    ]
}

// MARK: - Spanish

private enum Spanish {
    static let strings: [String: String] = [
        "home.welcome":             "Bienvenido a KeyDo",
        "home.search.placeholder":  "Buscar atajos, colecciones, apps…",
        "home.ask_keydo":           "Preguntar a KeyDo",
        "sub.free":                 "Gratis",
        "sub.pro":                  "Pro",
        "sub.teams":                "Equipos",
        "sub.upgrade.title":        "Desbloquea todo KeyDo",
        "sub.upgrade.body":         "Colecciones ilimitadas, sincronización en la nube, funciones de IA y la Tienda de plantillas.",
        "sub.per_month":            "/mes",
        "sub.per_year":             "/año",
        "sub.get_pro":              "Obtener Pro",
        "sub.get_teams":            "Obtener Equipos",
        "sub.current_plan":         "Plan actual",
        "challenge.title":          "Desafío KeyDo de 7 días",
        "challenge.day":            "Día %d",
        "challenge.complete":       "Marcar como completado",
        "challenge.badge.title":    "¡Ganaste la insignia KeyDo Pro!",
        "challenge.share.text":     "Acabo de completar el Desafío KeyDo de 7 días 🏆 — ahorrando horas con atajos de teclado. Pruébalo gratis en keydo.app",
        "store.title":              "Tienda KeyDo",
        "store.install":            "Instalar",
        "store.installed":          "Instalado",
        "store.publish":            "Publicar un paquete",
        "store.search.placeholder": "Buscar paquetes…",
        "store.free":               "Gratis",
        "wall.title":               "Muro KeyDo",
        "wall.share":               "Comparte tu experiencia",
        "wall.filter.all":          "Todo",
        "wall.filter.official":     "De KeyDo",
        "wall.filter.tips":         "Consejos",
        "wall.filter.showcase":     "Proyectos",
        "wall.filter.experience":   "Experiencias",
        "wall.submit":              "Enviar",
        "wall.pending_approval":    "Las publicaciones se revisan antes de aparecer.",
        "common.sign_in":           "Iniciar sesión",
        "common.sign_out":          "Cerrar sesión",
        "common.close":             "Cerrar",
        "common.done":              "Listo",
        "common.cancel":            "Cancelar",
        "common.retry":             "Reintentar",
        "common.loading":           "Cargando…",
    ]
}

// MARK: - Portuguese (Brazil)

private enum PortugueseBR {
    static let strings: [String: String] = [
        "home.welcome":             "Bem-vindo ao KeyDo",
        "home.search.placeholder":  "Buscar atalhos, coleções, apps…",
        "home.ask_keydo":           "Perguntar ao KeyDo",
        "sub.free":                 "Grátis",
        "sub.pro":                  "Pro",
        "sub.teams":                "Times",
        "sub.upgrade.title":        "Desbloqueie o KeyDo completo",
        "sub.upgrade.body":         "Coleções ilimitadas, sincronização na nuvem, recursos de IA e a Loja de modelos.",
        "sub.per_month":            "/mês",
        "sub.per_year":             "/ano",
        "sub.get_pro":              "Obter Pro",
        "sub.get_teams":            "Obter Times",
        "sub.current_plan":         "Plano atual",
        "challenge.title":          "Desafio KeyDo de 7 Dias",
        "challenge.day":            "Dia %d",
        "challenge.complete":       "Marcar como concluído",
        "challenge.badge.title":    "Você ganhou o emblema KeyDo Pro!",
        "challenge.share.text":     "Acabei de completar o Desafio KeyDo de 7 Dias 🏆 — economizando horas com atalhos de teclado. Experimente grátis em keydo.app",
        "store.title":              "Loja KeyDo",
        "store.install":            "Instalar",
        "store.installed":          "Instalado",
        "store.publish":            "Publicar um pacote",
        "store.search.placeholder": "Buscar pacotes…",
        "store.free":               "Grátis",
        "wall.title":               "Mural KeyDo",
        "wall.share":               "Compartilhe sua experiência",
        "wall.filter.all":          "Tudo",
        "wall.filter.official":     "Do KeyDo",
        "wall.filter.tips":         "Dicas",
        "wall.filter.showcase":     "Destaques",
        "wall.filter.experience":   "Experiências",
        "wall.submit":              "Enviar",
        "wall.pending_approval":    "As publicações são revisadas antes de aparecer.",
        "common.sign_in":           "Entrar",
        "common.sign_out":          "Sair",
        "common.close":             "Fechar",
        "common.done":              "Pronto",
        "common.cancel":            "Cancelar",
        "common.retry":             "Tentar novamente",
        "common.loading":           "Carregando…",
    ]
}

// MARK: - French

private enum French {
    static let strings: [String: String] = [
        "home.welcome":             "Bienvenue sur KeyDo",
        "home.search.placeholder":  "Rechercher raccourcis, collections, apps…",
        "home.ask_keydo":           "Demander à KeyDo",
        "sub.free":                 "Gratuit",
        "sub.pro":                  "Pro",
        "sub.teams":                "Équipes",
        "sub.upgrade.title":        "Débloquez KeyDo en entier",
        "sub.upgrade.body":         "Collections illimitées, synchronisation cloud, fonctions IA et la Boutique de modèles.",
        "sub.per_month":            "/mois",
        "sub.per_year":             "/an",
        "sub.get_pro":              "Obtenir Pro",
        "sub.get_teams":            "Obtenir Équipes",
        "sub.current_plan":         "Abonnement actuel",
        "challenge.title":          "Défi KeyDo en 7 jours",
        "challenge.day":            "Jour %d",
        "challenge.complete":       "Marquer comme terminé",
        "challenge.badge.title":    "Vous avez obtenu le badge KeyDo Pro !",
        "challenge.share.text":     "Je viens de terminer le Défi KeyDo en 7 jours 🏆 — économisant des heures avec des raccourcis clavier. Essayez gratuitement sur keydo.app",
        "store.title":              "Boutique KeyDo",
        "store.install":            "Installer",
        "store.installed":          "Installé",
        "store.publish":            "Publier un pack",
        "store.search.placeholder": "Rechercher des packs…",
        "store.free":               "Gratuit",
        "wall.title":               "Mur KeyDo",
        "wall.share":               "Partagez votre expérience",
        "wall.filter.all":          "Tout",
        "wall.filter.official":     "De KeyDo",
        "wall.filter.tips":         "Astuces",
        "wall.filter.showcase":     "Vitrines",
        "wall.filter.experience":   "Expériences",
        "wall.submit":              "Envoyer",
        "wall.pending_approval":    "Les publications sont vérifiées avant d'apparaître.",
        "common.sign_in":           "Connexion",
        "common.sign_out":          "Déconnexion",
        "common.close":             "Fermer",
        "common.done":              "Terminé",
        "common.cancel":            "Annuler",
        "common.retry":             "Réessayer",
        "common.loading":           "Chargement…",
    ]
}

// MARK: - Arabic

private enum Arabic {
    static let strings: [String: String] = [
        "home.welcome":             "مرحبًا بك في KeyDo",
        "home.search.placeholder":  "ابحث عن اختصارات، مجموعات، تطبيقات…",
        "home.ask_keydo":           "اسأل KeyDo",
        "sub.free":                 "مجاني",
        "sub.pro":                  "برو",
        "sub.teams":                "الفرق",
        "sub.upgrade.title":        "افتح KeyDo بالكامل",
        "sub.upgrade.body":         "مجموعات غير محدودة، مزامنة سحابية، ميزات الذكاء الاصطناعي، ومتجر القوالب.",
        "sub.per_month":            "/شهر",
        "sub.per_year":             "/سنة",
        "sub.get_pro":              "احصل على برو",
        "sub.get_teams":            "احصل على الفرق",
        "sub.current_plan":         "الخطة الحالية",
        "challenge.title":          "تحدي KeyDo لـ 7 أيام",
        "challenge.day":            "اليوم %d",
        "challenge.complete":       "وضع علامة مكتمل",
        "challenge.badge.title":    "لقد حصلت على شارة KeyDo Pro!",
        "challenge.share.text":     "أكملت تحدي KeyDo لـ 7 أيام 🏆 — أوفر ساعات كل أسبوع باختصارات لوحة المفاتيح. جربه مجانًا على keydo.app",
        "store.title":              "متجر KeyDo",
        "store.install":            "تثبيت",
        "store.installed":          "مثبَّت",
        "store.publish":            "نشر حزمة",
        "store.search.placeholder": "البحث في الحزم…",
        "store.free":               "مجاني",
        "wall.title":               "جدار KeyDo",
        "wall.share":               "شارك تجربتك",
        "wall.filter.all":          "الكل",
        "wall.filter.official":     "من KeyDo",
        "wall.filter.tips":         "نصائح",
        "wall.filter.showcase":     "عروض",
        "wall.filter.experience":   "تجارب",
        "wall.submit":              "إرسال",
        "wall.pending_approval":    "تُراجع المشاركات قبل الظهور.",
        "common.sign_in":           "تسجيل الدخول",
        "common.sign_out":          "تسجيل الخروج",
        "common.close":             "إغلاق",
        "common.done":              "تم",
        "common.cancel":            "إلغاء",
        "common.retry":             "إعادة المحاولة",
        "common.loading":           "جارٍ التحميل…",
    ]
}

// MARK: - Japanese

private enum Japanese {
    static let strings: [String: String] = [
        "home.welcome":             "KeyDoへようこそ",
        "home.search.placeholder":  "ショートカット、コレクション、アプリを検索…",
        "home.ask_keydo":           "KeyDoに聞く",
        "sub.free":                 "無料",
        "sub.pro":                  "Pro",
        "sub.teams":                "Teams",
        "sub.upgrade.title":        "KeyDoをフル活用する",
        "sub.upgrade.body":         "無制限のコレクション、クラウド同期、AI機能、テンプレートストアをご利用いただけます。",
        "sub.per_month":            "/月",
        "sub.per_year":             "/年",
        "sub.get_pro":              "Proを取得",
        "sub.get_teams":            "Teamsを取得",
        "sub.current_plan":         "現在のプラン",
        "challenge.title":          "7日間 KeyDo チャレンジ",
        "challenge.day":            "%d日目",
        "challenge.complete":       "完了としてマーク",
        "challenge.badge.title":    "KeyDo Proバッジを獲得しました！",
        "challenge.share.text":     "7日間 KeyDo チャレンジを完了しました 🏆 — キーボードショートカットで毎週何時間も節約中。keydo.appで無料でお試しください",
        "store.title":              "KeyDoストア",
        "store.install":            "インストール",
        "store.installed":          "インストール済み",
        "store.publish":            "パックを公開",
        "store.search.placeholder": "パックを検索…",
        "store.free":               "無料",
        "wall.title":               "KeyDo ウォール",
        "wall.share":               "あなたの体験を共有",
        "wall.filter.all":          "すべて",
        "wall.filter.official":     "KeyDoより",
        "wall.filter.tips":         "ヒント",
        "wall.filter.showcase":     "ショーケース",
        "wall.filter.experience":   "体験",
        "wall.submit":              "送信",
        "wall.pending_approval":    "投稿は表示前に審査されます。",
        "common.sign_in":           "サインイン",
        "common.sign_out":          "サインアウト",
        "common.close":             "閉じる",
        "common.done":              "完了",
        "common.cancel":            "キャンセル",
        "common.retry":             "再試行",
        "common.loading":           "読み込み中…",
    ]
}

// MARK: - German

private enum German {
    static let strings: [String: String] = [
        "home.welcome":             "Willkommen bei KeyDo",
        "home.search.placeholder":  "Kürzel, Sammlungen, Apps suchen…",
        "home.ask_keydo":           "KeyDo fragen",
        "sub.free":                 "Kostenlos",
        "sub.pro":                  "Pro",
        "sub.teams":                "Teams",
        "sub.upgrade.title":        "Das volle KeyDo freischalten",
        "sub.upgrade.body":         "Unbegrenzte Sammlungen, Cloud-Sync, KI-Funktionen und der Template-Shop.",
        "sub.per_month":            "/Monat",
        "sub.per_year":             "/Jahr",
        "sub.get_pro":              "Pro holen",
        "sub.get_teams":            "Teams holen",
        "sub.current_plan":         "Aktueller Plan",
        "challenge.title":          "7-Tage KeyDo Challenge",
        "challenge.day":            "Tag %d",
        "challenge.complete":       "Als abgeschlossen markieren",
        "challenge.badge.title":    "Sie haben das KeyDo-Pro-Abzeichen erhalten!",
        "challenge.share.text":     "Ich habe die 7-Tage KeyDo Challenge abgeschlossen 🏆 — spare jede Woche Stunden mit Tastaturkürzeln. Kostenlos ausprobieren auf keydo.app",
        "store.title":              "KeyDo Store",
        "store.install":            "Installieren",
        "store.installed":          "Installiert",
        "store.publish":            "Pack veröffentlichen",
        "store.search.placeholder": "Packs suchen…",
        "store.free":               "Kostenlos",
        "wall.title":               "KeyDo Wall",
        "wall.share":               "Erfahrung teilen",
        "wall.filter.all":          "Alle",
        "wall.filter.official":     "Von KeyDo",
        "wall.filter.tips":         "Tipps",
        "wall.filter.showcase":     "Showcases",
        "wall.filter.experience":   "Erfahrungen",
        "wall.submit":              "Senden",
        "wall.pending_approval":    "Beiträge werden vor der Anzeige geprüft.",
        "common.sign_in":           "Anmelden",
        "common.sign_out":          "Abmelden",
        "common.close":             "Schließen",
        "common.done":              "Fertig",
        "common.cancel":            "Abbrechen",
        "common.retry":             "Erneut versuchen",
        "common.loading":           "Wird geladen…",
    ]
}
