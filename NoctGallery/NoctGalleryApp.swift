import SwiftUI

@main
struct NoctGalleryApp: App {
    @StateObject private var model = GalleryViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
        }
    }
}
