//
//  CustomVideoCapturer.swift
//  BridgingDemo
//
//  Created by Adil Mir on 03/07/21.
//

import Foundation
import OpenTok
import AVFoundation
import Vision
import Accelerate
import UIKit

extension UIApplication {
    func currentDeviceOrientation(cameraPosition pos: AVCaptureDevice.Position) -> OTVideoOrientation {
        let orientation = statusBarOrientation
        if pos == .front {
            switch orientation {
            case .landscapeLeft: return .up
            case .landscapeRight: return .down
            case .portrait: return .left
            case .portraitUpsideDown: return .right
            case .unknown: return .up
            @unknown default:
                return .up
            }
        } else {
            switch orientation {
            case .landscapeLeft: return .down
            case .landscapeRight: return .up
            case .portrait: return .left
            case .portraitUpsideDown: return .right
            case .unknown: return .up
            @unknown default:
                return .up
            }
        }
    }
}

extension AVCaptureSession.Preset {
    func dimensionForCapturePreset() -> (width: UInt32, height: UInt32) {
        switch self {
        case AVCaptureSession.Preset.cif352x288: return (352, 288)
        case AVCaptureSession.Preset.vga640x480, AVCaptureSession.Preset.high: return (640, 480)
        case AVCaptureSession.Preset.low: return (192, 144)
        case AVCaptureSession.Preset.medium: return (480, 360)
        case AVCaptureSession.Preset.hd1280x720: return (1280, 720)
        default: return (352, 288)
        }
    }
}

struct VideoCircularAnnotation {
    var x:Int
    var y:Int
    var widget:WIdget
    var color:UIColor
}

struct LineCoordinates {
    var x:Int
    var y:Int
    var draw:Bool
    var color:UIColor
}

class CustomVideCapturer: VideoCapturerBase, OTVideoCapture {
    var videoContentHint: OTVideoContentHint
    
    var captureSession: AVCaptureSession?
    var videoInput: AVCaptureDeviceInput?
    var videoOutput: AVCaptureVideoDataOutput?
    var videoCaptureConsumer: OTVideoCaptureConsumer?
    var pauseCameraScene = #imageLiteral(resourceName: "scene")

    var cameraPosition: AVCaptureDevice.Position {
        get {
            videoInput?.device.position ?? .unspecified
        }
    }
  
  var modelDataHandler: ModelDataHandler? =
    ModelDataHandler(modelFileInfo: MobileNetSSD.modelInfo, labelsFileInfo: MobileNetSSD.labelsInfo)
    
    fileprivate var capturePreset: AVCaptureSession.Preset {
        didSet {
            (captureWidth, captureHeight) = capturePreset.dimensionForCapturePreset()
        }
    }
    
    fileprivate var captureWidth: UInt32
    fileprivate var captureHeight: UInt32
    fileprivate var capturing = false
    fileprivate let videoFrame: OTVideoFrame
    fileprivate var videoFrameOrientation: OTVideoOrientation = .left  //potrait
    
    let captureQueue: DispatchQueue
    //let objectDetectionModel = try! VNCoreMLModel(for: YOLOv3Int8LUT().model)
    
    fileprivate func updateFrameOrientation() {
        DispatchQueue.main.async {
            guard let inputDevice = self.videoInput else {
                return;
            }
            self.videoFrameOrientation = UIApplication.shared.currentDeviceOrientation(cameraPosition: inputDevice.device.position)
        }
    }
    
    override init(vcDelegate:VideoCapturerDelegate?) {
        capturePreset = AVCaptureSession.Preset.vga640x480
        captureQueue = DispatchQueue(label: "com.tokbox.VideoCapture", attributes: [])
        (captureWidth, captureHeight) = capturePreset.dimensionForCapturePreset()
        videoFrame = OTVideoFrame(format: OTVideoFormat(argbWithWidth: captureWidth, height: captureHeight))
        videoContentHint = .none
        super.init(vcDelegate: vcDelegate)
    }
    
