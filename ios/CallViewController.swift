//
//  CallViewController.swift
//  BridgingDemo
//
//  Created by Adil Mir on 03/07/21.
//

import UIKit
import OpenTok
import ARKit

class CallViewController: UIViewController,  VideoCapturerDelegate {
  
  @IBOutlet weak var callVideoContainer: UIView!
  @IBOutlet weak var callVideoActions: UIStackView!
  @IBOutlet weak var muteMicButton: UIButton!
  @IBOutlet weak var switchCamera: UIButton!
  @IBOutlet weak var stopVideoButton: UIButton!
  @IBOutlet weak var faceMaskButton: UIButton!
  @IBOutlet weak var faceMaskView: UIView!
  @IBOutlet weak var micView: UIView!
  @IBOutlet weak var freezeView: UIView!
  @IBOutlet weak var reconnectingView: UIView!
  @IBOutlet weak var activityIndicatorView: UIActivityIndicatorView!
  
  var kApiKey = ""
  var kSessionId = ""
  var kToken = ""
  var mute = true
  
  var session: OTSession?
  var publisher: OTPublisher?
  var subscriber: OTSubscriber?
  var capturer: VideoCapturer?
  var callId:String?
  var sceneView:ARSCNView?
  var isCallActive: ((_ callStatus:Bool)-> Void)?
  override func viewDidLoad() {
      super.viewDidLoad()
      setCamera()
      NotificationCenter.default.addObserver(self, selector: #selector(videoSettingsUpdated), name: .videoSettingsChanged, object: nil)
      getSessionDetails()
      switchCamera.isSelected = false
      faceMaskButton.isSelected = false
      muteMicButton.isSelected = false
      stopVideoButton.isSelected = false
      reconnectingView.layer.cornerRadius = 8
  }
  
  override func viewWillAppear(_ animated: Bool) {
      super.viewWillAppear(animated)
      self.navigationController?.navigationBar.isHidden = true
    isCallActive?(true)
  }
  
  override func viewWillDisappear(_ animated: Bool) {
      super.viewWillDisappear(animated)
      
      // Pause the view's session
      if sceneView != nil {
          sceneView?.session.pause()
      }
  }
  
  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
//        if let touch = touches.first {
//            let currentPoint = touch.location(in: publisher?.view)
//            print(currentPoint)
//            let details = SignalData(x: Int(currentPoint.x), y: Int(currentPoint.y), type: "mh")
//            let data = try! JSONEncoder().encode(details)
//            let dataString = String(data: data, encoding: .utf8)
//            p
  }
  
  override func viewDidAppear(_ animated: Bool) {
      super.viewDidAppear(animated)
  }
  
  func setCamera() {
      Utils.updateVideoSettings(videoSettings: VideoSettings())
      let settings = OTPublisherSettings()
      settings.name = UIDevice.current.name
  
      guard let publisher = OTPublisher(delegate: self, settings: settings) else {
          return
      }
      
      // !!!!! NOT SURE WHY THS IS REQUIRED EVEN WHEN THERE IS CUSTOM CAPTURER IS SET !!!!!
     self.publisher = publisher
      publisher.cameraPosition = AVCaptureDevice.Position.back;
    self.publisher?.viewScaleBehavior = OTVideoViewScaleBehavior.fit
    
      capturer = getCapturer()
      publisher.videoCapture = (capturer as! OTVideoCapture)
      guard let publisherView = publisher.view else {
          return
      }
  
      if sceneView == nil {
        publisherView.frame = UIScreen.main.bounds
        callVideoContainer.insertSubview(publisherView, at: 0)
      }
  }
  
  //MARK:-  Button Actions
  
  @IBAction func showHideCamera(_ sender: UIButton, forEvent event: UIEvent) {
      stopVideoButton.isSelected = !sender.isSelected
      stopVideoButton.isSelected ? (freezeView.alpha = 1) : (freezeView.alpha = 0.5)
    capturer?.toggleFreeze(shouldFreeze:!sender.isSelected)
  }
  
  @IBAction func leaveCall(_ sender: UIButton, forEvent event: UIEvent) {
      cleanupBeforeLeavingCall()
      self.dismiss(animated: true, completion: nil)
  }
  
  @IBAction func toggleFreeze(_ sender: UIButton, forEvent event: UIEvent) {
    if let capturer = publisher?.videoCapture as? CustomVideCapturer {
      let currrentVideo = Utils.getVideoSettings()
      Utils.updateVideoSettings(videoSettings: VideoSettings())
      let _ = capturer.toggleCameraPosition()
      Utils.updateVideoSettings(videoSettings: currrentVideo)
    }
  }

  @IBAction func requestTap(_ sender: UIButton, forEvent event: UIEvent) {
      capturer?.requestTap()
  }
  
