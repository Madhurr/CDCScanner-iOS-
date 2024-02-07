#CDCScanner-iOS
Introduction
CDCScanner-iOS is a powerful and easy-to-use library designed to simplify the scanning and extraction of credit/debit card information directly within iOS applications. Utilizing the device's built-in capabilities, it accurately captures card details such as card number, card type, and expiry date without the need for external hardware.

Features
Comprehensive Card Support: Compatible with a wide range of credit and debit cards including Visa, MasterCard, Maestro, American Express, Discover, and more.
Easy Integration: Designed for seamless integration with iOS projects.
Swift-Friendly: Fully written in Swift, offering a modern API for iOS developers.
Privacy-Focused: Processes all information on-device, ensuring user data privacy and security.
Supported Cards
CDCScanner-iOS supports the following card types:

Visa
MasterCard
Maestro
American Express
Discover
China T-Union
China Union Pay
Diners Club International
RuPay
Interpayment
JCB
Dankort
MIR
NPS Pridnestrovie
UTAP
Installation
Swift Package Manager
You can add CDCScanner-iOS to your project via Swift Package Manager by adding the following dependency to your Package.swift file:

swift
Copy code
dependencies: [
    .package(url: "https://github.com/yourgithubusername/CDCScanner-iOS.git", .upToNextMajor(from: "1.0.0"))
]
How to Use
To use CDCScanner-iOS in your project, follow these steps:

Import CDCScanner in your file:
swift
Copy code
import CDCScanner
Instantiate the scanner and configure it as needed:
swift
Copy code
let scanner = CDCScanner()
scanner.delegate = self
Implement the delegate methods to receive scanned card information:
swift
Copy code
extension YourViewController: CDCScannerDelegate {
    func didScanCard(_ card: CardDetails) {
        print("Card Number: \(card.number)")
        print("Expiry Date: \(card.expiryDate)")
        print("Card Type: \(card.type)")
    }
}
Start the scanning process:
swift
Copy code
scanner.startScanning()
Examples
For a detailed example, please refer to the Example directory in the repository. This includes a sample project demonstrating the integration and usage of CDCScanner-iOS in an iOS app.

Requirements
iOS 11.0+
Xcode 11+
Swift 5.0+
License
CDCScanner-iOS is released under the MIT license. See LICENSE for details.

Contact
For any questions or feedback, please contact [Your Name] at [Your Email].

Remember to replace placeholder texts like [Your Name], [Your Email], and https://github.com/yourgithubusername/CDCScanner-iOS.git with your actual contact information and repository URL. Adjust any section according to the specifics of your library and the level of detail you wish to include.
