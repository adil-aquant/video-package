//
//  VideoCapturer.swift
//  BridgingDemo
//
//  Created by Adil Mir on 03/07/21.
//

import Foundation
import AVFoundation
import OpenTok
import UIKit

protocol VideoCapturer {
    func updateGuidePos(xPos x:Int, yPos y:Int)
    func stopGuidance()
    func endGuidance()
    func annotate(xPos x:Int, yPos y:Int,widget:WIdget,color:UIColor)
    func toggleFreeze(shouldFreeze:Bool)
    func drawFreeHand(xPos x:Int, yPos y:Int,draw:Bool,color:UIColor)
    func releaseCapture()
    func togglePause()
    func requestTap()
    func videSettingsUpdated()
    func updateSelectedWidget(widget:WIdget)
}

protocol VideoCapturerDelegate {
    func sendMessage(type:String, message:String)
}

protocol FrameCapturerMetadataDelegate {
    func finishPreparingFrame(_ videoFrame: OTVideoFrame?)
}

public struct TapMessage : Encodable {
    public var type = String()
    public var text = String()
}

public class VideoCapturerBase : NSObject, VideoCapturer {
    
    var delegate: FrameCapturerMetadataDelegate?
    var annotations = Array<VideoCircularAnnotation>()
    var lineCoordinates     = [LineCoordinates]()
    var guidingInProgress = false
    var gxPos = 0
    var gyPos = 0
    var isFrozen = false
    var isPaused = false
    var frozenImage:CGImage?
    var context = CIContext()
    var vcDelegate:VideoCapturerDelegate?
    private var selectedWidget = WIdget.pencil
    
    public var bTapEnabled = Utils.getVideoSettings().onTapStream, bTapRequested = true, bMaskFaces = Utils.getVideoSettings().faceMask, bMaskDisplays = Utils.getVideoSettings().displayMask
    
    init(vcDelegate:VideoCapturerDelegate?) {
        self.vcDelegate = vcDelegate 
    }
    
    public func processOverlays(image:UIImage) -> CVPixelBuffer?{
        var newPixelBuffer:CVPixelBuffer?
        
        var uii = image
        if(self.annotations.count > 0){
            uii = overlayCircularAnnotations(parent: uii)
        }
        
        if(guidingInProgress){
            uii = overlayGuide(parent: uii, overlay: getGuideImage(), ox: gxPos, oy: gyPos)
        }
        
      if(self.lineCoordinates.count > 0) {
        uii = overlayLineAnnotations(parent: uii)
      }
        
        newPixelBuffer = buffer(from: (uii.cgImage)!)
        return newPixelBuffer
    }
    
    public func getGuideImage() -> UIImage {
        switch selectedWidget{
        case .cursor:
         return #imageLiteral(resourceName: "Cursor")
        default:
          return #imageLiteral(resourceName: "hand_pointer_2")
        }
    }
    
    public func overlayGuide(parent: UIImage, overlay: UIImage, ox:Int, oy:Int) -> UIImage {
        let size = parent.size
        let container = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        parent.draw(in: container)
        
        // draw guide
        let posX = oy
        let posY = Int(size.height) - ox
        
        let oWidth = 22, oHeight = 22
        let ov = overlay.rotate(by: 90)
        ov.draw(in: CGRect(x: posX, y: posY, width: oWidth, height: oHeight), blendMode: .normal, alpha: 0.7)
        // end draw guide
        let newImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return newImage
    }
    
    public func overlayCircularAnnotations(parent: UIImage) -> UIImage  {
        
        let size = parent.size
        let container = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        parent.draw(in: container)
        
        // draw annotations
        let ctx = UIGraphicsGetCurrentContext()
        ctx?.saveGState()
        
        for annotation in self.annotations {
            let posX = annotation.y - 15
            let posY = Int(size.height) - annotation.x + 15
            let rect = CGRect(x: posX, y: posY, width: 50, height: 50)
          ctx?.setStrokeColor(annotation.color.cgColor)
            ctx?.setLineWidth(5)
          switch annotation.widget{
          case .circle:
            ctx?.strokeEllipse(in: rect)
          case .square:
            ctx?.addRect(rect)
            ctx?.drawPath(using: .stroke)
          case .cursor:
            continue
          case .pencil:
            continue
          }
        }
        ctx?.restoreGState()
        // end draw annotations
        
        let newImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return newImage
    }
  