  @IBAction func toggleFaceMask(sender:UIButton) {
      faceMaskButton.isSelected = !sender.isSelected
      if faceMaskButton.isSelected {
          faceMaskView.alpha = 1
      } else {
          faceMaskView.alpha = 0.35
      }
      var videoSettings = Utils.getVideoSettings()
      videoSettings.faceMask = !videoSettings.faceMask
      videoSettings.displayMask = !videoSettings.displayMask
      Utils.updateVideoSettings(videoSettings: videoSettings)
      
  }
  
  @IBAction func muteMicAction(_ sender: UIButton) {
    if publisher != nil {
      publisher?.publishAudio = !(publisher?.publishAudio ?? false)
      muteMicButton.isSelected = !sender.isSelected
      updateMicView()
    }
  }
  
  @objc func videoSettingsUpdated() {
      capturer?.videSettingsUpdated()
  }
  
  func updateMicView() {
    if !(publisher?.publishAudio ?? false) {
        micView.alpha = 1
    } else {
        micView.alpha = 0.5
    }
  }
  
  func cleanupBeforeLeavingCall() {
    isCallActive?(false)
      capturer?.releaseCapture()
      
      var error: OTError?
      session?.disconnect(&error)
  }
  
  public func initialize(callId:String,muteCall:Bool) {
      self.callId = callId
      self.mute = muteCall
  }
  
  func getSessionDetails() {
      Backend().joinSession(callId: callId!) { (result,success,message)  in
          if let session = result, success {
              self.kApiKey = session.apiKey
              self.kSessionId = session.sessionId;
              self.kToken = session.token
              self.connectToAnOpenTokSession()
          } else {
              self.alert(errorMessage: message) {
                  self.cleanupBeforeLeavingCall()
                  self.dismiss(animated: true, completion: nil)
              }
          }
      }
  }
  
  func alert(errorMessage:String,completion: (() -> Void)? = nil) {
      DispatchQueue.main.async {
          let alertBox = UIAlertController(title: "ERROR", message: errorMessage, preferredStyle: UIAlertController.Style.alert)
          alertBox.addAction(UIAlertAction(title: "OK", style: .default, handler: { (action: UIAlertAction!) in
              alertBox.dismiss(animated: true, completion: nil)
              completion?()
          }))
          self.present(alertBox, animated: true, completion: nil)
      }
  }
  
  func connectToAnOpenTokSession() {
      session = OTSession(apiKey: kApiKey, sessionId: kSessionId, delegate: self)
      var error: OTError?
      session?.connect(withToken: kToken, error: &error)
      if error != nil {
          print(error!)
      }
  }
  
  func sendSifnal(type:String, message: String) {
      
      guard let s = subscriber else { return }
      
      session?.signal(withType: type, string: message, connection: s.stream?.connection, error: nil)
  }
  
  func sendMessage(type:String, message:String) {
      print("Type = \(type) Message=\(message)")
      
      guard let s = subscriber else { return }
      
      session?.signal(withType: type, string: message, connection: s.stream?.connection, error: nil)
  }
}

// MARK: - OTSessionDelegate callbacks
extension CallViewController: OTSessionDelegate {
  
  func sessionDidConnect(_ session: OTSession) {
    print("The client connected to the OpenTok session.")
    var error: OTError?
    publisher?.publishAudio = !mute
    muteMicButton.isSelected = true
    updateMicView()
    session.publish(self.publisher!, error: &error)
    guard error == nil else {
      print(error!)
      return
    }
  }
  
  func getCapturer() -> VideoCapturer {
    var c:VideoCapturer?
    c = CustomVideCapturer(vcDelegate: self)
    /*sceneView = ARSCNView()
     let scene = SCNScene(named: "art.scnassets/ship.dataset/ship.scn")!
     sceneView?.scene = scene
     
     sceneView?.frame = callVideoContainer.bounds
     callVideoContainer.insertSubview(sceneView!, at: 0)
     c = SCNViewVideoCapture(sceneView: sceneView!)
     
     let configuration = ARWorldTrackingConfiguration()
     sceneView?.session.run(configuration)*/
    return c!
  }
  
  func sessionDidDisconnect(_ session: OTSession) {
    reconnectingView.isHidden = true
    activityIndicatorView.stopAnimating()
    cleanupBeforeLeavingCall()
    print("The client disconnected from the OpenTok session.")
  }
  
  func session(_ session: OTSession, didFailWithError error: OTError) {
    print("The client failed to connect to the OpenTok session: \(error).")
  }
  
  func session(_ session: OTSession, connectionDestroyed connection: OTConnection) {
    cleanupBeforeLeavingCall()
    self.dismiss(animated: true, completion: nil)
  }
  
  func sessionDidBeginReconnecting(_ session: OTSession) {
    reconnectingView.isHidden = false
    activityIndicatorView.startAnimating()
  }
  
  func sessionDidReconnect(_ session: OTSession) {
    reconnectingView.isHidden = true
    activityIndicatorView.stopAnimating()
  }
  
