import SwiftUI

@main
struct NoctGalleryApp: App {
    @StateObject private var support = AppSupportStore.shared

    @StateObject private var model = GalleryViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
        }
    }
}
