import UIKit
import UniformTypeIdentifiers

final class ImportCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
}

@MainActor
final class ImportViewController: UIViewController {
    private let status = UILabel()
    private let save = UIButton(type: .system)
    private let cancellation = ImportCancellation()
    private var saving: Task<Void, Never>?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let title = UILabel(); title.text = "Save to NoctGallery"; title.font = .preferredFont(forTextStyle: .title2); title.textAlignment = .center
        status.text = "Files are encrypted here. Open and unlock Gallery to import them into your private library."
        status.font = .preferredFont(forTextStyle: .body); status.numberOfLines = 0; status.textAlignment = .center
        save.setTitle("Save Encrypted Files", for: .normal); save.addTarget(self, action: #selector(beginSave), for: .touchUpInside)
        let cancel = UIButton(type: .system); cancel.setTitle("Cancel", for: .normal); cancel.addTarget(self, action: #selector(cancelSave), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [title, status, save, cancel]); stack.axis = .vertical; stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -28),
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            stack.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 24)])
        preferredContentSize = CGSize(width: 420, height: 380)
    }

    @objc private func beginSave() {
        guard saving == nil else { return }
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        guard !providers.isEmpty, providers.count <= 20 else { status.text = "Choose up to 20 supported photos or videos."; return }
        save.isEnabled = false
        saving = Task {
            var completed = 0
            do {
                let inbox = try GalleryImportInbox.appInbox()
                for provider in providers {
                    try Task.checkCancellation()
                    status.text = "Encrypting \(completed + 1) of \(providers.count)…"
                    let type = try Self.supportedType(provider)
                    let token = cancellation
                    let _: URL = try await withCheckedThrowingContinuation { continuation in
                        provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                            do {
                                if let error { throw error }
                                guard let url, !token.isCancelled else { throw CancellationError() }
                                let result = try inbox.enqueue(source: url, typeIdentifier: type, cancelled: { token.isCancelled })
                                continuation.resume(returning: result)
                            } catch { continuation.resume(throwing: error) }
                        }
                    }
                    completed += 1
                }
                status.text = "Saved \(completed) encrypted files. Open Gallery to import them."
                extensionContext?.completeRequest(returningItems: nil)
            } catch {
                status.text = (completed > 0 ? "\(completed) files saved. " : "") + error.localizedDescription
                save.isEnabled = true; saving = nil
            }
        }
    }

    private static func supportedType(_ provider: NSItemProvider) throws -> String {
        guard let identifier = provider.registeredTypeIdentifiers.first(where: { id in
            guard let type = UTType(id) else { return false }
            return type.conforms(to: .image) || type.conforms(to: .movie)
        }) else { throw GalleryImportInbox.InboxError.invalid }
        return identifier
    }

    @objc private func cancelSave() {
        cancellation.cancel(); saving?.cancel()
        extensionContext?.cancelRequest(withError: CancellationError())
    }
}
