@preconcurrency import Photos
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: GalleryViewModel
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("onboarding.completed") private var completedOnboarding = false

    var body: some View {
        ZStack {
            NoctGalleryTheme.background(for: colorScheme)
                .ignoresSafeArea()

            if !completedOnboarding {
                OnboardingView {
                    completedOnboarding = true
                    Task { await model.requestAccess() }
                }
            } else if model.canReadLibrary {
                MainTabView()
            } else {
                PhotoPermissionView(status: model.authorizationStatus) {
                    Task { await model.requestAccess() }
                }
            }
        }
        .task { await model.start() }
        .sheet(item: $model.sharePayload, onDismiss: model.finishShare) { payload in
            ShareSheet(url: payload.url, completion: model.finishShare)
                .presentationDetents([.medium, .large])
        }
        .alert("Noct Gallery", isPresented: errorBinding) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "An unknown error occurred.")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }
}
private struct MainTabView: View {
    var body: some View {
        TabView {
            GalleryView()
                .tabItem { Label("Gallery", systemImage: "photo.stack") }
            SharePrivacyView()
                .tabItem { Label("Share", systemImage: "shield.lefthalf.filled") }
            GallerySettingsView()
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
        }
        .tint(NoctGalleryTheme.violet)
    }
}

private struct OnboardingView: View {
    let continueAction: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 44)
                NoctGalleryMark()
                    .scaleEffect(1.35)
                VStack(spacing: 10) {
                    Text("Noct Gallery")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("Your photos stay where they are.")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 14) {
                    OnboardingPoint(
                        icon: "photo.stack",
                        title: "No second library",
                        detail: "Noct Gallery reads the system photo library and keeps no private media copy."
                    )
                    OnboardingPoint(
                        icon: "wand.and.sparkles",
                        title: "Clean only when sharing",
                        detail: "The selected original is bounded, decoded, normalized, and re-encoded at share time."
                    )
                    OnboardingPoint(
                        icon: "theatermasks",
                        title: "Optional decoy metadata",
                        detail: "Generated metadata is explicit, temporary, and never written back to Photos."
                    )
                }

                Button(action: continueAction) {
                    Text("Continue to Photo Access")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(NoctGalleryTheme.violet)

                Text("PhotoKit requires read access to display the gallery. Noct Gallery does not modify or upload your originals.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct OnboardingPoint: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(NoctGalleryTheme.gradient)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct PhotoPermissionView: View {
    let status: PHAuthorizationStatus
    let request: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        ContentUnavailableView {
            Label("Photo Access Needed", systemImage: "photo.badge.exclamationmark")
        } description: {
            Text("Noct Gallery needs PhotoKit access to display your existing library. It does not create a second copy.")
        } actions: {
            if status == .notDetermined {
                Button("Allow Photo Access", action: request)
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}
