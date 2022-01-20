@objc(VideoPackage)
class VideoPackage: NSObject {
    var callActive = false
    @objc(multiply:withB:withResolver:withRejecter:)
    func multiply(a: Float, b: Float, resolve:RCTPromiseResolveBlock,reject:RCTPromiseRejectBlock) -> Void {
        resolve(a*b)
    }
   
   
    @objc func loadCallViewController(_ callId:NSString, mute:Bool) {
      DispatchQueue.main.async {
        let controller = UIStoryboard(name: "VideoCall", bundle: Bundle._module).instantiateViewController(withIdentifier: "CallViewController") as! CallViewController
        controller.modalPresentationStyle = .overCurrentContext
        controller.initialize(callId: callId as String, muteCall: mute)
       // controller.isCallActive = //self.updateIsCallActive(isCallActive:)
        if let topController = UIApplication.topViewController() {
          if topController.isKind(of: UIAlertController.self) || topController.isKind(of: CallViewController.self) {
            topController.dismiss(animated: true) {
              UIApplication.topViewController()?.present(controller, animated: true, completion: nil)
            }
          } else {
            UIApplication.topViewController()?.present(controller, animated: true, completion: nil)
          }
        }
      }
    }
  //Load video call contoller
  public class func loadCall(_ callId:NSString, mute:Bool) {
          DispatchQueue.main.async {
  //            let frameworkBundle = Bundle(for: LoadController.self)
  //            let bundleURL = frameworkBundle.resourceURL?.appendingPathComponent("VideoPod.bundle")
  //            let resourceBundle = Bundle(url: bundleURL!)
              let controller = UIStoryboard(name: "VideoCall", bundle: Bundle._module).instantiateViewController(withIdentifier: "CallViewController") as! CallViewController
            controller.modalPresentationStyle = .overCurrentContext
            controller.initialize(callId: callId as String, muteCall: mute)
           // controller.isCallActive = //self.updateIsCallActive(isCallActive:)
            if let topController = UIApplication.topViewController() {
              if topController.isKind(of: UIAlertController.self) || topController.isKind(of: CallViewController.self) {
                topController.dismiss(animated: true) {
                  UIApplication.topViewController()?.present(controller, animated: true, completion: nil)
                }
              } else {
                UIApplication.topViewController()?.present(controller, animated: true, completion: nil)
              }
            }
          }
        }
      
    
    //If you want to handle universal link via App Delegate use this method.
    @objc public func updateFromUserActivity(_ userActivity:NSUserActivity) {
      print(userActivity.activityType)
      
      if userActivity.activityType == NSUserActivityTypeBrowsingWeb{
        guard let url = userActivity.webpageURL else { return }
        print(url)
        
        let path = url.relativePath
        print(path)
        
        if path.starts(with: "/j") {
          let cid = url.lastPathComponent
          
          if !cid.isEmpty && cid.count >= 8 {
            print(cid)
            LoadVideoController().loadCallViewController(NSString(string: cid), mute: true)
          }
        }
      }
    }
    
    //Get the status whether call is active or not
    @objc(isCallActive:rejecter:)
    func isCallActive(_ resolve: RCTPromiseResolveBlock, rejecter reject:RCTPromiseRejectBlock) -> Void {
      resolve(callActive)
    }

    func updateIsCallActive(isCallActive:Bool) {
      callActive = isCallActive
    }

    @objc func callStarted(_ callback: RCTResponseSenderBlock) {
      callback(nil)
    }
  }
