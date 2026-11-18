import CoreLocation
import EventKit
import Foundation

/// The next event from the Mac's Calendar, for the notch. Asks for access only when that part is turned on.
@MainActor
final class CalendarGlance: ObservableObject {
    static let shared = CalendarGlance()
    struct Event: Equatable { var title: String; var start: Date; var allDay: Bool }
    @Published private(set) var next: Event?
    @Published private(set) var allowed = EKEventStore.authorizationStatus(for: .event) == .fullAccess
    private let store = EKEventStore()

    func requestAccess() {
        Task { allowed = (try? await store.requestFullAccessToEvents()) ?? false; refresh() }
    }

    /// The next event that hasn't ended, today or tomorrow.
    func refresh(now: Date = Date()) {
        allowed = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        guard allowed, let end = Calendar.current.date(byAdding: .day, value: 2, to: Calendar.current.startOfDay(for: now)) else { next = nil; return }
        let events = store.events(matching: store.predicateForEvents(withStart: now, end: end, calendars: nil))
            .filter { $0.endDate > now }
            .sorted { ($0.isAllDay ? 1 : 0, $0.startDate) < ($1.isAllDay ? 1 : 0, $1.startDate) }
        next = events.first.map { Event(title: $0.title ?? "Event", start: $0.startDate, allDay: $0.isAllDay) }
    }
}

/// UV index and temperature from Open-Meteo (free, no key, no account). Only the city's rough
/// coordinates are sent, at most every 30 minutes, and never in offline mode.
@MainActor
final class WeatherGlance: ObservableObject {
    static let shared = WeatherGlance()
    @Published private(set) var uv: Double?
    @Published private(set) var uvMax: Double?
    @Published private(set) var temperature: Double?
    @Published var message: String?
    private var fetched: Date?
    var city: String { UserDefaults.standard.string(forKey: "moi.weatherCity") ?? "" }

    static func level(_ uv: Double) -> String {
        switch uv { case ..<3: "Low"; case ..<6: "Moderate"; case ..<8: "High"; case ..<11: "Very high"; default: "Extreme" }
    }

    /// Looks the city up once (Apple's map service) and remembers where it is.
    func setCity(_ name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        do {
            guard let place = try await CLGeocoder().geocodeAddressString(trimmed).first, let location = place.location else { message = "I couldn't find “\(trimmed)”."; return }
            UserDefaults.standard.set(place.locality ?? trimmed, forKey: "moi.weatherCity")
            UserDefaults.standard.set(location.coordinate.latitude, forKey: "moi.weatherLat")
            UserDefaults.standard.set(location.coordinate.longitude, forKey: "moi.weatherLon")
            message = nil; fetched = nil
            await refresh()
        } catch { message = "I couldn't look that place up: \(error.localizedDescription)" }
    }

    func refresh() async {
        if let fetched, Date().timeIntervalSince(fetched) < 1800 { return }
        guard !(UserDefaults.standard.object(forKey: "moi.offline") as? Bool ?? true) else { message = "Weather is off while offline mode is on."; return }
        guard !city.isEmpty else { message = "Choose your city in the notch editor."; return }
        let lat = UserDefaults.standard.double(forKey: "moi.weatherLat"), lon = UserDefaults.standard.double(forKey: "moi.weatherLon")
        guard let url = URL(string: String(format: "https://api.open-meteo.com/v1/forecast?latitude=%.2f&longitude=%.2f&current=temperature_2m,uv_index&daily=uv_index_max&forecast_days=1&timezone=auto", lat, lon)) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let current = json?["current"] as? [String: Any]
            uv = current?["uv_index"] as? Double
            temperature = current?["temperature_2m"] as? Double
            uvMax = ((json?["daily"] as? [String: Any])?["uv_index_max"] as? [Double])?.first
            fetched = Date(); message = uv == nil ? "The weather service sent nothing back." : nil
        } catch { message = "Couldn't get the weather right now." }
    }
}
