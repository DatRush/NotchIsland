import SwiftUI

struct WeatherHeader: View {
    @ObservedObject var weather = WeatherStore.shared
    var body: some View {
        if let city = weather.city {
            HStack(spacing: 5) {
                Image(systemName: weather.reading?.symbol ?? "cloud")
                Text(weather.reading?.temperatureText ?? "—")
                    .monospacedDigit()
                if weather.failed || weather.reading?.isStale(at: weather.now) == true {
                    Image(systemName: "exclamationmark.circle").font(.system(size: 9))
                }
            }
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1).minimumScaleFactor(0.8)
            .foregroundColor(.white.opacity(0.85))
            .help(details(city))
            .accessibilityElement(children: .ignore).accessibilityLabel(details(city))
            .onAppear { weather.refresh() }
        }
    }
    private func details(_ city: WeatherCity) -> String {
        var text = city.label
        if let reading = weather.reading {
            let formatter = DateFormatter()
            formatter.locale = AppLanguage.locale
            formatter.dateStyle = .short; formatter.timeStyle = .short
            text += "\n" + reading.temperatureText + "C · " + L("Данные на ", "Data for ") + formatter.string(from: reading.date)
            if reading.isStale(at: weather.now) { text += "\n" + L("Данные устарели", "Weather data is outdated") }
        } else { text += "\n" + L("Погода пока недоступна", "Weather is not available yet") }
        if weather.failed { text += "\n" + L("Не удалось обновить погоду", "Could not update weather") }
        return text + "\n" + L("Данные погоды: Open-Meteo.com (CC BY 4.0)", "Weather data by Open-Meteo.com (CC BY 4.0)")
    }
}

struct WeatherSettings: View {
    @ObservedObject var weather = WeatherStore.shared
    @State private var query = ""
    var body: some View {
        Section(L("Погода", "Weather")) {
            if let city = weather.city {
                HStack {
                    Text(city.label).lineLimit(2)
                    Spacer()
                    Button(L("Выключить", "Turn off")) { weather.select(nil) }
                }
            }
            HStack {
                TextField(L("Город", "City"), text: $query)
                    .onSubmit { weather.search(query) }
                    .onChange(of: query) { _ in weather.cancelSearch() }
                Button(L("Найти", "Search")) { weather.search(query) }
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 || weather.searching)
            }
            if weather.searching { Text(L("Поиск…", "Searching…")).font(.caption) }
            if weather.searchFailed { Text(L("Не удалось найти города. Повторите поиск.", "Could not search for cities. Try again.")).font(.caption) }
            else if weather.searched && weather.results.isEmpty { Text(L("Города не найдены", "No cities found")).font(.caption) }
            ForEach(weather.results) { city in
                Button(city.label) { weather.select(city); query = "" }.lineLimit(2)
            }
            Text(L("Выберите город, чтобы показывать погоду слева от камеры. Обновление — каждые 15 минут, пока приложение работает. Геолокация не используется. Open-Meteo получает поисковый запрос, координаты выбранного города и IP-адрес. Выключение удаляет сохранённый город и погоду.", "Choose a city to show weather to the left of the camera. Updates every 15 minutes while the app is running. Device location is not used. Open-Meteo receives your search query, selected city's coordinates and IP address. Turning weather off removes the saved city and weather."))
                .font(.caption).foregroundColor(.secondary)
            HStack {
                Link(L("Погода: Open-Meteo", "Weather: Open-Meteo"), destination: URL(string: "https://open-meteo.com/")!)
                Link("CC BY 4.0", destination: URL(string: "https://creativecommons.org/licenses/by/4.0/")!)
                Link(L("Города: GeoNames", "Cities: GeoNames"), destination: URL(string: "https://www.geonames.org/")!)
            }.font(.caption)
        }.onDisappear { weather.cancelSearch() }
    }
}
