import SwiftUI

@main
struct NoctGalleryApp: App {
    @StateObject private var support = AppSupportStore.shared

    @StateObject private var model = GalleryViewModel(inbox: try? GalleryImportInbox.appInbox())

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(model.lock)
        }
    }
}
