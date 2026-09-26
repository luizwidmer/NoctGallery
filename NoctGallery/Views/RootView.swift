@preconcurrency import Photos
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: GalleryViewModel
    @EnvironmentObject private var lock: GalleryLockController
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsProtectedSettingsResetConfirmation = false

    var body: some View {
        ZStack {
            NoctGalleryTheme.background(for: colorScheme)
                .ignoresSafeArea()

            if let settingsError = model.settingsLoadError {
                VStack(spacing: 18) {
                    NoctGalleryMark()
                    Text("Protected settings unavailable").font(.title2.bold())
                    Text(settingsError).multilineTextAlignment(.center).foregroundStyle(.secondary)
                    Button("Retry") { model.retrySettingsLoad() }.buttonStyle(.borderedProminent)
                    Button("Purge and Reset App", role: .destructive) {
                        showsProtectedSettingsResetConfirmation = true
                    }
                }
                .padding(28)
            } else if !lock.isLoaded || lock.loadFailed || lock.pendingDuress != nil || model.isResetting || model.resetNeedsRetry {
                GalleryLockView()
            } else if lock.configuration == nil {
                NavigationStack { GalleryProtectionView(onboarding: true) }
            } else if !lock.isUnlocked {
                GalleryLockView()
            } else if !model.onboardingCompleted {
                OnboardingView {
                    model.onboardingCompleted = true
                }
            } else {
                MainTabView()
            }
            if scenePhase != .active {
                NoctGalleryTheme.background(for: colorScheme).ignoresSafeArea()
                NoctGalleryMark()
            }
        }
        .id(model.resetGeneration)
        .task(id: model.resetGeneration) {
            await model.start()
            if lock.isUnlocked { _ = await model.unlockPrivate() }
        }
        .task(id: lock.pendingDuress?.id) {
            if let plan = lock.pendingDuress { await model.applyDuress(plan) }
        }
        .onChange(of: lock.isUnlocked) { _, unlocked in
            Task { if unlocked { _ = await model.unlockPrivate() } else { await model.lockPrivate(lockApp: false) } }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { lock.lock(); Task { await model.lockPrivate(lockApp: false) } }
            if phase == .active { lock.activate() }
        }
        .sheet(isPresented: $lock.showsProtectionSettings) {
            NavigationStack { GalleryProtectionView() }
        }
        .sheet(item: $model.sharePayload, onDismiss: model.finishShare) { payload in
            ShareSheet(url: payload.url, completion: model.finishShare)
                .presentationDetents([.medium, .large])
        }
        .alert("Noct Gallery", isPresented: errorBinding) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "An unknown error occurred.")
        }
        .confirmationDialog("Permanently remove all Gallery data?",
                            isPresented: $showsProtectedSettingsResetConfirmation) {
            Button("Purge and Reset App", role: .destructive) {
                Task { await model.purgeAndReset() }
            }
        } message: {
            Text("Private media, protection settings, and Gallery preferences will be removed from this device.")
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
    @EnvironmentObject private var model: GalleryViewModel
    @State private var selection = 1
    var body: some View {
        TabView(selection: $selection) {
            Group {
                if model.canReadLibrary {
                    GalleryView()
                } else {
                    PhotoPermissionView(status: model.authorizationStatus) {
                        Task { await model.requestAccess() }
                    }
                }
            }
                .tabItem { Label("Photos", systemImage: "photo.stack") }.tag(0)
            PrivateGalleryView()
                .tabItem { Label("Private", systemImage: "lock.rectangle.stack") }.tag(1)
            GallerySettingsView()
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }.tag(2)
        }
        .tint(NoctGalleryTheme.accent)
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
                    Text("A private space. A cleaner share.")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 14) {
                    OnboardingPoint(
                        icon: "photo.stack",
                        title: "Your private gallery",
                        detail: "Keep photos and videos encrypted on your device."
                    )
                    OnboardingPoint(
                        icon: "wand.and.sparkles",
                        title: "Private camera",
                        detail: "Capture directly into Gallery, without saving to Photos."
                    )
                    OnboardingPoint(
                        icon: "theatermasks",
                        title: "Optional decoy metadata",
                        detail: "Choose camera details, dates and places for copies you share."
                    )
                }

                Button(action: continueAction) {
                    Text("Get Started")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(NoctGalleryTheme.accent)

                Text("Photos access is optional. Camera permissions are requested when needed.")
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
            Text("Allow access to browse Photos. The private gallery and camera work without it.")
        } actions: {
            if status == .notDetermined || status == .authorized || status == .limited {
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
