#if os(iOS)
import Foundation

/// Receives the outcome of a ``CardScannerViewController`` session.
///
/// All methods are called on the main actor. The scanner does not dismiss itself; the delegate
/// decides what happens next, exactly as with `UIImagePickerController`.
@MainActor
public protocol CardScannerDelegate: AnyObject {
    /// A card was read and confirmed.
    func cardScanner(_ scanner: CardScannerViewController, didScan card: ScannedCard)

    /// The user tapped Cancel.
    func cardScannerDidCancel(_ scanner: CardScannerViewController)

    /// Scanning could not start or stopped unexpectedly.
    func cardScanner(_ scanner: CardScannerViewController, didFailWith error: CardScannerError)
}

public extension CardScannerDelegate {
    func cardScannerDidCancel(_ scanner: CardScannerViewController) {}
    func cardScanner(_ scanner: CardScannerViewController, didFailWith error: CardScannerError) {}
}
#endif
