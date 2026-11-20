import Foundation

/// The Luhn (mod 10) checksum used by payment card numbers.
public enum Luhn {
    /// Returns `true` when `digits` is a non-empty, all-numeric string with a valid Luhn check digit.
    public static func isValid(_ digits: String) -> Bool {
        guard digits.count >= 2 else { return false }
        var sum = 0
        var shouldDouble = false
        for scalar in digits.unicodeScalars.reversed() {
            guard let value = Int(String(scalar)), ("0"..."9").contains(String(scalar)) else { return false }
            if shouldDouble {
                let doubled = value * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += value
            }
            shouldDouble.toggle()
        }
        return sum % 10 == 0
    }
}