  func session(_ session: OTSession, streamCreated stream: OTStream) {
    print("A stream was created in the session.")
    
    subscriber = OTSubscriber(stream: stream, delegate: self)
    guard let subscriber = subscriber else {
      return
    }
    
    var error: OTError?
    session.subscribe(subscriber, error: &error)
    guard error == nil else {
      print(error!)
      return
    }
    
    guard let subscriberView = subscriber.view else {
      return
    }
    
    let screenBounds = UIScreen.main.bounds
    subscriberView.frame = CGRect(x: screenBounds.width - 100 - 20, y: screenBounds.height - 120 - 120, width: 100, height: 120)
    subscriberView.layer.cornerRadius = 8.0
    subscriberView.clipsToBounds = true
    view.addSubview(subscriberView)
  }
  
  func session(_ session: OTSession, streamDestroyed stream: OTStream) {
    print("A stream was destroyed in the session.")
  }
  
  func session(_ session: OTSession, receivedSignalType type: String?, from connection: OTConnection?, with string: String?) {
    print(string!)
    let data: Data? = string!.data(using: .utf8)
    let signalData: SignalData = try! JSONDecoder().decode(SignalData.self, from: data!)
    let color  = UIColor(hexString: signalData.color ?? "#FFFF00")
    if signalData.type == "mh" {
      print(signalData.x!,signalData.y!)
      capturer?.updateGuidePos(xPos: signalData.x!, yPos: signalData.y!)
    } else if signalData.type == "mo" {
      capturer?.stopGuidance()
    } else if signalData.type == "mc" {
      if signalData.flag ?? false {
        capturer?.annotate(xPos: signalData.x!, yPos: signalData.y!, widget: WIdget(rawValue: signalData.widget ?? "") ?? .circle,color:color)
      }
    } else if signalData.type == "eg" {
      capturer?.toggleFreeze(shouldFreeze: false)
      capturer?.endGuidance()
    } else if signalData.type == "sg" {
      capturer?.toggleFreeze(shouldFreeze: true)
    } else if signalData.type == "md" {
      if let xPos = signalData.x, let yPos = signalData.y {
        capturer?.updateGuidePos(xPos: signalData.x!, yPos: signalData.y!)
        capturer?.drawFreeHand(xPos: xPos, yPos: yPos, draw: signalData.flag ?? false,color: color)
      }
    }  else if signalData.type == "mp" {
      capturer?.updateGuidePos(xPos: signalData.x!, yPos: signalData.y!)
      if let xPos = signalData.x, let yPos = signalData.y {
        capturer?.drawFreeHand(xPos: xPos, yPos: yPos, draw: false,color: color)
      }
    } else if signalData.type == "wc" {
      capturer?.updateSelectedWidget(widget : WIdget(rawValue: signalData.widget ?? "") ?? .pencil)
    }
  }
}

// MARK: - OTPublisherDelegate callbacks
extension CallViewController: OTPublisherDelegate,OTPublisherKitNetworkStatsDelegate {
   func publisher(_ publisher: OTPublisherKit, didFailWithError error: OTError) {
       print("The publisher failed: \(error)")
   }
  
  func publisher(_ publisher: OTPublisherKit, videoNetworkStatsUpdated stats: [OTPublisherKitVideoNetworkStats]) {
    print("Call")
  }
  
}

// MARK: - OTSubscriberDelegate callbacks
extension CallViewController: OTSubscriberDelegate {
   public func subscriberDidConnect(toStream subscriber: OTSubscriberKit) {
       print("The subscriber did connect to the stream.")
    NotificationCenter.default.post(name: NSNotification.Name("event-emitted"), object: nil)
   }

   public func subscriber(_ subscriber: OTSubscriberKit, didFailWithError error: OTError) {
       print("The subscriber failed to connect to the stream.")
   }
}

struct SignalData : Codable{
    var x: Int?
    var y: Int?
    var type: String
    var flag: Bool?
    var widget: String?
    var color: String?
}

extension Notification.Name {
  
    static var videoSettingsChanged:Notification.Name {
        return .init("videoSettingsChanged")
    }
}

class Utils {
  public static func updateVideoSettings(videoSettings:VideoSettings) {
      let encoder = JSONEncoder()
      if let encodedObject = try? encoder.encode(videoSettings){
          UserDefaults.standard.set(encodedObject, forKey: UserDefaultKeys.VIDEO_SETTINGS)
          NotificationCenter.default.post(name: Notification.Name.videoSettingsChanged, object: nil)
      }
  }
  
  public static func getVideoSettings() -> VideoSettings {
      if let videoSettings = UserDefaults.standard.object(forKey: UserDefaultKeys.VIDEO_SETTINGS) as? Data {
          let decoder = JSONDecoder()
          if let decodedVideSettings = try? decoder.decode(VideoSettings.self, from: videoSettings) {
              return decodedVideSettings
          }
      }
      return VideoSettings()
  }
}

public struct VideoSettings : Codable{
    var faceMask = false
    var displayMask = false
    var onTapStream = false
}

public struct UserDefaultKeys {
    public static let VIDEO_SETTINGS = "VideoSettings"
}

public enum WIdget: String {
  case square
  case circle
  case cursor
  case pencil
}
