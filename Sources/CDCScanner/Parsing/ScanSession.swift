import CDCCore
import Foundation

/// Accumulates recognised text across camera frames and decides when a scan is complete.
///
/// OCR on a live feed is noisy, so a single frame is never trusted. `ScanSession` counts how
/// many frames agree on each candidate number and expiry and only reports a ``ScannedCard``
/// once ``ScannerConfiguration/requiredConfirmations`` frames agree.
///
/// The type is a plain value with no camera dependency. ``CardScannerViewController`` drives it,
/// and you can drive it yourself from any text source:
///
/// ```swift
/// var session = ScanSession(configuration: .init())
/// for frame in frames {
///     if let card = session.ingest(frame.lines, at: frame.timestamp) {
///         print(card.formattedNumber)
///         break
///     }
/// }
/// ```
public struct ScanSession: Sendable {
    /// Where the session is in its lifecycle.
    public enum Phase: Hashable, Sendable {
        /// No number has been confirmed yet.
        case searchingForNumber
        /// The number is confirmed; waiting for an expiry or for the timeout.
        case searchingForExpiry(CardNumberMatch)
        /// The scan is finished.
        case complete(ScannedCard)
    }

    public let configuration: ScannerConfiguration
    public private(set) var phase: Phase = .searchingForNumber

    private let numberParser: CardNumberParser
    private let expiryParser: ExpiryParser
    private var numberVotes: [CardNumberMatch: Int] = [:]
    private var expiryVotes: [CardExpiry: Int] = [:]
    private var numberConfirmedAt: Date?

    public init(configuration: ScannerConfiguration = ScannerConfiguration()) {
        self.configuration = configuration
        self.numberParser = CardNumberParser(rules: configuration.brandRules)
        self.expiryParser = ExpiryParser()
    }

    /// The result, once the session has completed.
    public var card: ScannedCard? {
        if case .complete(let card) = phase { return card }
        return nil
    }

    /// Feeds one frame's worth of recognised text lines into the session.
    ///
    /// - Parameters:
    ///   - lines: The text observations from a single frame.
    ///   - date: When the frame was captured. Used for the expiry timeout.
    /// - Returns: The finished card the first time the session completes, otherwise `nil`.
    @discardableResult
    public mutating func ingest(_ lines: [String], at date: Date = Date()) -> ScannedCard? {
        if case .complete = phase { return nil }

        let joined = lines.joined(separator: "\n")
        for expiry in expiryParser.parse(joined, referenceDate: date) {
            expiryVotes[expiry, default: 0] += 1
        }

        switch phase {
        case .searchingForNumber:
            for match in numberParser.parse(lines: lines) {
                numberVotes[match, default: 0] += 1
            }
            guard let confirmed = confirmedNumber() else { return nil }
            numberConfirmedAt = date
            phase = .searchingForExpiry(confirmed)
            return finishIfPossible(number: confirmed, at: date)

        case .searchingForExpiry(let number):
            return finishIfPossible(number: number, at: date)

        case .complete:
            return nil
        }
    }

    /// Resets the session so it can be reused for another card.
    public mutating func reset() {
        phase = .searchingForNumber
        numberVotes.removeAll()
        expiryVotes.removeAll()
        numberConfirmedAt = nil
    }

    private func confirmedNumber() -> CardNumberMatch? {
        numberVotes
            .filter { $0.value >= configuration.requiredConfirmations }
            .max { lhs, rhs in
                // Most votes wins; longer numbers break ties so a 16-digit read beats a 15-digit substring.
                (lhs.value, lhs.key.number.count) < (rhs.value, rhs.key.number.count)
            }?
            .key
    }

    private func confirmedExpiry() -> CardExpiry? {
        expiryVotes
            .filter { $0.value >= configuration.requiredConfirmations }
            .max { lhs, rhs in (lhs.value, lhs.key) < (rhs.value, rhs.key) }?
            .key
    }

    private func bestEffortExpiry() -> CardExpiry? {
        expiryVotes.max { lhs, rhs in (lhs.value, lhs.key) < (rhs.value, rhs.key) }?.key
    }

    private mutating func finishIfPossible(number: CardNumberMatch, at date: Date) -> ScannedCard? {
        if let expiry = confirmedExpiry() {
            return complete(number: number, expiry: expiry)
        }
        if !configuration.requiresExpiry {
            return complete(number: number, expiry: bestEffortExpiry())
        }
        if let confirmedAt = numberConfirmedAt, date.timeIntervalSince(confirmedAt) >= configuration.expiryTimeout {
            return complete(number: number, expiry: bestEffortExpiry())
        }
        return nil
    }

    private mutating func complete(number: CardNumberMatch, expiry: CardExpiry?) -> ScannedCard {
        let card = ScannedCard(number: number.number, brand: number.brand, expiry: expiry)
        phase = .complete(card)
        return card
    }
}
