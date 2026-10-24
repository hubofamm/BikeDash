import SwiftUI

@main
struct BikeDashApp: App {
    @StateObject private var link: BoardLink
    @StateObject private var nav: Navigator

    init() {
        let l = BoardLink()
        _link = StateObject(wrappedValue: l)
        _nav = StateObject(wrappedValue: Navigator(link: l))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(link)
                .environmentObject(nav)
        }
    }
}
