#if os(iOS)
import SwiftUI

/// A SwiftUI view that scans a payment card.
///
/// ```swift
/// .fullScreenCover(isPresented: $isScanning) {
///     CardScannerView { card in
///         number = card.formattedNumber
///         isScanning = false
///     } onCancel: {
///         isScanning = false
///     }
/// }
/// ```
///
/// For the common case of presenting from a toggle, use the `cardScanner(isPresented:configuration:onScan:onError:)`
/// view modifier instead.
public struct CardScannerView: UIViewControllerRepresentable {
    public var configuration: ScannerConfiguration
    public var onScan: (ScannedCard) -> Void
    public var onCancel: () -> Void
    public var onError: (CardScannerError) -> Void

    public init(
        configuration: ScannerConfiguration = ScannerConfiguration(),
        onScan: @escaping (ScannedCard) -> Void,
        onCancel: @escaping () -> Void = {},
        onError: @escaping (CardScannerError) -> Void = { _ in }
    ) {
        self.configuration = configuration
        self.onScan = onScan
        self.onCancel = onCancel
        self.onError = onError
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(view: self)
    }

    public func makeUIViewController(context: Context) -> CardScannerViewController {
        let controller = CardScannerViewController(configuration: configuration)
        controller.delegate = context.coordinator
        return controller
    }

    public func updateUIViewController(_ uiViewController: CardScannerViewController, context: Context) {
        context.coordinator.view = self
    }

    @MainActor
    public final class Coordinator: CardScannerDelegate {
        var view: CardScannerView

        init(view: CardScannerView) {
            self.view = view
        }

        public func cardScanner(_ scanner: CardScannerViewController, didScan card: ScannedCard) {
            view.onScan(card)
        }

        public func cardScannerDidCancel(_ scanner: CardScannerViewController) {
            view.onCancel()
        }

        public func cardScanner(_ scanner: CardScannerViewController, didFailWith error: CardScannerError) {
            view.onError(error)
        }
    }
}

public extension View {
    /// Presents the card scanner full screen while `isPresented` is `true`.
    ///
    /// The binding is set back to `false` on scan, cancel or error, after the matching closure runs.
    ///
    /// ```swift
    /// Button("Scan card") { isScanning = true }
    ///     .cardScanner(isPresented: $isScanning) { card in
    ///         number = card.formattedNumber
    ///     }
    /// ```
    func cardScanner(
        isPresented: Binding<Bool>,
        configuration: ScannerConfiguration = ScannerConfiguration(),
        onScan: @escaping (ScannedCard) -> Void,
        onError: @escaping (CardScannerError) -> Void = { _ in }
    ) -> some View {
        fullScreenCover(isPresented: isPresented) {
            CardScannerView(
                configuration: configuration,
                onScan: { card in
                    onScan(card)
                    isPresented.wrappedValue = false
                },
                onCancel: {
                    isPresented.wrappedValue = false
                },
                onError: { error in
                    onError(error)
                    isPresented.wrappedValue = false
                }
            )
            .ignoresSafeArea()
        }
    }
}
#endif
