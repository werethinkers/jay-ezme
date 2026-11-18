// Live facts for formulas, from free sources that need no key: where you are (city and place), the weather, sunrise and
// sunset, air quality, exchange rates, crypto prices and a quote of the day. Formulas read the last value that was fetched,
// so they answer at once; the values are refreshed in the background when the app starts and when a form opens.
import Foundation
import CoreLocation

enum LiveData {
    private static let store = UserDefaults.standard
    private static let lock = NSLock()
    private static var refreshing = false

    // MARK: Reading

    static func value(_ key: String) -> String { store.string(forKey: "ezmeLive." + key) ?? "" }
    private static func set(_ key: String, _ value: String) { if !value.isEmpty { store.set(value, forKey: "ezmeLive." + key) } }
    private static var stamp: Date { Date(timeIntervalSince1970: store.double(forKey: "ezmeLive.stamp")) }

    /// Starts a background refresh when the last one is older than ten minutes. Safe to call as often as you like.
    static func prefetch() {
        guard Date().timeIntervalSince(stamp) > 600 else { return }
        Task.detached { await refresh() }
    }

    /// The cached answer for a live word or function, or nil when the name is not a live one.
    static func evaluate(_ name: String, args: [String], now: Date) -> WishValue? {
        let upper = name.uppercased()
        if words.contains(name.lowercased()) || ["TEMP", "STATE", "AIRQUALITY"].contains(upper) { store.set(true, forKey: "ezmeLive.used") }
        func ready(_ key: String, _ fallback: String = "\u{2014}") -> WishValue {
            let found = value(key)
            if found.isEmpty { prefetchSoon(); return .text(fallback) }
            return .text(found)
        }
        switch name.uppercased() {
        case "CITY": return ready("city")
        case "REGION", "STATE": return ready("region")
        case "COUNTRY": return ready("country")
        case "AREA", "NEIGHBOURHOOD": return ready("area")
        case "PLACENAME", "ADDRESS": return ready("placename")
        case "PLACE", "LOCATION":
            let area = value("area")
            let parts = (area.isEmpty ? [value("city"), value("region"), value("country")] : [area, value("city"), value("region")]).filter { !$0.isEmpty }
            if parts.isEmpty { prefetchSoon(); return .text("\u{2014}") }
            return .text(parts.joined(separator: ", "))
        case "COORDS": return ready("coords")
        case "TEMPERATURE", "TEMP": return ready("temperature")
        case "WEATHER": return ready("weather")
        case "HUMIDITY": return ready("humidity")
        case "WIND": return ready("wind")
        case "SUNRISE": return ready("sunrise")
        case "SUNSET": return ready("sunset")
        case "UV": return ready("uv")
        case "AQI", "AIRQUALITY": return ready("aqi")
        case "QUOTE": return ready("quote")
        case "MOON": return .text(moonPhase(now))
        case "DAYOFYEAR": return .number(Double(Calendar.current.ordinality(of: .day, in: .year, for: now) ?? 1))
        case "YEARLEFT":
            let day = Calendar.current.ordinality(of: .day, in: .year, for: now) ?? 1
            let total = Calendar.current.range(of: .day, in: .year, for: now)?.count ?? 365
            return .number(Double(total - day))
        case "RATE":
            let from = (args.count > 0 ? args[0] : "USD").uppercased(), to = (args.count > 1 ? args[1] : "INR").uppercased()
            let key = "rate.\(from).\(to)"
            if let number = Double(value(key)) { return .number(number) }
            pending(rate: (from, to))
            return .text("\u{2014}")
        case "CRYPTO":
            let coin = (args.count > 0 ? args[0] : "bitcoin").lowercased(), currency = (args.count > 1 ? args[1] : "inr").lowercased()
            let key = "crypto.\(coin).\(currency)"
            if let number = Double(value(key)) { return .number(number) }
            pending(crypto: (coin, currency))
            return .text("\u{2014}")
        default: return nil
        }
    }

    /// The names that work on their own, like =City or =Temperature.
    static let words: Set<String> = ["city", "area", "placename", "region", "country", "place", "location", "coords", "temperature", "weather", "humidity", "wind", "sunrise", "sunset", "uv", "aqi", "quote", "moon", "dayofyear", "yearleft"]

