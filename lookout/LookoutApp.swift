// xcode: set sdk=iOS

import SwiftUI

@main
struct LookoutApp: App {
    @State private var hasEntered = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                if hasEntered {
                    ContentView()
                        .transition(.opacity.combined(with: .scale(scale: 1.03)))
                } else {
                    StartupView {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            hasEntered = true
                        }
                    }
                    .transition(.opacity)
                }
            }
        }
    }
}
