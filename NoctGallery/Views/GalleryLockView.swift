import NoctweaveSecurityKeys
import SwiftUI

struct GalleryLockView: View {
    @EnvironmentObject private var lock: GalleryLockController
    @EnvironmentObject private var model: GalleryViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var pin = ""
    @State private var keyPIN = ""
    @State private var transport = SecurityKeyTransport.nfc
    @State private var automaticBiometricAttempted = false
    @State private var showsReset = false
    @State private var resetText = ""
    @State private var normalUnlockRequested = false
    @State private var showsHiddenKey = false

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                NoctGalleryMark()
                    .contentShape(Rectangle())
                    .onLongPressGesture(minimumDuration: 2) {
                        guard lock.isDiscreet, !lock.isBusy else { return }
                        normalUnlockRequested = true
                        automaticBiometricAttempted = false
                        lock.message = nil
                        if lock.nextFactor == .securityKey { showsHiddenKey = true }
                        else { beginAutomaticBiometrics() }
                    }
                    .accessibilityHidden(true)
                    .padding(.top, 60)
                VStack(spacing: 8) {
                    Text("Noct Gallery").font(.largeTitle.bold())
                    Text(lock.pendingDuress == nil ? "Your private space, protected." : "Finishing setup…")
                        .foregroundStyle(.secondary)
                }
                if !lock.isLoaded || model.isResetting {
                    ProgressView().padding()
                } else if model.resetNeedsRetry {
                    Button("Finish Reset") { Task { await model.purgeAndReset() } }.buttonStyle(.borderedProminent)
                } else if lock.loadFailed {
                    Text("Protection settings are unavailable.").foregroundStyle(.secondary)
                    Button("Try Again") { Task { await lock.load() } }.buttonStyle(.borderedProminent)
                } else if let plan = lock.pendingDuress {
                    Button("Continue") { Task { await model.applyDuress(plan) } }.buttonStyle(.borderedProminent)
                } else {
                    if lock.nextFactor == .securityKey, !lock.isDiscreet {
                        VStack(spacing: 16) {
                            Label("Security Key", systemImage: "key.horizontal").font(.headline)
                            SecurityKeyConnectionLabel()
                            SecureField("Security key PIN", text: $keyPIN)
                                .textContentType(.none).textInputAutocapitalization(.never).autocorrectionDisabled()
                                .textFieldStyle(.roundedBorder)
                            Button("Verify Key") {
                                let entered = keyPIN
                                keyPIN = ""
                                Task { await lock.authenticateKey(pin: entered, transport: transport) }
                            }.buttonStyle(.borderedProminent).disabled(lock.isBusy)
                        }.padding(22).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24))
                    }
                    if lock.nextFactor == .biometrics, !lock.isDiscreet {
                        Button { Task { await lock.authenticateBiometrics() } } label: {
                            Label("Unlock with \(lock.biometricName)", systemImage: lock.biometricName == "Face ID" ? "faceid" : "touchid")
                                .frame(maxWidth: .infinity)
                        }.buttonStyle(.borderedProminent).controlSize(.large).disabled(lock.isBusy)
                    }
                    // A duress PIN can be entered before any ordinary factor. Once
                    // key verification starts, this initial field disappears until
                    // the final, real PIN step, following the Noctweave flow.
                    if lock.nextFactor == .pin || (lock.hasDuress && lock.completed.isEmpty && !lock.isBusy && !showsHiddenKey) {
                        VStack(spacing: 14) {
                            GalleryPINField(title: "PIN", text: $pin)
                                .accessibilityIdentifier("lock.pin")
                            Button("Unlock") {
                                let entered = pin
                                pin = ""
                                Task { await lock.submitPIN(entered) }
                            }.buttonStyle(.borderedProminent).controlSize(.large)
                                .disabled(!GalleryPINVerifier.isValid(pin) || lock.isBusy)
                                .accessibilityIdentifier("lock.unlock")
                        }.padding(22).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24))
                    }
                    if lock.isBusy { ProgressView().padding(8) }
                    if let message = lock.message {
                        Text(lock.isDiscreet ? "Unable to unlock. Try again." : message)
                            .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                }
                if lock.isLoaded, lock.pendingDuress == nil, !model.isResetting, !lock.isBusy {
                    Button("Reset App…") { resetText = ""; showsReset = true }
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 440).padding(24).frame(maxWidth: .infinity)
        }
        .onChange(of: lock.nextFactor, initial: true) { _, _ in beginAutomaticBiometrics() }
        .onChange(of: lock.isBusy) { _, busy in if !busy { beginAutomaticBiometrics() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { beginAutomaticBiometrics() }
            if phase == .background {
                pin = ""; keyPIN = ""; normalUnlockRequested = false
                automaticBiometricAttempted = false; showsHiddenKey = false
            }
        }
        .onChange(of: lock.completed) { _, factors in
            if factors.contains(.securityKey) { showsHiddenKey = false }
        }
        .sheet(isPresented: $showsHiddenKey, onDismiss: {
            lock.message = nil
            if lock.completed.contains(.securityKey) { beginAutomaticBiometrics() }
            else { normalUnlockRequested = false }
        }) { GalleryHiddenKeyPrompt() }
        .onDisappear { pin = ""; keyPIN = "" }
        .alert("Reset Noct Gallery?", isPresented: $showsReset) {
            TextField("Type RESET to confirm", text: $resetText).textInputAutocapitalization(.characters).autocorrectionDisabled()
            Button("Cancel", role: .cancel) {}
            Button("Purge and Reset", role: .destructive) { Task { await model.purgeAndReset() } }.disabled(resetText != "RESET")
        } message: {
            Text("Permanently delete all private media, encryption keys, protection settings and temporary files. This cannot be undone. Originals in Apple Photos stay unchanged.")
        }
    }
    private func beginAutomaticBiometrics() {
        guard scenePhase == .active, lock.nextFactor == .biometrics, !lock.isBusy,
              !automaticBiometricAttempted, !showsReset, !model.isResetting,
              !showsHiddenKey, (!lock.isDiscreet || normalUnlockRequested) else { return }
        automaticBiometricAttempted = true
        Task { await lock.authenticateBiometrics() }
    }
}

