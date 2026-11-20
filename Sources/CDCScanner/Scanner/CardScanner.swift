#if os(iOS)
import UIKit

/// A one-call, `async` way to scan a card from UIKit.
///
/// ```swift
/// do {
///     let card = try await CardScanner.scan(from: self)
///     print(card.formattedNumber, card.brand, card.expiry ?? "no expiry")
/// } catch is CancellationError {
///     // The user tapped Cancel.
/// } catch let error as CardScannerError {
///     // Camera denied, unsupported device, and so on.
/// }
/// ```
@MainActor
public enum CardScanner {
    /// Whether this device can run the live scanner at all. See ``CardScannerViewController/isSupported``.
    public static var isSupported: Bool {
        CardScannerViewController.isSupported
    }

    /// Presents a ``CardScannerViewController`` full screen and waits for a result.
    ///
    /// The controller is dismissed before this function returns or throws.
    ///
    /// - Parameters:
    ///   - presenter: The view controller to present from.
    ///   - configuration: Scan options.
    ///   - animated: Whether to animate presentation and dismissal.
    /// - Returns: The scanned card.
    /// - Throws: `CancellationError` when the user cancels or the calling task is cancelled, or
    ///   a ``CardScannerError`` when scanning cannot run.
    public static func scan(
        from presenter: UIViewController,
        configuration: ScannerConfiguration = ScannerConfiguration(),
        animated: Bool = true
    ) async throws -> ScannedCard {
        let controller = CardScannerViewController(configuration: configuration)
        let coordinator = PresentationCoordinator(controller: controller, animated: animated)
        controller.delegate = coordinator

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                coordinator.continuation = continuation
                presenter.present(controller, animated: animated)
            }
        } onCancel: {
            Task { @MainActor in coordinator.cancel() }
        }
    }
}

@MainActor
private final class PresentationCoordinator: CardScannerDelegate {
    var continuation: CheckedContinuation<ScannedCard, Error>?
    private let controller: CardScannerViewController
    private let animated: Bool

    init(controller: CardScannerViewController, animated: Bool) {
        self.controller = controller
        self.animated = animated
    }

    func cardScanner(_ scanner: CardScannerViewController, didScan card: ScannedCard) {
        resume(with: .success(card))
    }

    func cardScannerDidCancel(_ scanner: CardScannerViewController) {
        resume(with: .failure(CancellationError()))
    }

    func cardScanner(_ scanner: CardScannerViewController, didFailWith error: CardScannerError) {
        resume(with: .failure(error))
    }

    func cancel() {
        resume(with: .failure(CancellationError()))
    }

    private func resume(with result: Result<ScannedCard, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        let finish = { continuation.resume(with: result) }
        if controller.presentingViewController != nil {
            controller.dismiss(animated: animated, completion: finish)
        } else {
            finish()
        }
    }
}
#endif
