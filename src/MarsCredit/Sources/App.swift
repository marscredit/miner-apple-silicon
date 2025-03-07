import SwiftUI
import CoreText

@main
struct MarsCreditApp: App {
    private let miningService = MiningService()
    
    init() {
        // Register custom font
        if let fontURL = Bundle.module.url(forResource: "gunshipboldital", withExtension: "otf") {
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &error) {
                print("Failed to register font: \(error.debugDescription)")
            }
        } else {
            print("Failed to find font file in bundle")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView(miningService: miningService)
                .frame(width: 800, height: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
} 