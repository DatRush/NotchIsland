import Foundation

var checks = 0
func check(_ value: @autoclosure () -> Bool, _ name: String) {
    precondition(value(), name)
    checks += 1
}
func wait(_ predicate: () -> Bool) {
    let deadline = Date().addingTimeInterval(3)
    while !predicate() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    precondition(predicate(), "Timed out waiting for response")
}
final class Stub: URLProtocol {
    static var pending: [Stub] = []
    static var count = 0
    private var stopped = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        DispatchQueue.main.async { Self.count += 1; Self.pending.append(self) }
    }
    override func stopLoading() { stopped = true }
    func reply(_ body: String, status: Int = 200) {
        guard !stopped else { return }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}
func next() -> Stub {
    wait { !Stub.pending.isEmpty }
    return Stub.pending.removeFirst()
}
let suite = "NotchIsland-Weather-Checks-" + UUID().uuidString
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
let configuration = URLSessionConfiguration.ephemeral
configuration.protocolClasses = [Stub.self]
let session = URLSession(configuration: configuration)
var now = Date(timeIntervalSince1970: 1_800_000_000)
let store = WeatherStore(defaults: defaults, session: session, startAutomatically: false, clock: { now })
let rome = WeatherCity(id: 1, name: "Roma", latitude: 41.9, longitude: 12.5, country: "Italia", admin1: "Lazio")
let paris = WeatherCity(id: 2, name: "Paris", latitude: 48.9, longitude: 2.3, country: "France", admin1: nil)
func payload(_ temperature: Double = 12, code: Int = 2, day: Int = 1, time: Double? = nil) -> String {
    "{\"current\":{\"temperature_2m\":\(temperature),\"weather_code\":\(code),\"is_day\":\(day),\"time\":\(time ?? now.timeIntervalSince1970)}}"
}
func decode(_ text: String) -> WeatherReading? { try? WeatherAPI.decodeReading(Data(text.utf8), now: now) }

check(store.city == nil && Stub.count == 0, "No requests before city selection")
check(decode(payload(-0.2))?.temperatureText == "0°", "No negative zero")
check(decode(payload(-12.6))?.temperatureText == "-13°", "Negative temperature rounding")
check(decode(payload(12, code: 0, day: 0))?.symbol == "moon", "Night icon")
check(decode(payload(12, code: 95))?.symbol == "cloud.bolt.rain", "Thunderstorm icon")
check(decode(payload(12, code: 999))?.symbol == "questionmark", "Unknown code does not invent weather")
check(decode(payload(1000)) == nil, "Invalid temperature rejected")
check(decode(payload(time: now.timeIntervalSince1970 + 3600)) == nil, "Future data rejected")
check(decode("{\"current\":null}") == nil, "Missing current conditions rejected")
check(decode(payload(day: 4)) == nil, "Invalid day value rejected")
check(decode(payload(time: now.timeIntervalSince1970 - 3601))!.isStale(at: now), "Old data marked stale")
check((try! WeatherAPI.decodeCities(Data("{}".utf8))).isEmpty, "Empty geocoding response")
check((try! WeatherAPI.decodeCities(Data("{\"results\":[{\"id\":1,\"name\":\"Romania\",\"latitude\":46,\"longitude\":25,\"feature_code\":\"PCLI\"}]}".utf8))).isEmpty, "Country matches excluded from city search")
check(WeatherAPI.searchURL("A&B Москва", language: "ru").query!.contains("%26"), "Search query escaping")
check(URLComponents(url: WeatherAPI.forecastURL(rome), resolvingAgainstBaseURL: false)!.queryItems!.contains(URLQueryItem(name: "temperature_unit", value: "celsius")), "Explicit Celsius units")

store.select(rome)
let initial = next()
store.refresh()
check(Stub.count == 1, "No parallel weather request")
initial.reply(payload())
wait { !store.loading }
check(store.reading?.temperature == 12 && !store.failed, "Successful response")
check(defaults.data(forKey: WeatherStore.cacheKey) != nil, "Selection and reading cached together")
let restored = WeatherStore(defaults: defaults, startAutomatically: false, clock: { now })
check(restored.city == rome && restored.reading == store.reading, "Cache restored")
store.refresh()
RunLoop.main.run(until: Date().addingTimeInterval(0.05))
check(Stub.count == 1, "Refresh interval enforced")
now = now.addingTimeInterval(901)
store.refresh()
next().reply("{}", status: 503)
wait { !store.loading }
check(store.failed && store.reading?.temperature == 12, "Network failure preserves last reading")
store.select(paris)
let pendingParis = next()
check(store.reading == nil, "City change never displays previous city's weather")
store.select(rome)
let pendingRome = next()
pendingParis.reply(payload(25))
pendingRome.reply(payload(8))
wait { !store.loading }
check(store.city == rome && store.reading?.temperature == 8, "Late result cannot overwrite selected city")
now = now.addingTimeInterval(901)
store.refresh()
let pendingOff = next()
store.select(nil)
pendingOff.reply(payload(30))
RunLoop.main.run(until: Date().addingTimeInterval(0.05))
check(store.city == nil && store.reading == nil && !store.loading, "Turning off cancels weather")
check(defaults.data(forKey: WeatherStore.cacheKey) == nil, "Turning off removes persisted data")
store.search("Roma")
next().reply("{\"results\":[{\"id\":1,\"name\":\"Roma\",\"latitude\":41.9,\"longitude\":12.5,\"country\":\"Italia\",\"admin1\":\"Lazio\"}]}")
wait { !store.searching }
check(store.results == [rome], "Geocoding result decoded")
store.search("Paris")
let search = next()
store.cancelSearch()
search.reply("{}")
RunLoop.main.run(until: Date().addingTimeInterval(0.05))
check(store.results.isEmpty && !store.searched && !store.searching, "Query edit invalidates pending search")
store.search("Unknown")
next().reply("{}")
wait { !store.searching }
check(store.searched && !store.searchFailed && store.results.isEmpty, "Empty search differs from failure")
store.search("Roma")
next().reply("{}", status: 429)
wait { !store.searching }
check(store.searchFailed, "Rate limit surfaced as search failure")
print("PASS: \(checks) weather checks")