    public func overlayLineAnnotations(parent: UIImage) -> UIImage  {
      
      let size = parent.size
      let container = CGRect(x: 0, y: 0, width: size.width, height: size.height)
      UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
      parent.draw(in: container)
      
      // draw line
      let ctx = UIGraphicsGetCurrentContext()
      ctx?.saveGState()
    for (index,coordinate) in lineCoordinates.enumerated() {
      if index == 0 || !coordinate.draw {
        continue
      }
      let previousCoordinates = lineCoordinates[index - 1]
      let previousX = previousCoordinates.y + 20
      let previousY = Int(size.height) - previousCoordinates.x + 22
      let posX = coordinate.y + 20
      let posY = Int(size.height) - coordinate.x + 22
      ctx?.setLineWidth(4.0)
      ctx?.setStrokeColor(coordinate.color.cgColor)
      ctx?.move(to: CGPoint(x: previousX, y: previousY))
      ctx?.addLine(to: CGPoint(x: posX, y: posY))
      ctx?.strokePath()
    }
    ctx?.restoreGState()
    // end draw annotations
    
    let newImage = UIGraphicsGetImageFromCurrentImageContext()!
    UIGraphicsEndImageContext()
    return newImage
  }

    public func maskText(cii:CIImage) -> CGImage? {
        var cgi:CGImage?
        
        let textDetector = CIDetector(ofType: CIDetectorTypeText, context: nil, options: [CIDetectorAccuracy : CIDetectorAccuracyHigh])
        let features = textDetector?.features(in: cii)
        
        if features != nil {
            var maskImage: CIImage?
            let pixelateFiler = CIFilter(name: "CIPixellate")
            pixelateFiler!.setValue(cii, forKey: kCIInputImageKey)
            let inputScaleKey = max(cii.extent.width, cii.extent.height) / 60.0
            pixelateFiler!.setValue(inputScaleKey, forKey: kCIInputScaleKey)

            for feature in features! as! [CITextFeature] {
                print("Found a text block \(feature.bounds.origin.x)")
                
                let linearGradient = CIFilter(name: "CILinearGradient")
                linearGradient!.setValue(CIColor(red: 0, green: 1, blue: 0, alpha: 1), forKey: "inputColor0")
                linearGradient!.setValue(CIColor(red: 0, green: 0, blue: 0, alpha: 0), forKey: "inputColor1")
                linearGradient!.setValue(CIVector(x: feature.bounds.origin.x, y: feature.bounds.origin.y), forKey: "inputPoint0")
                linearGradient!.setValue(CIVector(x: feature.bounds.origin.x + feature.bounds.size.width,
                                                  y: feature.bounds.origin.y + feature.bounds.size.height), forKey: "inputPoint1")
                
                let rectangleImage = linearGradient!.outputImage!.cropped(to: cii.extent)
                
                if (maskImage == nil) {
                    maskImage = rectangleImage
                } else {
                    let filter =  CIFilter(name: "CISourceOverCompositing")
                    filter!.setValue(rectangleImage, forKey: kCIInputImageKey)
                    filter!.setValue(maskImage, forKey: kCIInputBackgroundImageKey)
                    
                    maskImage = filter!.outputImage
                }
            }
            
            let composite = CIFilter(name: "CIBlendWithMask")
            composite!.setValue(pixelateFiler!.outputImage, forKey: kCIInputImageKey)
            composite!.setValue(cii, forKey: kCIInputBackgroundImageKey)
            composite!.setValue(maskImage, forKey: kCIInputMaskImageKey)
            
            cgi = context.createCGImage(composite!.outputImage!, from: composite!.outputImage!.extent)
        }
        
        return cgi
    }
    