private struct GalleryHiddenKeyPrompt: View {
    @EnvironmentObject private var lock: GalleryLockController
    @Environment(\.dismiss) private var dismiss
    @State private var pin = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("Security key") {
                    SecurityKeyConnectionLabel()
                    SecureField("Security key PIN", text: $pin).textContentType(.none).autocorrectionDisabled()
                    Button("Verify Key") {
                        let entered = pin; pin = ""
                        Task { await lock.authenticateKey(pin: entered, transport: .nfc) }
                    }.disabled(lock.isBusy)
                    if lock.isBusy { ProgressView() }
                    if let message = lock.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                }
            }.navigationTitle("Unlock").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(lock.isBusy) } }
        }.presentationDetents([.medium, .large]).interactiveDismissDisabled(lock.isBusy)
    }
}

struct GalleryPINField: View {
    let title: String
    @Binding var text: String
    var body: some View {
        SecureField(title, text: $text)
            .keyboardType(.numberPad).textContentType(.none)
            .textFieldStyle(.roundedBorder)
            .onChange(of: text) { _, value in text = String(value.filter { $0.isASCII && $0.isNumber }.prefix(6)) }
    }
}

struct SecurityKeyConnectionLabel: View {
    var body: some View {
        Label("NFC · scan near the top of your iPhone", systemImage: "wave.3.right")
            .font(.subheadline).foregroundStyle(.secondary)
    }
}

struct GalleryProtectionView: View {
    @EnvironmentObject private var lock: GalleryLockController
    @Environment(\.dismiss) private var dismiss
    var onboarding = false
    @State private var mode = GalleryLockMode.pin
    @State private var pin = ""
    @State private var confirmation = ""
    @State private var keyPIN = ""
    @State private var keyName = "Security Key"
    @State private var transport = SecurityKeyTransport.nfc
    @State private var loaded = false
    @State private var discreet = false