    // MARK: - AVFoundation functions
    fileprivate func setupAudioVideoSession() throws {
        captureSession = AVCaptureSession()
        captureSession?.beginConfiguration()

        captureSession?.sessionPreset = capturePreset
        captureSession?.usesApplicationAudioSession = false

        // Configure Camera Input
        guard let device = camera(withPosition: .back)
            else {
                print("Failed to acquire camera device for video")
                return
        }
        
        videoInput = try AVCaptureDeviceInput(device: device)
        guard let videoInput = self.videoInput else {
            print("There was an error creating videoInput")
            return
        }
        captureSession?.addInput(videoInput)
        
        // Configure Ouput
        videoOutput = AVCaptureVideoDataOutput()
        videoOutput?.alwaysDiscardsLateVideoFrames = true
        videoOutput?.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCMPixelFormat_32BGRA)
        ]
        videoOutput?.setSampleBufferDelegate(self, queue: captureQueue)
        
        guard let videoOutput = self.videoOutput else {
            print("There was an error creating videoOutput")
            return
        }
        captureSession?.addOutput(videoOutput)
        setFrameRate()
        captureSession?.commitConfiguration()
        
        captureSession?.startRunning()
    }
    
    fileprivate func frameRateRange(forFrameRate fps: Int) -> AVFrameRateRange? {
        return videoInput?.device.activeFormat.videoSupportedFrameRateRanges.filter({ range in
            return range.minFrameRate <= Double(fps) && Double(fps) <= range.maxFrameRate
        }).first
    }
    
    fileprivate func setFrameRate(fps: Int = 20) {
        guard let _ = frameRateRange(forFrameRate: fps)
            else {
                print("Unsupported frameRate \(fps)")
                return
        }
        
        let desiredMinFps = CMTime(value: 1, timescale: CMTimeScale(fps))
        let desiredMaxFps = CMTime(value: 1, timescale: CMTimeScale(fps))
        
        do {
            try videoInput?.device.lockForConfiguration()
            videoInput?.device.activeVideoMinFrameDuration = desiredMinFps
            videoInput?.device.activeVideoMaxFrameDuration = desiredMaxFps
        } catch {
            print("Error setting framerate")
        }
        
    }
    
    fileprivate func camera(withPosition pos: AVCaptureDevice.Position) -> AVCaptureDevice? {
      let deviceDiscoverySession = AVCaptureDevice.DiscoverySession(
        deviceTypes: [ .builtInWideAngleCamera,.builtInDualCamera],
          mediaType: .video,
          position: pos
      )
      return deviceDiscoverySession.devices.first
    }
    
    fileprivate func updateCaptureFormat(width w: UInt32, height h: UInt32) {
        captureWidth = w
        captureHeight = h
        videoFrame.format = OTVideoFormat.init(argbWithWidth: w, height: h)
    }

    // MARK: - OTVideoCapture protocol
    func initCapture() {
        NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification,
                                               object: nil,
                                               queue: .main,
                                               using: { (_) in self.updateFrameOrientation() })
        captureQueue.async {
            do {
                try self.setupAudioVideoSession()
            } catch let error as NSError {
                print("Error configuring AV Session: \(error)")
            }
        }
    }
    
    func start() -> Int32 {
        self.updateFrameOrientation()
        self.capturing = true
        return 0
    }
    
    func stop() -> Int32 {
        capturing = false
        return 0
    }
    
    override func releaseCapture() {
        let _ = stop()
        videoOutput?.setSampleBufferDelegate(nil, queue: captureQueue)
        captureQueue.sync {
            self.captureSession?.stopRunning()
        }
        captureSession = nil
        videoOutput = nil
        videoInput = nil
        
        NotificationCenter.default.removeObserver(self,
                                                  name: UIDevice.orientationDidChangeNotification,
                                                  object: nil)
    }
    
    func isCaptureStarted() -> Bool {
        return capturing && (captureSession != nil)
    }
    
    func captureSettings(_ videoFormat: OTVideoFormat) -> Int32 {
        videoFormat.pixelFormat = .ARGB
        videoFormat.imageWidth = captureWidth
        videoFormat.imageHeight = captureHeight
        return 0
    }
    
    fileprivate func frontFacingCamera() -> AVCaptureDevice? {
        return camera(withPosition: .front)
    }
    
    fileprivate func backFacingCamera() -> AVCaptureDevice? {
        return camera(withPosition: .back)
    }
    
    fileprivate var hasMultipleCameras : Bool {
      if let _ = AVCaptureDevice.default(.builtInWideAngleCamera, for: AVMediaType.video, position: .front),let _ = AVCaptureDevice.default(.builtInWideAngleCamera, for: AVMediaType.video, position: .back) {
        return true
      }
      return false
    }
    
    func setCameraPosition(_ position: AVCaptureDevice.Position) -> Bool {
        guard let preset = captureSession?.sessionPreset else {
            return false
        }
        
        let newVideoInput: AVCaptureDeviceInput? = {
            do {
                if position == AVCaptureDevice.Position.back {
                    guard let backFacingCamera = backFacingCamera() else { return nil }
                    return try AVCaptureDeviceInput.init(device: backFacingCamera)
                } else if position == AVCaptureDevice.Position.front {
                    guard let frontFacingCamera = frontFacingCamera() else { return nil }
                    return try AVCaptureDeviceInput.init(device: frontFacingCamera)
                } else {
                    return nil
                }
            } catch {
                return nil
            }
        }()
        
        guard let newInput = newVideoInput else {
            return false
        }
        
        var success = true
        
        captureQueue.sync {
            captureSession?.beginConfiguration()
            guard let videoInput = self.videoInput else { return }
            captureSession?.removeInput(videoInput)
            
            if captureSession?.canAddInput(newInput) ?? false {
                captureSession?.addInput(newInput)
                self.videoInput = newInput
            } else {
                success = false
                captureSession?.addInput(videoInput)
            }
            
            captureSession?.commitConfiguration()
        }
        
        if success {
            capturePreset = preset
        }
        
        return success
    }
    
    func toggleCameraPosition() -> Bool {
        guard hasMultipleCameras else {
            return false
        }
        
        if  videoInput?.device.position == .front {
            return setCameraPosition(.back)
        } else {
            return setCameraPosition(.front)
        }
    }
}

