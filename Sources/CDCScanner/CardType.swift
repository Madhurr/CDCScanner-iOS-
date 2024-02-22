//
//  CardType.swift
//
//
//  Created by Madhur Jain on 26/01/24.
//

import Foundation

enum CardType: String {
    case all
    case noneExceptCustom
    case visa = "Visa"
    case mastercard = "Mastercard"
    case americanExpress = "American Express"
    case discover = "Discover"
    case chinaTUnion = "China T-Union"
    case chinaUnionPay = "China Union Pay"
    case dinersClubInternational = "Diners Club International"
    case ruPay = "RuPay"
    case interPayment = "Interpayment"
    case jcb = "JCB"
    case maestroUK = "Maestro UK"
    case maestro = "Maestro"
    case dankort = "Dankort"
    case mir = "MIR"
    case npsPridnestrovie = "NPS Pridnestrovie"
    case utap = "UTAP"
    case custom = "Custom Card"
}

extension CardType {
    static var defaultTypes: [CardType: [String: String]] {
        [
            .visa: ["4": "16-19"],
            .mastercard: ["51-55" : "16", "2221-2720" : "16"],
            .americanExpress: ["34" : "15", "37" : "15"],
            .discover: ["6011" : "16-19",
                        "622126-622925" : "16-19",
                        "644-649" : "16-19",
                        "65" : "16-19"],
            .chinaTUnion:["31" : "19"],
            .chinaUnionPay: ["62" : "16-19"],
            .dinersClubInternational: ["36" : "14-19"],
            .ruPay: ["60" : "15",
                     "6521-6522" : "16"],
            .interPayment: ["636" : "16-19"],
            .jcb: ["3528-3589" : "16-19"],
            .maestroUK: ["6759" : "16-19",
                         "676770" : "12-19",
                         "676774" : "12-19"],
            .maestro: ["5018" : "12-19",
                       "5020" : "12-19",
                       "5038" : "12-19",
                       "5893" : "12-19",
                       "6304" : "12-19",
                       "6759" : "12-19",
                       "6761" : "12-19",
                       "6762" : "12-19",
                       "6763" : "12-19"],
            .dankort: ["5019": "16"],
            .mir: ["2200-2204" : "16"],
            .utap: ["1" : "15"]
        ]
    }
}


public enum RecognitionLevel {
    case fastest, fast, normal, accurate, veryaccurate
}