    public func maskDisplays(regions:Array<CGRect>, cii:CIImage) -> CGImage? {
        var cgi:CGImage?
        
        if regions.count > 0 {
            var maskImage: CIImage?
            let pixelateFiler = CIFilter(name: "CIPixellate")
            pixelateFiler!.setValue(cii, forKey: kCIInputImageKey)
            let inputScaleKey = max(cii.extent.width, cii.extent.height) / 60.0
            pixelateFiler!.setValue(inputScaleKey, forKey: kCIInputScaleKey)
            
            regions.forEach { (region) in
                
                let centerX = region.origin.x + region.size.width / 2.0
                let centerY = region.origin.y + region.size.height / 2.0
              let radius = min(region.size.width, region.size.height) / 1.5
                print("x = \(centerX), y = \(centerY)")
                
                let radialGradient = CIFilter(name: "CIRadialGradient")
                radialGradient!.setValue(radius, forKey: "inputRadius0")
                radialGradient!.setValue(radius + 1, forKey: "inputRadius1")
                radialGradient!.setValue(CIColor(red: 0, green: 1, blue: 0, alpha: 1), forKey: "inputColor0")
                radialGradient!.setValue(CIColor(red: 0, green: 0, blue: 0, alpha: 0), forKey: "inputColor1")
                radialGradient!.setValue(CIVector(x: centerX, y: centerY), forKey: kCIInputCenterKey)
                
                let rectangleImage = radialGradient!.outputImage!.cropped(to: cii.extent)
                
                if (maskImage == nil) {
                    maskImage = rectangleImage
                } else {
                    let filter =  CIFilter(name: "CISourceOverCompositing")
                    filter!.setValue(rectangleImage, forKey: kCIInputImageKey)
                    filter!.setValue(maskImage, forKey: kCIInputBackgroundImageKey)
                    
                    maskImage = filter!.outputImage
                }
            }
            
            let composite = CIFilter(name: "CIBlendWithMask")
            composite!.setValue(pixelateFiler!.outputImage, forKey: kCIInputImageKey)
            composite!.setValue(cii, forKey: kCIInputBackgroundImageKey)
            composite!.setValue(maskImage, forKey: kCIInputMaskImageKey)
            
            cgi = context.createCGImage(composite!.outputImage!, from: composite!.outputImage!.extent)
           // cgi = context.createCGImage(pixelateFiler!.outputImage!, from: composite!.outputImage!.extent)
        }
        
        return cgi
    }
    
    public func maskFaces(cii:CIImage) -> CGImage? {
        let faceDetector = CIDetector(ofType: CIDetectorTypeFace, context: nil, options: [CIDetectorAccuracy : CIDetectorAccuracyHigh])
        let features = faceDetector?.features(in: cii)
        
        var cgi:CGImage?
        if features != nil {
            var maskImage: CIImage?
            let pixelateFiler = CIFilter(name: "CIPixellate")
            pixelateFiler!.setValue(cii, forKey: kCIInputImageKey)
            let inputScaleKey = max(cii.extent.width, cii.extent.height) / 60.0
            pixelateFiler!.setValue(inputScaleKey, forKey: kCIInputScaleKey)
            
            for feature in features! as [CIFeature] {
                print("Found a face")
                
                let centerX = feature.bounds.origin.x + feature.bounds.size.width / 2.0
                let centerY = feature.bounds.origin.y + feature.bounds.size.height / 2.0
                let radius = min(feature.bounds.size.width, feature.bounds.size.height) / 1.5
                
                let radialGradient = CIFilter(name: "CIRadialGradient")
                radialGradient!.setValue(radius, forKey: "inputRadius0")
                radialGradient!.setValue(radius + 1, forKey: "inputRadius1")
                radialGradient!.setValue(CIColor(red: 0, green: 1, blue: 0, alpha: 1), forKey: "inputColor0")
                radialGradient!.setValue(CIColor(red: 0, green: 0, blue: 0, alpha: 0), forKey: "inputColor1")
                radialGradient!.setValue(CIVector(x: centerX, y: centerY), forKey: kCIInputCenterKey)
                
                let circleImage = radialGradient!.outputImage!.cropped(to: cii.extent)
                
                if (maskImage == nil) {
                    maskImage = circleImage
                } else {
                    let filter =  CIFilter(name: "CISourceOverCompositing")
                    filter!.setValue(circleImage, forKey: kCIInputImageKey)
                    filter!.setValue(maskImage, forKey: kCIInputBackgroundImageKey)
                    
                    maskImage = filter!.outputImage
                }
            }
            
            let composite = CIFilter(name: "CIBlendWithMask")
            composite!.setValue(pixelateFiler!.outputImage, forKey: kCIInputImageKey)
            composite!.setValue(cii, forKey: kCIInputBackgroundImageKey)
            composite!.setValue(maskImage, forKey: kCIInputMaskImageKey)
            
            cgi = context.createCGImage(composite!.outputImage!, from: composite!.outputImage!.extent)
        }
        
        return cgi
    }
    