extension CustomVideCapturer: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ captureOutput: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        //print("Dropping frame")
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection)
    {
        if !capturing || videoCaptureConsumer == nil { return }
        
        connection.isVideoMirrored = false;
        
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                print("Error acquiring sample buffer")
                return
        }

        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        CVPixelBufferLockBaseAddress(imageBuffer, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)))
        
        videoFrame.timestamp = time
        let height = UInt32(CVPixelBufferGetHeight(imageBuffer))
        let width = UInt32(CVPixelBufferGetWidth(imageBuffer))
        
        if width != captureWidth || height != captureHeight {
            updateCaptureFormat(width: width, height: height)
        }

        var uii:UIImage?
        if isPaused {
            uii = pauseCameraScene.copy() as! UIImage
            sendProcessedImage(uii: uii)
        } else {
            let cii = ciImage(from: sampleBuffer)
            
            // frozen image?
            if self.isFrozen {
                if self.frozenImage == nil {
                    
                    // mask face
                    if bMaskFaces {
                        self.frozenImage = maskFaces(cii: cii!)
                    }
                    // end mask face
                    
                    if self.frozenImage == nil {
                        self.frozenImage = cgImage(from: cii!)
                    }
                }
                
                uii = self.uiImage(from: self.frozenImage!)
                sendProcessedImage(uii: uii)
            } else {
                var cgi:CGImage?
                
                // mask face
                if bMaskFaces {
                    cgi = maskFaces(cii: cii!)
                }
                // end mask face
                
                if cgi == nil {
                    cgi = cgImage(from: cii!)
                }
                
                executeTap(cgi)
                
                if bMaskDisplays {
                    executeMaskDisplays(cgi, imageBuffer: imageBuffer)
                 
              } else {
                    self.sendProcessedImage(uii: self.uiImage(from: cgi!))
                }
            }
            // end frozen image
        }
        
        CVPixelBufferUnlockBaseAddress(imageBuffer, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)));
    }

    func executeTap(_ cgiImage:CGImage?) {

        if bTapEnabled && bTapRequested {
            bTapRequested = false
            let dbr = VNDetectBarcodesRequest { (request, error) in
                if request.results != nil && request.results!.count > 0 {
                    request.results?.compactMap({$0 as? VNBarcodeObservation})
                        .forEach({ (observation) in
                            let message = observation.payloadStringValue
                            let tm = TapMessage(type: "bc", text: message ?? "")
                            self.vcDelegate?.sendMessage(type: "tp", message: String(data: tm.toJSONData()!, encoding: .utf8)!)
                        })
                }
            }
            
            try? VNImageRequestHandler(cgImage: cgiImage!, orientation: .left, options: [:]).perform([dbr])
        }
    }
    
  func executeMaskDisplays(_ cgiImage:CGImage?,imageBuffer: CVPixelBuffer) {
    var cgi = cgiImage
    let result = modelDataHandler?.runModel(onFrame: imageBuffer)?.inferences
    var rectArray = Array<CGRect>()
    if result?.count ?? 0 > 0 {
      for res in result! {
        rectArray.append(res.rect)
      }
      let mdcgi = self.maskDisplays(regions: rectArray, cii: self.ciImage(from: cgi!)!)
      
      if mdcgi != nil {
        cgi = mdcgi
      }
    }
    
    self.sendProcessedImage(uii: self.uiImage(from: cgi!))
  }
