import Foundation
import Combine

struct WeatherCity: Codable, Identifiable, Equatable {
    let id: Int
    let name: String
    let latitude: Double
    let longitude: Double
    let country: String?
    let admin1: String?
    var feature_code: String? = nil
    var label: String { [name, admin1, country].compactMap { $0 }.joined(separator: ", ") }
    var isValid: Bool { latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude) }
}

struct WeatherReading: Codable, Equatable {
    let temperature: Double
    let code: Int
    let isDay: Bool
    let date: Date
    var temperatureText: String { String(format: "%.0f°", temperature.rounded() == 0 ? 0 : temperature) }
    func isStale(at now: Date) -> Bool { now.timeIntervalSince(date) > 3600 }
    var symbol: String {
        switch code {
        case 0: return isDay ? "sun.max" : "moon"
        case 1, 2: return isDay ? "cloud.sun" : "cloud.moon"
        case 3: return "cloud"
        case 45, 48: return "cloud.fog"
        case 51, 53, 55: return "cloud.drizzle"
        case 56, 57, 66, 67: return "cloud.sleet"
        case 61, 63, 65, 80, 81, 82: return "cloud.rain"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow"
        case 95, 96, 99: return "cloud.bolt.rain"
        default: return "questionmark"
        }
    }
}

enum WeatherAPI {
    static func searchURL(_ name: String, language: String) -> URL {
        var url = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        url.queryItems = [URLQueryItem(name: "name", value: name), URLQueryItem(name: "count", value: "10"), URLQueryItem(name: "language", value: language)]
        return url.url!
    }
    static func forecastURL(_ city: WeatherCity) -> URL {
        var url = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        url.queryItems = [
            URLQueryItem(name: "latitude", value: String(city.latitude)),
            URLQueryItem(name: "longitude", value: String(city.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "temperature_unit", value: "celsius"),
            URLQueryItem(name: "timeformat", value: "unixtime")
        ]
        return url.url!
    }
    static func decodeCities(_ data: Data) throws -> [WeatherCity] {
        struct Response: Decodable { let results: [WeatherCity]? }
        let results = try JSONDecoder().decode(Response.self, from: data).results ?? []
        return Array(results.filter { $0.isValid && ($0.feature_code?.hasPrefix("PPL") ?? true) }.prefix(5))
    }
    static func decodeReading(_ data: Data, now: Date) throws -> WeatherReading {
        struct Response: Decodable {
            struct Current: Decodable { let temperature_2m: Double; let weather_code: Int; let is_day: Int; let time: Double }
            let current: Current
        }
        let value = try JSONDecoder().decode(Response.self, from: data).current
        guard value.temperature_2m.isFinite, (-100...70).contains(value.temperature_2m),
              value.time.isFinite, value.time > 0, value.time <= now.timeIntervalSince1970 + 900,
              [0, 1].contains(value.is_day) else { throw URLError(.cannotParseResponse) }
        return WeatherReading(temperature: value.temperature_2m, code: value.weather_code, isDay: value.is_day == 1, date: Date(timeIntervalSince1970: value.time))
    }
}

private final class WeatherRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

final class WeatherStore: ObservableObject {
    static let shared = WeatherStore()
    static let cacheKey = "weatherSelectionAndReading"
    private struct Cache: Codable { let city: WeatherCity; let reading: WeatherReading? }
    @Published private(set) var city: WeatherCity?
    @Published private(set) var reading: WeatherReading?
    @Published private(set) var results: [WeatherCity] = []
    @Published private(set) var searching = false
    @Published private(set) var searchFailed = false
    @Published private(set) var searched = false
    @Published private(set) var loading = false
    @Published private(set) var failed = false
    @Published private(set) var now = Date()
    private let defaults: UserDefaults
    private let session: URLSession
    private let clock: () -> Date
    private var weatherTask: URLSessionDataTask?
    private var searchTask: URLSessionDataTask?
    private var generation = UUID()
    private var searchGeneration = UUID()
    private var lastAttempt: Date?
    private var timer: Timer?

    init(defaults: UserDefaults = .standard, session: URLSession? = nil, startAutomatically: Bool = true, clock: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.clock = clock
        now = clock()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        self.session = session ?? URLSession(configuration: configuration, delegate: WeatherRedirectPolicy(), delegateQueue: nil)
        if let data = defaults.data(forKey: Self.cacheKey), let cache = try? JSONDecoder().decode(Cache.self, from: data), cache.city.isValid {
            city = cache.city
            if let saved = cache.reading, saved.temperature.isFinite, (-100...70).contains(saved.temperature), saved.date.timeIntervalSince1970 > 0, saved.date <= now.addingTimeInterval(900) { reading = saved }
        }
        if startAutomatically {
            refresh()
            timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refresh() }
            timer?.tolerance = 10
        }
    }
    deinit { timer?.invalidate(); weatherTask?.cancel(); searchTask?.cancel(); session.invalidateAndCancel() }

    func search(_ text: String) {
        cancelSearch()
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { return }
        searching = true
        let token = searchGeneration
        searchTask = session.dataTask(with: WeatherAPI.searchURL(query, language: AppLanguage.english ? "en" : "ru")) { [weak self] data, response, error in
            let cities: [WeatherCity]? = error == nil && (response as? HTTPURLResponse)?.statusCode == 200 ? data.flatMap { try? WeatherAPI.decodeCities($0) } : nil
            DispatchQueue.main.async {
                guard let self, self.searchGeneration == token else { return }
                self.searching = false
                self.searched = true
                self.searchFailed = cities == nil
                self.results = cities ?? []
                self.searchTask = nil
            }
        }
        searchTask?.resume()
    }
    func cancelSearch() {
        searchGeneration = UUID()
        searchTask?.cancel(); searchTask = nil
        searching = false; searched = false; searchFailed = false; results = []
    }
    func select(_ selection: WeatherCity?) {
        guard selection == nil || selection!.isValid else { return }
        generation = UUID()
        weatherTask?.cancel(); weatherTask = nil
        cancelSearch()
        city = selection; reading = nil; failed = false; loading = false; lastAttempt = nil
        persist()
        refresh()
    }
    private func persist() {
        if let city, let data = try? JSONEncoder().encode(Cache(city: city, reading: reading)) { defaults.set(data, forKey: Self.cacheKey) }
        else { defaults.removeObject(forKey: Self.cacheKey) }
    }
    func refresh() {
        now = clock()
        guard let city, !loading, lastAttempt.map({ now.timeIntervalSince($0) >= 900 }) ?? true else { return }
        lastAttempt = now
        loading = true
        let token = generation
        weatherTask = session.dataTask(with: WeatherAPI.forecastURL(city)) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                let reading = error == nil && (response as? HTTPURLResponse)?.statusCode == 200 ? data.flatMap { try? WeatherAPI.decodeReading($0, now: self.clock()) } : nil
                self.loading = false
                self.failed = reading == nil
                self.weatherTask = nil
                if let reading { self.reading = reading; self.persist() }
                self.now = self.clock()
            }
        }
        weatherTask?.resume()
    }
}
