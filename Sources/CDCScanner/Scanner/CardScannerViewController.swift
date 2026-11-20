#if os(iOS)
import AVFoundation
import UIKit
import VisionKit

/// A full-screen camera view that reads a payment card's number, brand and expiry.
///
/// Recognition is done by VisionKit's `DataScannerViewController`, so everything stays on
/// device and nothing is uploaded. Present the controller, set a ``delegate`` and dismiss it when
/// the delegate is called:
///
/// ```swift
/// let scanner = CardScannerViewController()
/// scanner.delegate = self
/// present(scanner, animated: true)
/// ```
///
/// Prefer ``CardScanner/scan(from:configuration:animated:)`` for an `async` API or
/// ``CardScannerView`` from SwiftUI.
///
/// > Important: Add `NSCameraUsageDescription` to your app's Info.plist. Check
/// > ``isSupported`` before presenting; the simulator and devices older than the A12 chip are not
/// > supported by VisionKit's live scanner.
@MainActor
public final class CardScannerViewController: UIViewController {
    /// The options this controller was created with.
    public let configuration: ScannerConfiguration

    /// Receives the result. Held weakly.
    public weak var delegate: CardScannerDelegate?

    /// Whether this device can run the live scanner at all.
    public static var isSupported: Bool {
        DataScannerViewController.isSupported
    }

    /// Whether the scanner can start right now, which also requires camera permission.
    public static var isAvailable: Bool {
        DataScannerViewController.isAvailable
    }

    private var session: ScanSession
    private var dataScanner: DataScannerViewController?
    private let overlay: CardGuideOverlayView
    private var hasFinished = false
    private var startTask: Task<Void, Never>?
    private var expiryTimer: Timer?
    private var isTorchOn = false

    public init(configuration: ScannerConfiguration = ScannerConfiguration()) {
        self.configuration = configuration
        self.session = ScanSession(configuration: configuration)
        self.overlay = CardGuideOverlayView(configuration: configuration)
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("CardScannerViewController does not support storyboards.")
    }

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        overlay.frame = view.bounds
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.onCancel = { [weak self] in self?.cancel() }
        overlay.onToggleTorch = { [weak self] in self?.toggleTorch() }
        overlay.setTorchButtonHidden(!configuration.showsTorchButton || !Self.deviceHasTorch)
        view.addSubview(overlay)
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startIfNeeded()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stop()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateRegionOfInterest()
    }

    public override var prefersStatusBarHidden: Bool { true }
    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        traitCollection.userInterfaceIdiom == .pad ? .all : .portrait
    }

    // MARK: - Public control

    /// Discards any partial result and starts scanning again. Useful for a "scan another card" flow
    /// after the delegate has been called.
    public func restartScanning() {
        stop()
        session.reset()
        hasFinished = false
        if let scanner = dataScanner {
            do {
                try scanner.startScanning()
            } catch {
                finish(.failure(.scannerUnavailable(error.localizedDescription)))
            }
        } else {
            startIfNeeded()
        }
    }

    // MARK: - Starting and stopping

    private func startIfNeeded() {
        guard dataScanner == nil, startTask == nil, !hasFinished else { return }
        startTask = Task { [weak self] in
            await self?.start()
            self?.startTask = nil
        }
    }

    private func start() async {
        guard Self.isSupported else {
            finish(.failure(.unsupportedDevice))
            return
        }
        guard await Self.requestCameraAccess() else {
            finish(.failure(.cameraAccessDenied))
            return
        }
        guard !hasFinished, dataScanner == nil, isViewLoaded else { return }

        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: configuration.recognitionQuality.visionKitLevel,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: false,
            isGuidanceEnabled: false,
            isHighlightingEnabled: false
        )
        scanner.delegate = self

        addChild(scanner)
        scanner.view.frame = view.bounds
        scanner.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(scanner.view, belowSubview: overlay)
        scanner.didMove(toParent: self)
        dataScanner = scanner

        view.layoutIfNeeded()
        updateRegionOfInterest()

        do {
            try scanner.startScanning()
        } catch {
            finish(.failure(.scannerUnavailable(error.localizedDescription)))
        }
    }

    private func stop() {
        expiryTimer?.invalidate()
        expiryTimer = nil
        dataScanner?.stopScanning()
        setTorch(false)
    }

    private static func requestCameraAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func updateRegionOfInterest() {
        guard let scanner = dataScanner else { return }
        if configuration.showsCardGuide, configuration.restrictsRecognitionToGuide {
            scanner.regionOfInterest = overlay.convert(overlay.guideRect, to: scanner.view)
        } else {
            scanner.regionOfInterest = nil
        }
    }

    // MARK: - Results

    private func process(_ items: [RecognizedItem]) {
        guard !hasFinished else { return }
        let lines = items.compactMap { item -> String? in
            if case .text(let text) = item { return text.transcript }
            return nil
        }
        let now = Date()
        if let card = session.ingest(lines, at: now) {
            finish(.success(card))
            return
        }
        if case .searchingForExpiry = session.phase, expiryTimer == nil {
            scheduleExpiryTimeout()
        }
    }

    /// Frames stop arriving when nothing on screen changes, so the expiry timeout also runs on a timer.
    private func scheduleExpiryTimeout() {
        expiryTimer = Timer.scheduledTimer(withTimeInterval: configuration.expiryTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.hasFinished else { return }
                if let card = self.session.ingest([], at: Date()) {
                    self.finish(.success(card))
                }
            }
        }
    }

    private func finish(_ result: Result<ScannedCard, CardScannerError>) {
        guard !hasFinished else { return }
        hasFinished = true
        stop()
        switch result {
        case .success(let card):
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            delegate?.cardScanner(self, didScan: card)
        case .failure(let error):
            delegate?.cardScanner(self, didFailWith: error)
        }
    }

    private func cancel() {
        guard !hasFinished else { return }
        hasFinished = true
        stop()
        delegate?.cardScannerDidCancel(self)
    }

    // MARK: - Torch

    private static var deviceHasTorch: Bool {
        AVCaptureDevice.default(for: .video)?.hasTorch ?? false
    }

    private func toggleTorch() {
        setTorch(!isTorchOn)
    }

    private func setTorch(_ on: Bool) {
        guard on != isTorchOn,
              let device = AVCaptureDevice.default(for: .video),
              device.hasTorch
        else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
            isTorchOn = on
            overlay.setTorchActive(on)
        } catch {
            // The torch is a convenience; failing to toggle it is not worth surfacing.
        }
    }
}

// MARK: - DataScannerViewControllerDelegate

extension CardScannerViewController: DataScannerViewControllerDelegate {
    public func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
        process(allItems)
    }

    public func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
        process(allItems)
    }

    public func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
        let reason: String
        switch error {
        case .unsupported: reason = "This device does not support live text scanning."
        case .cameraRestricted: reason = "Camera access is restricted."
        @unknown default: reason = String(describing: error)
        }
        finish(.failure(.scannerUnavailable(reason)))
    }
}

extension RecognitionQuality {
    var visionKitLevel: DataScannerViewController.QualityLevel {
        switch self {
        case .fast: return .fast
        case .balanced: return .balanced
        case .accurate: return .accurate
        }
    }
}
#endif
