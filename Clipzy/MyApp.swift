import SwiftUI

@main struct MyApp: App {
    init() { AppFonts.register() }

    var body: some Scene {
        WindowGroup {
            ClipzStudioRoot()
        }
    }
}