    private static func prefetchSoon() { Task.detached { await refresh(force: false) } }

    // MARK: Things asked for by name that are not cached yet

    private static var wantedRates: Set<String> = []
    private static var wantedCoins: Set<String> = []
    private static func pending(rate: (String, String)) {
        lock.lock(); let isNew = wantedRates.insert("\(rate.0).\(rate.1)").inserted; lock.unlock()
        if isNew { Task.detached { await fetchRate(rate.0, rate.1) } }
    }
    private static func pending(crypto: (String, String)) {
        lock.lock(); let isNew = wantedCoins.insert("\(crypto.0).\(crypto.1)").inserted; lock.unlock()
        if isNew { Task.detached { await fetchCrypto(crypto.0, crypto.1) } }
    }

    // MARK: Fetching

    private static func json(_ address: String) async -> [String: Any]? {
        guard let url = URL(string: address) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("KeyDo", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func begin(force: Bool) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if refreshing { return false }
        if !force, Date().timeIntervalSince(stamp) < 120 { return false }
        refreshing = true
        return true
    }
    private static func finish() { lock.lock(); refreshing = false; lock.unlock() }

    static func refresh(force: Bool = true) async {
        guard begin(force: force) else { return }
        defer { finish() }

        // Where you are: this Mac's own location (street level) when you allow it, otherwise your internet address (city level).
        var latitude: Double?, longitude: Double?
        let allowPrompt = store.bool(forKey: "ezmeLive.used")
        if let here = await DeviceLocator.shared.locate(allowPrompt: allowPrompt) {
            latitude = here.coordinate.latitude
            longitude = here.coordinate.longitude
            if let mark = try? await CLGeocoder().reverseGeocodeLocation(here).first {
                set("city", mark.locality ?? mark.subAdministrativeArea ?? "")
                set("region", mark.administrativeArea ?? "")
                set("country", mark.country ?? "")
                store.set(mark.subLocality ?? "", forKey: "ezmeLive.area")
                let named = mark.name ?? mark.thoroughfare ?? ""
                store.set(named, forKey: "ezmeLive.placename")
            }
            store.set("device", forKey: "ezmeLive.source")
        } else if let place = await json("https://ipwho.is/"), (place["success"] as? Bool) != false {
            set("city", place["city"] as? String ?? "")
            set("region", place["region"] as? String ?? "")
            set("country", place["country"] as? String ?? "")
            store.removeObject(forKey: "ezmeLive.area"); store.removeObject(forKey: "ezmeLive.placename")
            latitude = place["latitude"] as? Double
            longitude = place["longitude"] as? Double
        } else if let place = await json("https://ipapi.co/json/") {
            set("city", place["city"] as? String ?? "")
            set("region", place["region"] as? String ?? "")
            set("country", place["country_name"] as? String ?? "")
            store.removeObject(forKey: "ezmeLive.area"); store.removeObject(forKey: "ezmeLive.placename")
            latitude = place["latitude"] as? Double
            longitude = place["longitude"] as? Double
        }
        if let latitude, let longitude {
            set("coords", String(format: "%.4f, %.4f", latitude, longitude))
            let at = "latitude=\(latitude)&longitude=\(longitude)"
            if let weather = await json("https://api.open-meteo.com/v1/forecast?\(at)&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m&daily=sunrise,sunset,uv_index_max&timezone=auto&forecast_days=1") {
                if let current = weather["current"] as? [String: Any] {
                    if let t = current["temperature_2m"] as? Double { set("temperature", "\(Int(t.rounded()))\u{00B0}C") }
                    if let h = current["relative_humidity_2m"] as? Double { set("humidity", "\(Int(h.rounded()))%") }
                    if let w = current["wind_speed_10m"] as? Double { set("wind", "\(Int(w.rounded())) km/h") }
                    if let code = current["weather_code"] as? Int { set("weather", describe(code)) }
                }
                if let daily = weather["daily"] as? [String: Any] {
                    if let rise = (daily["sunrise"] as? [String])?.first { set("sunrise", clock(rise)) }
                    if let setting = (daily["sunset"] as? [String])?.first { set("sunset", clock(setting)) }
                    if let uv = (daily["uv_index_max"] as? [Double])?.first { set("uv", String(format: "%.0f", uv)) }
                }
            }
            if let air = await json("https://air-quality-api.open-meteo.com/v1/air-quality?\(at)&current=us_aqi"),
               let current = air["current"] as? [String: Any], let aqi = current["us_aqi"] as? Double {
                set("aqi", "\(Int(aqi.rounded())) (\(aqiWord(aqi)))")
            }
        }
        // Money, the usual pairs.
        for (from, to) in [("USD", "INR"), ("EUR", "INR"), ("GBP", "INR"), ("AED", "INR")] { await fetchRate(from, to) }
        await fetchCrypto("bitcoin", "inr")
        if let quote = await quoteOfTheDay() { set("quote", quote) }
        store.set(Date().timeIntervalSince1970, forKey: "ezmeLive.stamp")
    }

    private static func fetchRate(_ from: String, _ to: String) async {
        if let data = await json("https://api.frankfurter.app/latest?from=\(from)&to=\(to)"), let rates = data["rates"] as? [String: Any], let rate = rates[to] as? Double {
            set("rate.\(from).\(to)", String(rate))
        }
    }

    private static func fetchCrypto(_ coin: String, _ currency: String) async {
        let safeCoin = coin.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? coin
        if let data = await json("https://api.coingecko.com/api/v3/simple/price?ids=\(safeCoin)&vs_currencies=\(currency)"),
           let entry = data[coin] as? [String: Any], let price = entry[currency] as? Double {
            set("crypto.\(coin).\(currency)", String(price))
        }
    }

    /// ZenQuotes gives one free quote a day; the credit line goes with it.
    private static func quoteOfTheDay() async -> String? {
        guard let url = URL(string: "https://zenquotes.io/api/today"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = list.first, let text = first["q"] as? String, !text.isEmpty else { return nil }
        let author = (first["a"] as? String) ?? ""
        return author.isEmpty ? text : "\(text) \u{2014} \(author)"
    }

    // MARK: Words for numbers

    private static func clock(_ iso: String) -> String {
        let input = DateFormatter()
        input.locale = Locale(identifier: "en_US_POSIX")
        input.dateFormat = "yyyy-MM-dd'T'HH:mm"
        guard let date = input.date(from: iso) else { return iso }
        let output = DateFormatter()
        output.locale = Locale(identifier: "en_IN")
        output.dateFormat = "h:mm a"
        return output.string(from: date)
    }

    private static func aqiWord(_ value: Double) -> String {
        switch value {
        case ..<51: return "Good"
        case ..<101: return "Moderate"
        case ..<151: return "Unhealthy for some"
        case ..<201: return "Unhealthy"
        case ..<301: return "Very unhealthy"
        default: return "Hazardous"
        }
    }

    private static func describe(_ code: Int) -> String {
        switch code {
        case 0: return "Clear sky"
        case 1: return "Mostly clear"
        case 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Foggy"
        case 51, 53, 55, 56, 57: return "Drizzle"
        case 61, 63, 65, 66, 67: return "Rain"
        case 71, 73, 75, 77: return "Snow"
        case 80, 81, 82: return "Rain showers"
        case 85, 86: return "Snow showers"
        case 95, 96, 99: return "Thunderstorm"
        default: return "Fair"
        }
    }

    /// The phase of the moon, worked out here with no internet.
    static func moonPhase(_ date: Date) -> String {
        let synodic = 29.530588853
        let reference = Date(timeIntervalSince1970: 947182440) // a new moon, 6 January 2000
        let days = date.timeIntervalSince(reference) / 86400
        let age = days - (days / synodic).rounded(.down) * synodic
        switch age {
        case ..<1.85: return "New moon"
        case ..<5.54: return "Waxing crescent"
        case ..<9.23: return "First quarter"
        case ..<12.92: return "Waxing gibbous"
        case ..<16.61: return "Full moon"
        case ..<20.30: return "Waning gibbous"
        case ..<23.99: return "Last quarter"
        case ..<27.68: return "Waning crescent"
        default: return "New moon"
        }
    }
}

extension WishFunctionCatalog {
    /// Live and place functions. Their values come from free sources and are kept fresh in the background.
    static let live: [WishFunctionInfo] = [
        WishFunctionInfo("CITY", "CITY()", "The city you are in now, from this Mac's location or your internet address.", "Live & place"),
        WishFunctionInfo("PLACE", "PLACE()", "Where you are, like Koregaon Park, Pune, Maharashtra. Uses this Mac's location when allowed.", "Live & place"),
        WishFunctionInfo("AREA", "AREA()", "The neighbourhood you are in (needs location allowed).", "Live & place"),
        WishFunctionInfo("PLACENAME", "PLACENAME()", "The name of the spot or street you are at (needs location allowed).", "Live & place"),
        WishFunctionInfo("REGION", "REGION()", "The state or region you are in.", "Live & place"),
        WishFunctionInfo("COUNTRY", "COUNTRY()", "The country you are in.", "Live & place"),
        WishFunctionInfo("COORDS", "COORDS()", "Latitude and longitude of the city.", "Live & place"),
        WishFunctionInfo("TEMPERATURE", "TEMPERATURE()", "The temperature now where you are (Open-Meteo).", "Live & place"),
        WishFunctionInfo("WEATHER", "WEATHER()", "Clear, cloudy, rain and so on, now where you are.", "Live & place"),
        WishFunctionInfo("HUMIDITY", "HUMIDITY()", "How humid it is now.", "Live & place"),
        WishFunctionInfo("WIND", "WIND()", "Wind speed now in km/h.", "Live & place"),
        WishFunctionInfo("SUNRISE", "SUNRISE()", "Today's sunrise time where you are.", "Live & place"),
        WishFunctionInfo("SUNSET", "SUNSET()", "Today's sunset time where you are.", "Live & place"),
        WishFunctionInfo("UV", "UV()", "Today's highest UV index.", "Live & place"),
        WishFunctionInfo("AQI", "AQI()", "Air quality now, with a word like Good or Unhealthy.", "Live & place"),
        WishFunctionInfo("RATE", "RATE(\"USD\", \"INR\")", "Exchange rate between two currencies (Frankfurter). It is a number, so it multiplies: =RATE(\"USD\",\"INR\")*amount.", "Live & place"),
        WishFunctionInfo("CRYPTO", "CRYPTO(\"bitcoin\", \"inr\")", "Price of a coin in a currency (CoinGecko).", "Live & place"),
        WishFunctionInfo("QUOTE", "QUOTE()", "Quote of the day, with its author (ZenQuotes).", "Live & place"),
        WishFunctionInfo("MOON", "MOON()", "Today's moon phase, worked out on your Mac.", "Live & place"),
        WishFunctionInfo("DAYOFYEAR", "DAYOFYEAR()", "Which day of the year it is, 1 to 366.", "Live & place"),
        WishFunctionInfo("YEARLEFT", "YEARLEFT()", "Days left in this year.", "Live & place")
    ]
}


/// This Mac's own location, asked for only once something uses a place word. Without permission formulas fall back to the internet address.
@MainActor final class DeviceLocator: NSObject, CLLocationManagerDelegate {
    static let shared = DeviceLocator()
    private let manager = CLLocationManager()
    private var waiting: [CheckedContinuation<CLLocation?, Never>] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func locate(allowPrompt: Bool) async -> CLLocation? {
        guard CLLocationManager.locationServicesEnabled() else { return nil }
        let status = manager.authorizationStatus
        if status == .denied || status == .restricted { return nil }
        if status == .notDetermined {
            guard allowPrompt else { return nil }
            manager.requestWhenInUseAuthorization()
        }
        return await withCheckedContinuation { (continuation: CheckedContinuation<CLLocation?, Never>) in
            waiting.append(continuation)
            if manager.authorizationStatus != .notDetermined { manager.requestLocation() }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                self.finish(nil)
            }
        }
    }

    private func finish(_ location: CLLocation?) {
        let pending = waiting
        waiting = []
        for continuation in pending { continuation.resume(returning: location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let first = locations.last
        Task { @MainActor in self.finish(first) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let status = self.manager.authorizationStatus
            if status == .denied || status == .restricted { self.finish(nil) }
            else if status != .notDetermined, !self.waiting.isEmpty { self.manager.requestLocation() }
        }
    }
}