    var body: some View {
        Form {
            if onboarding {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Protect your private space", systemImage: "lock.shield").font(.title2.bold())
                        Text("Choose how you unlock Noct Gallery before adding photos or videos.").foregroundStyle(.secondary)
                    }.padding(.vertical, 12)
                }
            }
            Section {
                Picker("Unlock with", selection: $mode) {
                    ForEach(GalleryLockMode.allCases) { candidate in
                        Text(candidate.title).tag(candidate)
                            .disabled(candidate.factors.contains(.securityKey) && !lock.securityKeysAvailable)
                    }
                }
                if mode != .off {
                    Text("Every selected method is required. Gallery locks when it enters the background; you can also lock it manually.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("Anyone using your unlocked device can open Gallery. Private media still uses encrypted storage.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } header: { Text("App protection") }
            if mode.factors.contains(.pin) {
                Section("Six-digit PIN") {
                    GalleryPINField(title: lock.configuration?.pin == nil ? "New PIN" : "New PIN (leave blank to keep)", text: $pin)
                        .accessibilityIdentifier("protection.newPIN")
                    GalleryPINField(title: "Confirm PIN", text: $confirmation)
                        .accessibilityIdentifier("protection.confirmPIN")
                    Text("This is your Gallery PIN, separate from your device passcode.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            if mode.factors.contains(.biometrics) {
                Section(lock.biometricName) {
                    Text(lock.biometricsAvailable
                         ? "You’ll verify \(lock.biometricName) when saving. The device passcode cannot replace this required check."
                         : "Set up biometrics in iOS Settings before selecting this method.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if mode.factors.contains(.securityKey) {
                Section("Hardware security key") {
                    SecurityKeyConnectionLabel()
                    TextField("Key name", text: $keyName).autocorrectionDisabled()
                    SecureField("Security key’s FIDO2 PIN", text: $keyPIN).textContentType(.none).autocorrectionDisabled()
                    if !(lock.configuration?.keys.isEmpty ?? true) {
                        Button("Verify Registered Key") { verify(register: false) }
                        ForEach(lock.configuration?.keys ?? []) { key in
                            Label(key.name, systemImage: "key.horizontal").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Button("Register Another Key") { verify(register: true) }
                        .disabled((lock.configuration?.keys.count ?? 0) >= 8)
                    if let key = lock.verifiedKey { Label("Verified: \(key.name)", systemImage: "checkmark.seal.fill").foregroundStyle(.green) }
                    Text("Use a FIDO2 NFC key with user verification on a compatible iPhone. Each unlock needs a scan. USB and continuous key-presence locking are unavailable on this platform.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.disabled(lock.isBusy || !lock.securityKeysAvailable)
            }
            if !onboarding, lock.mode != .off {
                Section {
                    NavigationLink { GalleryDuressSettingsView() } label: {
                        Label("Duress PINs & Decoy Media", systemImage: "theatermasks")
                    }
                }
                Section("Discreet lock screen") {
                    Toggle("Show only the PIN screen", isOn: $discreet)
                        .disabled(!lock.hasDuress || mode == .off)
                        .accessibilityIdentifier("protection.discreet")
                    Text(lock.hasDuress
                         ? "The lock screen shows no biometric or key controls and does not start biometrics automatically. Press and hold the Gallery logo for two seconds to start your normal unlock checks. Your duress PIN works directly in the visible PIN field."
                         : "Set a duress PIN first. It gives the visible PIN screen a usable unlock action when your ordinary method is biometrics or a key.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section {
                if let message = lock.message { Text(message).font(.callout).foregroundStyle(.red) }
                Button {
                    let entered = pin
                    Task {
                        if await lock.configure(mode: mode, pin: entered, discreet: discreet && lock.hasDuress && mode != .off) {
                            pin = ""; confirmation = ""; keyPIN = ""
                            if !onboarding { dismiss() }
                        }
                    }
                } label: {
                    HStack { Text("Save Protection"); Spacer(); if lock.isBusy { ProgressView() } }
                }.disabled(!canSave).accessibilityIdentifier("protection.save")
            }
        }
        .navigationTitle(onboarding ? "Welcome" : "App Protection")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !onboarding { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.disabled(lock.isBusy) } }
        }
        .interactiveDismissDisabled(lock.isBusy)
        .onAppear { if !loaded { mode = lock.configuration?.mode ?? .pin; discreet = lock.isDiscreet; loaded = true; lock.message = nil } }
        .onDisappear { pin = ""; confirmation = ""; keyPIN = "" }
    }
    private var canSave: Bool {
        !lock.isBusy && (!mode.factors.contains(.pin) || (pin.isEmpty && confirmation.isEmpty && lock.configuration?.pin != nil)
            || (GalleryPINVerifier.isValid(pin) && pin == confirmation))
        && (!mode.factors.contains(.biometrics) || lock.biometricsAvailable)
        && (!mode.factors.contains(.securityKey) || (lock.securityKeysAvailable && lock.verifiedKey != nil))
    }
    private func verify(register: Bool) {
        let entered = keyPIN
        keyPIN = ""
        Task { await lock.verifyKeyForSetup(name: keyName, pin: entered, transport: transport, register: register) }
    }
}
