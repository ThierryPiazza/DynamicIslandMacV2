import AppKit
import CoreLocation
import Combine

final class WeatherMonitor: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var temperature: Int?
    @Published var feelsLike: Int?
    @Published var weatherCode: Int?
    @Published var cityName: String = ""
    @Published var isLoading = false
    @Published var locationDenied = false

    private let locationManager = CLLocationManager()
    private var refreshTimer: Timer?
    private var hasFetchedData = false

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func start() {
        let s = ModuleSettings.shared
        if s.weatherUseFixed && s.weatherFixedLat != 0 {
            startFixed(lat: s.weatherFixedLat, lon: s.weatherFixedLon, city: s.weatherFixedCity)
            return
        }
        startAuto()
    }

    /// Avvia con coordinate fisse (nessuna richiesta GPS).
    func startFixed(lat: Double, lon: Double, city: String) {
        refreshTimer?.invalidate()
        isLoading  = true
        cityName   = city
        locationDenied = false
        hasFetchedData = true
        fetchWeather(lat: lat, lon: lon)
    }

    /// Avvia con posizione automatica GPS.
    private func startAuto() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            NSApp.activate(ignoringOtherApps: true)
            locationManager.requestWhenInUseAuthorization()
        case .authorized, .authorizedAlways, .authorizedWhenInUse:
            locationDenied = false
            if !hasFetchedData {
                isLoading = true
                locationManager.requestLocation()
            }
        case .denied, .restricted:
            locationDenied = true
        @unknown default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch manager.authorizationStatus {
            case .authorized, .authorizedAlways, .authorizedWhenInUse:
                self.locationDenied = false
                self.isLoading = true
                manager.requestLocation()
            case .denied, .restricted:
                self.locationDenied = true
                self.isLoading = false
            default:
                break
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.first else { return }
        hasFetchedData = true
        fetchWeather(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude)
        reverseGeocode(loc)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in self?.isLoading = false }
    }

    private func fetchWeather(lat: Double, lon: Double) {
        let urlStr = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,apparent_temperature,weather_code&timezone=auto"
        guard let url = URL(string: urlStr) else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let current = json["current"] as? [String: Any]
            else {
                DispatchQueue.main.async { self?.isLoading = false }
                return
            }
            let temp  = current["temperature_2m"] as? Double ?? 0
            let feels = current["apparent_temperature"] as? Double ?? temp
            let code  = current["weather_code"] as? Int ?? 0
            DispatchQueue.main.async {
                self?.temperature = Int(temp.rounded())
                self?.feelsLike   = Int(feels.rounded())
                self?.weatherCode = code
                self?.isLoading   = false
                self?.scheduleRefresh(lat: lat, lon: lon)
            }
        }.resume()
    }

    private func scheduleRefresh(lat: Double, lon: Double) {
        refreshTimer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: 1800, repeats: false) { [weak self] _ in
            self?.fetchWeather(lat: lat, lon: lon)
        }
        t.tolerance = 180
        refreshTimer = t
    }

    private func reverseGeocode(_ location: CLLocation) {
        CLGeocoder().reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            let city = placemarks?.first?.locality ?? placemarks?.first?.administrativeArea ?? ""
            DispatchQueue.main.async { self?.cityName = city }
        }
    }

    // MARK: - Static helpers used by WeatherView

    static func icon(for code: Int) -> String {
        switch code {
        case 0, 1:   return "sun.max.fill"
        case 2:      return "cloud.sun.fill"
        case 3:      return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67: return "cloud.rain.fill"
        case 71...77: return "cloud.snow.fill"
        case 80...82: return "cloud.heavyrain.fill"
        case 85, 86:  return "cloud.snow.fill"
        case 95:      return "cloud.bolt.fill"
        case 96, 99:  return "cloud.bolt.rain.fill"
        default:      return "cloud.fill"
        }
    }

    static func description(for code: Int) -> String {
        switch code {
        case 0, 1:   return "Sereno"
        case 2:      return "Parzialmente nuvoloso"
        case 3:      return "Nuvoloso"
        case 45, 48: return "Nebbia"
        case 51...57: return "Pioggerellina"
        case 61...67: return "Pioggia"
        case 71...77: return "Neve"
        case 80...82: return "Rovesci"
        case 85, 86:  return "Neve a rovesci"
        case 95:      return "Temporale"
        case 96, 99:  return "Grandine"
        default:      return "Variabile"
        }
    }
}
