import Foundation
import UIKit
import Vision
import Photos
import AVFoundation


@available(iOS 13.0, *)
public class CDCScanner: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    
   public var delegate: CDCScannerDelegate?
   public var createCardType = Card()
   public var cards = [CardType.all]
   public var recognitionLevel: RecognitionLevel?
    
    // MARK: - Standard Variables
    
    let year = Calendar.current.component(.year, from: Date())
    public var usedCards = [CardType: [String: String]]()
    public recognizedText = ""
    public var finalText = ""
    public var image: UIImage?
    public var processing = false
    public var findExp = false
    public var cardNumberDict = [String:Int]()
    public var cardExpDict = [String:Int]()
    public var cardExpPass = 0
    public var nagivationCont = UINavigationController()
    public var foundType: CardType?
    public var finalCardNumber = ""
    public var finalExpDate = ""
    public var finalName = ""
    public var ccPassLoops = 3
    public var expPassLoops = 3
    public var customCards = [String: String]()
    
    // MARK: - Lifecycle
     public  override func viewDidLoad() {
           super.viewDidLoad()
           setupCardOptions()
       }
    
    /** Add custom Cards to run a visual check against in a scan. */
    public func addCustomCards(cards: Array<Card>) {
        for card in cards {
            self.customCards[card.binRange] = card.lengthRange
        }
    }
    
    public func setupCardOptions() {
        self.ccPassLoops = 3
        self.expPassLoops = 4
        
        switch recognitionLevel {
        case .veryaccurate:
            self.ccPassLoops += 2
            self.expPassLoops += 2
            break
        case .accurate:
            self.ccPassLoops += 1
            self.expPassLoops += 1
            break
        case .normal:
            break
        case .fast:
            self.ccPassLoops -= 1
            self.expPassLoops -= 1
            break
        case .fastest:
            self.ccPassLoops -= 2
            self.expPassLoops -= 2
            break

        default:
            break
        }
        
        done: for card in cards {
            if card == .all {
                self.usedCards = CardType.defaultTypes
                self.usedCards[CardType.custom] = self.customCards
                break done
            } else if card == .noneExceptCustom {
                self.usedCards.removeAll()
                self.usedCards[CardType.custom] = self.customCards
                break done
            } else if card == .custom {
                self.usedCards[CardType.custom] = self.customCards
            } else {
                self.usedCards[card] = CardType.defaultTypes[card]
            }
        }
        
        
    }
    
    // MARK: - Vision
        
    private lazy var textDetectionRequest: VNRecognizeTextRequest = {
        let request = VNRecognizeTextRequest(completionHandler: self.handleDetectedText)
        request.recognitionLevel = .accurate
        request.minimumTextHeight = 0.020
        request.usesLanguageCorrection = false
        return request
    }()
    
     let disQueue = DispatchQueue(label: "my.image.handling.queue")
     var captureSession: AVCaptureSession?
     lazy var previewLayer = AVCaptureVideoPreviewLayer()
    
    public func  startScanner(viewController: UIViewController)
    {
       
        let preview = AVCaptureVideoPreviewLayer(session: self.captureSession!)
        preview.videoGravity = .resizeAspect
        self.previewLayer = preview
        
        let screenSize = UIScreen.main.bounds
        let cardLayer = CAShapeLayer()
        cardLayer.frame = screenSize
        self.previewLayer.insertSublayer(cardLayer, above: self.previewLayer)
        
        let cardWidth = 350.0 as CGFloat
        let cardHeight = 225.0 as CGFloat
        let cardXlocation = (screenSize.width - cardWidth) / 2
        let cardYlocation = (screenSize.height / 2) - (cardHeight / 2) - (screenSize.height * 0.05)
        let path = UIBezierPath(roundedRect: CGRect(
                                    x: cardXlocation, y: cardYlocation, width: cardWidth, height: cardHeight),
                                cornerRadius: 10.0)
        cardLayer.path = path.cgPath
        cardLayer.strokeColor = UIColor.white.cgColor
        cardLayer.lineWidth = 8.0
        cardLayer.backgroundColor = UIColor.black.withAlphaComponent(0.7).cgColor
        let mask = CALayer()
        mask.frame = cardLayer.bounds
        cardLayer.mask = mask
        let r = UIGraphicsImageRenderer(size: mask.bounds.size)
        let im = r.image { ctx in
            UIColor.black.setFill()
            ctx.fill(mask.bounds)
            path.addClip()
            ctx.cgContext.clear(mask.bounds)
        }
        mask.contents = im.cgImage
        self.previewLayer.frame = screenSize
        self.addCameraInput()
        self.addVideoOutput()
        let viewCont = UIViewController()
        viewCont.view.backgroundColor = .black
        viewCont.view.frame = screenSize
        viewCont.title = "Card Scanner"
        viewCont.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(self.doneButton(_:)))
        self.nagivationCont = UINavigationController(rootViewController: viewCont)
        self.nagivationCont.modalPresentationStyle = .fullScreen
        viewController.present(self.nagivationCont, animated: true, completion: nil)
        viewCont.view.layer.addSublayer(self.previewLayer)
        self.disQueue.async {
            self.captureSession!.startRunning()
        }
    }

    private func addCameraInput() {
        let device = AVCaptureDevice.default(for: .video)!
        let cameraInput = try! AVCaptureDeviceInput(device: device)
        self.captureSession!.addInput(cameraInput)
    }
    
    private func addVideoOutput() {
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.videoSettings = [(kCVPixelBufferPixelFormatTypeKey as NSString) : NSNumber(value: kCVPixelFormatType_32BGRA)] as [String : Any]
        videoOutput.setSampleBufferDelegate(self, queue: self.disQueue)
        self.captureSession!.addOutput(videoOutput)
    }
    
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection)
    {
        if !processing
        {
            guard let frame = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                debugPrint("unable to get image from sample buffer")
                return
            }
            self.processing = true
            let ciimage : CIImage = CIImage(cvPixelBuffer: frame)
            let theimage : UIImage = self.convert(cmage: ciimage)
            self.image = theimage
            self.processImage()
        }
    }
    
    private func convert(cmage:CIImage) -> UIImage
    {
        let context:CIContext = CIContext.init(options: nil)
        let cgImage:CGImage = context.createCGImage(cmage, from: cmage.extent)!
        let image:UIImage = UIImage.init(cgImage: cgImage)
        return image
    }
    
    private func processImage()
    {
        guard let image = image, let cgImage = image.cgImage else { return }
        let requests = [textDetectionRequest]
        let imageRequestHandler = VNImageRequestHandler(cgImage: cgImage, orientation: .right, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try imageRequestHandler.perform(requests)
            } catch let error {
                print("Error: \(error)")
            }
        }
    }
    
    public  func callDelegate() {
        self.delegate?.ccScannerCompleted(cardNumber: self.finalCardNumber,
                                          expDate: self.finalExpDate,
                                          cardType: self.foundType?.rawValue ?? "error")
        self.closeCapture()
    }
    
    @objc func doneButton(_ sender: UIBarButtonItem) {
        self.closeCapture()
    }
    
    private func closeCapture()
    {
        if self.captureSession == nil {
            self.captureSession = AVCaptureSession()
        }
        self.finalCardNumber = ""
        self.finalExpDate = ""
        self.finalName = ""
        self.processing = false
        self.findExp = false
        self.cardExpPass = 0
        self.cardNumberDict = [String:Int]()
        self.cardExpDict = [String:Int]()
        self.textDetectionRequest.minimumTextHeight = 0.020
        self.disQueue.async {
            self.captureSession!.stopRunning()
            if let inputs = self.captureSession!.inputs as? [AVCaptureDeviceInput] {
                for input in inputs {
                    self.captureSession!.removeInput(input)
                }
            }
        }
        DispatchQueue.main.async {
            self.previewLayer.removeFromSuperlayer()
            self.nagivationCont.dismiss(animated: true, completion: nil)
        }
    }
    
    // MARK: - Handle the read text
    
    fileprivate func handleDetectedText(request: VNRequest?, error: Error?)
    {
        self.finalText = ""
        
        if let error = error {
            print(error.localizedDescription)
            self.processing = false
            return
        }
        guard let results = request?.results, results.count > 0 else {
            self.processing = false
            return
        }
        
        if let requestResults = request?.results as? [VNRecognizedTextObservation] {
            self.recognizedText = ""
            for observation in requestResults {
                guard let candidiate = observation.topCandidates(1).first else { return }
                self.recognizedText += candidiate.string
                self.recognizedText += " "
            }
            
            var cleanedText = self.cleanText(originalText: self.recognizedText)
            
            if self.findExp && self.cardExpPass < 7 {
                findExpDate(fullText: self.recognizedText)
            }
            else if self.findExp {
                print("NO EXP DATE FOUND")
                self.callDelegate()
            }
            else
            {
                cleanedText = cleanedText.filter("0123456789".contains)
                verify: for (type, details) in self.usedCards {
                    for cardRange in details {
                        let cardNums = self.getCardDict(stringRange: cardRange.key)
                        let cardLengths = self.getCardDict(stringRange: cardRange.value)
                        
                        for num in cardNums {
                            for len in cardLengths {
                                if self.findCC(fullText: cleanedText, startingNum: Int(num)!, lengthOfCard: Int(len)!) {
                                    self.foundType = type
                                    break verify
                                }
                            }
                        }
                    }
                }
            }
        }
        
        self.processing = false
    }
    
    private func getCardDict(stringRange: String) -> [String] {
        let cardNums = stringRange.components(separatedBy: "-")
        var finalCardNums = [String]()
        if cardNums.count > 1 {
            var cardCount = Int(cardNums[0])!
            finalCardNums.append(String(cardCount))
            repeat {
                cardCount += 1
                finalCardNums.append(String(cardCount))
            } while cardCount < Int(cardNums[1])!
        }
        else {
            finalCardNums.append(cardNums[0])
        }
        
        return finalCardNums
    }
    
    private func cleanText(originalText: String) -> String {
        var replaced = originalText.replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ".", with: "")
        replaced = String(replaced.filter { !"\n\t\r".contains($0) })
        return replaced.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Exp Date
    
    private func findExpDate(fullText: String)
    {
        // looks for valid date for the next 20 years
        let expDate = fullText.regex(pattern: #"[0-1][0-9][\/][2-4][0-9]"#)
        
        if expDate.count > 0 {
            var finalDate = expDate[0]
            if expDate.count > 1 {
                var dates = [[String:Int]]()
                for ed in expDate {
                    let year = Int(ed.suffix(2))!
                    let month = Int(ed.prefix(2))!
                    dates.append(["month" : month, "year" : year])
                }
                let sortedDates = dates.sorted { $0["year"]! > $1["year"]! }
                
                finalDate = String(format:"%02d/%d", sortedDates[0]["month"]!, sortedDates[0]["year"]!)
            }
            
            if let expCount = self.cardExpDict[finalDate] {
                self.cardExpDict[finalDate]! = expCount + 1
            } else {
                self.cardExpDict[finalDate] = 0
            }
            
            if self.cardExpDict[finalDate]! > 3
            {
                //print("EXP DATE: ", finalDate)
                self.finalExpDate = finalDate
                self.callDelegate()
            }
        }
        
        self.cardExpPass += 1
    }
    
    // MARK: - Credit Card Number
    
    private func findCC(fullText: String, startingNum: Int, lengthOfCard: Int) -> Bool
    {
        if let numIndex = fullText.index(of: String(startingNum)) {
            let cardCheck = fullText[numIndex...]
            if cardCheck.count > lengthOfCard - 1 {
                return self.processCC(cardNumber: String(cardCheck))
            } else {
                return false
            }
        } else {
            return false
        }
    }
    
    private func processCC(cardNumber: String) -> Bool
    {
        let cardCheck = cardNumber[0..<16]
        let cardCheckRev = cardCheck.reversed().dropFirst()
        
        var testNum = 0
        
        // Luhn algorithm
        for (index, char) in cardCheckRev.enumerated() {
            if index % 2 == 0 {
                var num = Int(String(char))! * 2
                if num > 9 { num -= 9 }
                testNum += num
            } else {
                let num = Int(String(char))!
                testNum += num
            }
        }
        testNum += Int(String(cardCheck.last!))!
        if testNum % 10 == 0 {
            
            if let cardCount = self.cardNumberDict[cardCheck] {
                self.cardNumberDict[cardCheck]! = cardCount + 1
            } else {
                self.cardNumberDict[cardCheck] = 0
            }
            
            if self.cardNumberDict[cardCheck]! > self.ccPassLoops
            {
                //print("PASSED: ", cardCheck)
                self.finalCardNumber = cardCheck
                
                self.textDetectionRequest.minimumTextHeight = 0.01
                self.findExp = true
            }
            
            return true
        }
        else
        {
            return false
        }
    }
}

