//
//  CDCScannerDelegate.swift
//
//
//  Created by Madhur Jain on 26/01/24.
//

import UIKit

public protocol CDCScannerDelegate: AnyObject {
    func ccScannerCompleted(cardNumber: String, expDate: String, cardType: String)
}
