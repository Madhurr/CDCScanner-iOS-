import Foundation

/// What a secure field does when the user pastes.
public enum PastePolicy: Sendable, Hashable {
    /// Paste is refused. The safest choice when the keyboard's clipboard may be synced or shared.
    case disabled
    /// Pasted text is accepted after everything but digits is stripped. The default.
    case sanitized
}
