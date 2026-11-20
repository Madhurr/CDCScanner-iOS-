import CDCCore
import Foundation

/// How hard the recogniser works on each frame.
public enum RecognitionQuality: Sendable, Hashable, Codable {
    /// Lowest latency; fine for well-lit, embossed cards.
    case fast
    /// A sensible default.
    case balanced
    /// Most tolerant of flat-printed or low-contrast cards.
    case accurate
}

/// Options for a scan session.
///
/// ```swift
/// var configuration = ScannerConfiguration()
/// configuration.brandRules = CardBrandRule.defaults(for: [.visa, .mastercard])
/// configuration.requiresExpiry = false
/// ```
public struct ScannerConfiguration: Sendable, Hashable {
    /// The rules used to validate and classify card numbers. Defaults to ``CardBrandRule/defaults``.
    public var brandRules: [CardBrandRule]

    /// How many frames must agree on a value before it is accepted. Higher values reduce
    /// misreads at the cost of a slightly longer scan. Minimum 1.
    public var requiredConfirmations: Int {
        didSet { requiredConfirmations = max(1, requiredConfirmations) }
    }

    /// When `true` the scanner keeps looking for an expiry after the number has been confirmed,
    /// until it is found or ``expiryTimeout`` elapses. When `false` the scan completes as soon as
    /// the number is confirmed, attaching whichever expiry has been seen so far, if any.
    public var requiresExpiry: Bool

    /// How long to wait for an expiry after the number is confirmed, in seconds.
    public var expiryTimeout: TimeInterval

    /// The recognition quality level passed to VisionKit.
    public var recognitionQuality: RecognitionQuality

    /// Whether to draw a card-shaped guide over the camera preview.
    public var showsCardGuide: Bool

    /// Whether text recognition is restricted to the area inside the card guide. Ignored when
    /// ``showsCardGuide`` is `false`.
    public var restrictsRecognitionToGuide: Bool

    /// Whether to show a torch (flashlight) toggle on devices that have one.
    public var showsTorchButton: Bool

    /// Title shown above the camera preview.
    public var title: String

    /// Instruction text shown below the card guide.
    public var instructions: String

    public init(
        brandRules: [CardBrandRule] = CardBrandRule.defaults,
        requiredConfirmations: Int = 3,
        requiresExpiry: Bool = true,
        expiryTimeout: TimeInterval = 5,
        recognitionQuality: RecognitionQuality = .balanced,
        showsCardGuide: Bool = true,
        restrictsRecognitionToGuide: Bool = true,
        showsTorchButton: Bool = true,
        title: String = "Scan Card",
        instructions: String = "Position your card inside the frame"
    ) {
        self.brandRules = brandRules
        self.requiredConfirmations = max(1, requiredConfirmations)
        self.requiresExpiry = requiresExpiry
        self.expiryTimeout = expiryTimeout
        self.recognitionQuality = recognitionQuality
        self.showsCardGuide = showsCardGuide
        self.restrictsRecognitionToGuide = restrictsRecognitionToGuide
        self.showsTorchButton = showsTorchButton
        self.title = title
        self.instructions = instructions
    }
}

/// Errors reported by ``CardScannerViewController`` and ``CardScanner``.
public enum CardScannerError: Error, Hashable, Sendable {
    /// VisionKit's live text scanner is not supported on this device. Requires iOS 16 and an
    /// A12 Bionic chip or newer; the simulator is not supported.
    case unsupportedDevice
    /// The user denied camera access, or it is restricted by a device policy.
    case cameraAccessDenied
    /// The scanner became unavailable while running. The associated value describes why.
    case scannerUnavailable(String)
}

extension CardScannerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedDevice:
            return "Card scanning is not supported on this device."
        case .cameraAccessDenied:
            return "Camera access is required to scan a card."
        case .scannerUnavailable(let reason):
            return "The card scanner is unavailable: \(reason)"
        }
    }
}