    public func ciImage(from buffer: CMSampleBuffer) -> CIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) else { return nil }
        let cii = CIImage(cvPixelBuffer: pixelBuffer)
        return cii;
    }
    
    public func ciImage(from cgi:CGImage) -> CIImage? {
        return CIImage(cgImage: cgi)
    }
    
    public func cgImage(from cii : CIImage) -> CGImage? {
        return context.createCGImage(cii, from: cii.extent)
    }
    
    public func uiImage(from cgi : CGImage) -> UIImage {
        return UIImage(cgImage: cgi);
    }
    
    func buffer(from image : CGImage) -> CVPixelBuffer? {
        let frameSize = CGSize(width: image.width, height: image.height)
        var newPixelBuffer:CVPixelBuffer? = nil
        let status = CVPixelBufferCreate(kCFAllocatorDefault, Int(frameSize.width), Int(frameSize.height), kCVPixelFormatType_32ARGB , nil, &newPixelBuffer)
        if status != kCVReturnSuccess { return nil }
        
        CVPixelBufferLockBaseAddress(newPixelBuffer!, CVPixelBufferLockFlags.init(rawValue: 0))
        let data = CVPixelBufferGetBaseAddress(newPixelBuffer!)
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)
        let context = CGContext(data: data, width: Int(frameSize.width), height: Int(frameSize.height), bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(newPixelBuffer!), space: rgbColorSpace, bitmapInfo: bitmapInfo.rawValue)
        context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return newPixelBuffer
    }
    
    public func updateGuidePos(xPos x:Int, yPos y:Int) {
        self.guidingInProgress = true;
        self.gxPos = x;
        self.gyPos = y;
    }
    
    public func stopGuidance() {
        self.guidingInProgress = false;
    }
    
    public func endGuidance() {
        self.annotations = Array<VideoCircularAnnotation>()
        self.lineCoordinates.removeAll()
    }
    
  public func annotate(xPos x:Int, yPos y:Int,widget:WIdget,color:UIColor) {
      self.annotations.append(VideoCircularAnnotation(
          x: x, y: y,widget:widget, color: color
      ))
  }
    
  public func drawFreeHand(xPos x: Int, yPos y: Int, draw: Bool,color:UIColor) {
      //if x=0,y=0 and draw is false, we do not need to append it on the array because when the mouse press is lifted it is sending x=0.y=0 and draw false.
      if x == 0  && y == 0 && !draw {
        return
      }
          self.lineCoordinates.append(LineCoordinates(x: x, y: y, draw: draw,color:color))
 }

  
    public func requestTap() {
        bTapRequested = true
    }
    
  public func toggleFreeze(shouldFreeze: Bool) {
        isFrozen = shouldFreeze
        
        if isFrozen == false {
            frozenImage = nil
        }
    }
    
    public func togglePause() {
        isPaused = !isPaused
    }
  
    public func updateSelectedWidget(widget: WIdget) {
      selectedWidget = widget
    }
    
    public func releaseCapture() {}
    
    func videSettingsUpdated() {
        bTapEnabled = Utils.getVideoSettings().onTapStream
        bMaskFaces = Utils.getVideoSettings().faceMask
        bMaskDisplays = Utils.getVideoSettings().displayMask
    }
}