//        let imageRequest = VNCoreMLRequest(model: objectDetectionModel) { (request, error) in
//
//            if request.results != nil && request.results!.count > 0 {
//                var rectArray = Array<CGRect>()
//                request.results?.compactMap({$0 as? VNRecognizedObjectObservation})
//                    .filter({$0.confidence > 0.5 &&
//                                (       $0.labels[0].identifier == "laptop" ||  $0.labels[0].identifier == "tvmonitor"
//                                    ||  $0.labels[0].identifier == "cell phone" ||  $0.labels[0].identifier == "microwave")})
//                    .forEach({ (observation) in
//                        let rect = self.boundingBox(forRegionOfInterest: observation.boundingBox,
//                                         withinImageBounds: CGRect(x: 0, y: 0, width: cgi!.width, height: cgi!.height))
//                        rectArray.append(rect)
//                        print(observation.labels[0].identifier)
//                })
//
//                let mdcgi = self.maskDisplays(regions: rectArray, cii: self.ciImage(from: cgi!)!)
//
//                if mdcgi != nil {
//                    cgi = mdcgi
//                }
//            }
//
//            self.sendProcessedImage(uii: self.uiImage(from: cgi!))
//        }
//
//        try? VNImageRequestHandler(cgImage: cgi!, orientation: .left, options: [:]).perform([imageRequest])
 //   }
    
    func inferOrientation(image: UIImage) -> CGImagePropertyOrientation {
        switch image.imageOrientation {
        case .up:
            return CGImagePropertyOrientation.up
        case .upMirrored:
            return CGImagePropertyOrientation.upMirrored
        case .down:
            return CGImagePropertyOrientation.down
        case .downMirrored:
            return CGImagePropertyOrientation.downMirrored
        case .left:
            return CGImagePropertyOrientation.left
        case .leftMirrored:
            return CGImagePropertyOrientation.leftMirrored
        case .right:
            return CGImagePropertyOrientation.right
        case .rightMirrored:
            return CGImagePropertyOrientation.rightMirrored
        @unknown default:
            return CGImagePropertyOrientation.up
        }
    }
    
    func boundingBox(forRegionOfInterest: CGRect, withinImageBounds bounds: CGRect) -> CGRect {
        
        let rect = VNImageRectForNormalizedRect(forRegionOfInterest, Int(bounds.width), Int(bounds.height))
        return rect
    }
    
    func sendProcessedImage(uii:UIImage?) {
        
        guard let videoInput = videoInput else {
                print("Capturer does not have a valid input")
                return
        }
        
        // overlays
        let newPixelBuffer:CVPixelBuffer? = processOverlays(image: uii!);
        
        videoFrame.format?.imageWidth = UInt32((uii!.size.width))
        videoFrame.format?.imageHeight = UInt32((uii!.size.height))
        let minFrameDuration = videoInput.device.activeVideoMinFrameDuration
        
        videoFrame.format?.estimatedFramesPerSecond = Double(minFrameDuration.timescale) / Double(minFrameDuration.value)
        videoFrame.format?.estimatedCaptureDelay = 100
        videoFrame.orientation = videoFrameOrientation
        
        videoFrame.clearPlanes()
        
        if !CVPixelBufferIsPlanar(newPixelBuffer!) {
            videoFrame.planes?.addPointer(CVPixelBufferGetBaseAddress(newPixelBuffer!))
        } else {
            for idx in 0..<CVPixelBufferGetPlaneCount(newPixelBuffer!) {
                videoFrame.planes?.addPointer(CVPixelBufferGetBaseAddressOfPlane(newPixelBuffer!, idx))
            }
        }
        
        if let delegate = delegate {
            delegate.finishPreparingFrame(videoFrame)
        }
        
        videoCaptureConsumer!.consumeFrame(videoFrame)
        CVPixelBufferUnlockBaseAddress(newPixelBuffer!, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)))
    }
}

extension Encodable {
    func toJSONData() -> Data? { try? JSONEncoder().encode(self) }
}
