import Foundation
import MapKit
import CoreLocation

/// Plans a route with Apple Maps, follows your GPS and sends the next turn to the board.
final class Navigator: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var results: [MKMapItem] = []
    @Published var destination: MKMapItem?
    @Published var navigating = false
    @Published var instruction = ""
    @Published var distanceText = ""
    @Published var etaText = ""
    @Published var remainingText = ""
    @Published var message = ""

    let link: BoardLink
    private let lm = CLLocationManager()
    private var route: MKRoute?
    private var stepIndex = 0
    private var lastLocation: CLLocation?
    private var offRouteCount = 0
    private var lastReroute = Date.distantPast
    private var lastSend = Date.distantPast
    private var lastSentStep = -1
    private var arrivedAt: Date?

    init(link: BoardLink) {
        self.link = link
        super.init()
        lm.delegate = self
        lm.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        lm.activityType = .automotiveNavigation
        lm.distanceFilter = 5
        lm.requestWhenInUseAuthorization()
    }

    // MARK: Search

    func search(_ text: String) {
        let q = text.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = q
        if let loc = lastLocation {
            req.region = MKCoordinateRegion(center: loc.coordinate,
                                            latitudinalMeters: 50_000, longitudinalMeters: 50_000)
        }
        message = "Searching..."
        MKLocalSearch(request: req).start { [weak self] resp, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.results = resp?.mapItems ?? []
                self.message = self.results.isEmpty ? "No places found" : ""
            }
        }
    }

    // MARK: Start / stop

    func start(to item: MKMapItem) {
        destination = item
        navigating = true
        results = []
        arrivedAt = nil
        lastSentStep = -1
        lm.allowsBackgroundLocationUpdates = true
        lm.showsBackgroundLocationIndicator = true
        lm.pausesLocationUpdatesAutomatically = false
        lm.startUpdatingLocation()
        calculateRoute(from: nil)
    }

    func stop() {
        navigating = false
        route = nil
        destination = nil
        instruction = ""; distanceText = ""; etaText = ""; remainingText = ""
        message = ""
        lm.stopUpdatingLocation()
        lm.allowsBackgroundLocationUpdates = false
        link.send("X")
    }

    func sendTest() {
        link.send("2|250|Turn right onto Test Road|Test Road|10:58|12400|16")
        message = "Test sent - the board should show a right turn"
    }

    private func calculateRoute(from loc: CLLocation?) {
        guard let dest = destination else { return }
        lastReroute = Date()
        let req = MKDirections.Request()
        if let loc = loc {
            req.source = MKMapItem(placemark: MKPlacemark(coordinate: loc.coordinate))
        } else {
            req.source = MKMapItem.forCurrentLocation()
        }
        req.destination = dest
        req.transportType = .automobile
        message = loc == nil ? "Calculating route..." : "Rerouting..."
        MKDirections(request: req).calculate { [weak self] resp, err in
            DispatchQueue.main.async {
                guard let self = self, self.navigating else { return }
                guard let r = resp?.routes.first else {
                    self.message = "No route: \(err?.localizedDescription ?? "unknown error")"
                    return
                }
                self.route = r
                self.stepIndex = 0
                self.offRouteCount = 0
                self.lastSentStep = -1
                self.message = ""
                if let l = self.lastLocation { self.update(with: l) }
            }
        }
    }

    // MARK: Location

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        switch m.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: m.requestLocation()
        case .denied, .restricted: message = "Allow location for Bike Dash in iPhone Settings"
        default: break
        }
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        guard let l = locs.last, l.horizontalAccuracy >= 0 else { return }
        lastLocation = l
        if navigating { update(with: l) }
    }

    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) { }

    // MARK: Route following

    /// Distance from a point to a step's line, and how much of the step is left after that point.
    private func closest(_ c: CLLocationCoordinate2D, _ step: MKRoute.Step) -> (dist: Double, remaining: Double) {
        let n = step.polyline.pointCount
        let pts = step.polyline.points()
        let me = MKMapPoint(c)
        if n == 0 { return (.greatestFiniteMagnitude, 0) }
        if n == 1 { return (me.distance(to: pts[0]), 0) }

        var best = Double.greatestFiniteMagnitude
        var bestSeg = 0
        var bestProj = pts[0]
        for i in 0..<(n - 1) {
            let a = pts[i], b = pts[i + 1]
            let dx = b.x - a.x, dy = b.y - a.y
            let len2 = dx * dx + dy * dy
            var t = len2 > 0 ? ((me.x - a.x) * dx + (me.y - a.y) * dy) / len2 : 0
            t = max(0, min(1, t))
            let proj = MKMapPoint(x: a.x + t * dx, y: a.y + t * dy)
            let d = me.distance(to: proj)
            if d < best { best = d; bestSeg = i; bestProj = proj }
        }
        var remaining = bestProj.distance(to: pts[bestSeg + 1])
        if bestSeg + 2 < n {
            for i in (bestSeg + 1)..<(n - 1) { remaining += pts[i].distance(to: pts[i + 1]) }
        }
        return (best, remaining)
    }

    private func update(with l: CLLocation) {
        guard let r = route, !r.steps.isEmpty else { return }
        let steps = r.steps
        let here = l.coordinate

        // Which step are we on? Look a few steps ahead and pick the closest line.
        var bestIdx = stepIndex
        var bestDist = Double.greatestFiniteMagnitude
        var bestRemain = 0.0
        let upper = min(steps.count, stepIndex + 4)
        for i in stepIndex..<upper {
            let c = closest(here, steps[i])
            if c.dist < bestDist - 1 {
                bestDist = c.dist; bestIdx = i; bestRemain = c.remaining
            }
        }
        stepIndex = bestIdx

        // Off route -> recalculate (at most every 15 s)
        if bestDist > 50 {
            offRouteCount += 1
            if offRouteCount >= 3 && Date().timeIntervalSince(lastReroute) > 15 {
                calculateRoute(from: l)
            }
        } else {
            offRouteCount = 0
        }

        // Next maneuver
        let isLast = stepIndex >= steps.count - 1
        let nextText: String
        if isLast {
            nextText = "Arrive at \(destination?.name ?? "destination")"
        } else {
            let t = steps[stepIndex + 1].instructions
            nextText = t.isEmpty ? "Continue" : t
        }
        let code = isLast ? 9 : Navigator.code(for: nextText)
        let toTurn = max(0, bestRemain)

        var remaining = toTurn
        if !isLast {
            for i in (stepIndex + 1)..<steps.count { remaining += steps[i].distance }
        }
        let secondsLeft = r.distance > 0 ? r.expectedTravelTime * remaining / r.distance : 0
        let eta = Date().addingTimeInterval(secondsLeft)
        let etaString = Navigator.timeFormatter.string(from: eta)
        let minutesLeft = Int((secondsLeft / 60).rounded())

        // Arrived?
        if isLast && toTurn < 30 {
            if arrivedAt == nil { arrivedAt = Date() }
        }

        // Update the app screen
        instruction = nextText
        distanceText = Navigator.distanceString(toTurn)
        etaText = etaString
        remainingText = "\(Navigator.distanceString(remaining)) left, \(minutesLeft) min"

        // Send to the board: always on a new step, otherwise once per second
        if stepIndex != lastSentStep || Date().timeIntervalSince(lastSend) >= 1 {
            lastSend = Date()
            lastSentStep = stepIndex
            let packet = [
                String(code),
                String(Int(toTurn)),
                Navigator.clean(nextText, 80),
                Navigator.clean(Navigator.street(from: nextText), 40),
                etaString,
                String(Int(remaining)),
                String(minutesLeft)
            ].joined(separator: "|")
            link.send(packet)
        }

        // Stop automatically 20 s after arriving
        if let a = arrivedAt, Date().timeIntervalSince(a) > 20 { stop() }
    }

    // MARK: Text helpers

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    static func distanceString(_ m: Double) -> String {
        if m >= 1000 { return String(format: m >= 10_000 ? "%.0f km" : "%.1f km", m / 1000) }
        let r = m < 100 ? Int(m / 5) * 5 : Int(m / 10) * 10
        return "\(r) m"
    }

    static func clean(_ s: String, _ maxLen: Int) -> String {
        let noPipes = s.replacingOccurrences(of: "|", with: "/")
        return String(noPipes.prefix(maxLen))
    }

    /// Board arrow code from Apple's instruction text (English)
    static func code(for s: String) -> Int {
        let t = s.lowercased()
        if t.contains("arrive") || t.contains("destination") { return 9 }
        if t.contains("u-turn") || t.contains("u turn") { return 7 }
        if t.contains("roundabout") || t.contains("traffic circle") || t.contains("rotary") { return 8 }
        if t.contains("sharp left") { return 5 }
        if t.contains("sharp right") { return 6 }
        if t.contains("slight left") || t.contains("keep left") || t.contains("bear left") { return 3 }
        if t.contains("slight right") || t.contains("keep right") || t.contains("bear right") { return 4 }
        if t.contains("left") { return 1 }
        if t.contains("right") { return 2 }
        return 0
    }

    static func street(from s: String) -> String {
        for key in [" onto ", " on to ", " on ", " toward ", " towards "] {
            if let r = s.range(of: key, options: .caseInsensitive) {
                return String(s[r.upperBound...])
            }
        }
        return ""
    }
}
