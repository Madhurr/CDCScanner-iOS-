//
//  Card.swift
//
//
//  Created by Madhur Jain on 27/01/24.
//

import Foundation

public struct Card {
     var binRange = ""
     var lengthRange = ""
     
     /** Returns a custom Card by setting a custom BIN range and card number length. */
     mutating func new(binRange: String, lengthRange: String) -> Card {
         self.binRange = binRange
         self.lengthRange = lengthRange
         
         return self
     }
 }
