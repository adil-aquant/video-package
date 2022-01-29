//
//  COMPONENTEXTENSION.swift
//  BridgingDemo
//
//  Created by Adil Mir on 03/07/21.
//

import Foundation
import UIKit
extension UIImage {
    func rotate(by degrees: CGFloat) -> UIImage {

        let orientation = CGImagePropertyOrientation(rawValue: UInt32(self.imageOrientation.rawValue))
        
        // Create CIImage respecting image's orientation
        guard let inputImage = CIImage(image: self)?.oriented(orientation!)
            else { return self }

        // Rotate the image itself
        let rotation = CGAffineTransform(rotationAngle: (degrees * CGFloat.pi / 180))
        let outputImage = inputImage.transformed(by: rotation)

        // Create CGImage first
        guard let cgImage = CIContext().createCGImage(outputImage, from: outputImage.extent)
            else { return self }

        // Create output UIImage from CGImage
        return UIImage(cgImage: cgImage)
    }
}


extension UIApplication {
    
    internal class func topViewController(_ base: UIViewController? = UIApplication.shared.keyWindow?.rootViewController) -> UIViewController? {
        
        if let nav = base as? UINavigationController {
            return topViewController(nav.visibleViewController)
        }
        
        if let tab = base as? UITabBarController {
            let moreNavigationController = tab.moreNavigationController
            
            if let top = moreNavigationController.topViewController, top.view.window != nil {
                return topViewController(top)
            } else if let selected = tab.selectedViewController {
                return topViewController(selected)
            }
        }
        
        if let presented = base?.presentedViewController {
            return topViewController(presented)
        }
        
        return base
    }
}

extension UIColor {
  
    convenience init(hexString: String, alpha: CGFloat = 1.0) {
        let hexString: String = hexString.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let scanner = Scanner(string: hexString)
        if (hexString.hasPrefix("#")) {
            scanner.scanLocation = 1
        }
        var color: UInt64 = 0
        scanner.scanHexInt64(&color)
        let mask = 0x000000FF
        let r = Int(color >> 16) & mask
        let g = Int(color >> 8) & mask
        let b = Int(color) & mask
        let red   = CGFloat(r) / 255.0
        let green = CGFloat(g) / 255.0
        let blue  = CGFloat(b) / 255.0
        self.init(red:red, green:green, blue:blue, alpha:alpha)
    }
    
    func toHexString() -> String {
        var r:CGFloat = 0
        var g:CGFloat = 0
        var b:CGFloat = 0
        var a:CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        let rgb:Int = (Int)(r*255)<<16 | (Int)(g*255)<<8 | (Int)(b*255)<<0
        return String(format:"#%06x", rgb)
    }
}

extension UIAlertController {
    class func showErrorAlert(errorMessage:String,completion: (() -> Void)? = nil) {
        DispatchQueue.main.async {
            let alertBox = UIAlertController(title: "ERROR", message: errorMessage, preferredStyle: UIAlertController.Style.alert)
            alertBox.addAction(UIAlertAction(title: "OK", style: .default, handler: { (action: UIAlertAction!) in
                alertBox.dismiss(animated: true, completion: nil)
                completion?()
            }))
            UIApplication.topViewController()?.present(alertBox, animated: true, completion: nil)
        }
    }
}
