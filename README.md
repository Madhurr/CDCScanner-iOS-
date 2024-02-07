# CDCScanner
### Introduction

CDCScanner-iOS is a powerful and easy-to-use library designed to simplify the scanning and extraction of credit/debit card information directly within iOS applications. Utilizing the device's built-in capabilities, it accurately captures card details such as card number, card type, and expiry date without the need for external hardware.

### Features 

*   Comprehensive Card Support:  Compatible with a wide range of credit and debit cards including Visa, MasterCard, Maestro, American Express, Discover, and more.

*   Easy Integration: Designed for seamless integration with iOS projects.
    
*   Swift-Friendly: Fully written in Swift, offering a modern API for iOS developers.

*    Privacy-Focused: Processes all information on-device, ensuring user data privacy and security.

###  Supported Cards

CDCScanner-iOS supports the following card types:

* Visa
* MasterCard
* Maestro
* American Express
* Discover
* China T-Union
* China Union Pay
* Diners Club International
* RuPay
* Interpayment
* JCB
* Dankort
* MIR
* NPS Pridnestrovie
* UTAP

## Installation
###  Swift Package Manager
You can add CDCScanner-iOS to your project via Swift Package Manager by adding the following dependency to your Package.swift file:
```
dependencies: [
    .package(url: "https://github.com/yourgithubusername/CDCScanner-iOS.git", .upToNextMajor(from: "1.0.0"))
]
```
### How to Use
To use CDCScanner-iOS in your project, follow these steps:
1. Import CDCScanner in your file:
   
   ```
   import CDCScanner
   ```
2. Instantiate the scanner and configure it as needed:
   
    ```
    let scanner = CDCScanner()
    scanner.delegate = self

3. Implement the delegate methods to receive scanned card information:
    
    ```
    extension YourViewController: CDCScannerDelegate {
    func didScanCard(_ card: CardDetails) {
        print("Card Number: \(card.number)")
        print("Expiry Date: \(card.expiryDate)")
        print("Card Type: \(card.type)")
    }
    }

### Examples
For a detailed example, please refer to the Example directory in the repository. This includes a sample project demonstrating the integration and usage of CDCScanner-iOS in an iOS app. 

### Requirements
* iOS 11.0+
* Xcode 11+
* Swift 5.0+
     
### License
CDCScanner-iOS is released under the MIT license. See LICENSE for details.

### Contact
For any questions or feedback, please contact Dev at Madhurjain874@gmail.com.




