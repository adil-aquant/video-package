//
//  Backend.swift
//  BridgingDemo
//
//  Created by Adil Mir on 03/07/21.
//

import Foundation
import UIKit

public class Backend {
    typealias completionHandler = ((Decodable?,Bool,NetworkError?)-> Void)
    
    // calculated logo variable cannot go into Dto since UIImage is not JSON decodable
    private static var logo:UIImage?
    public static func getLogo() -> UIImage? {
        guard let l = logo else {
            return nil
        }
        
        return l;
    }
    
    public func joinSession(callId:String, handleResult: @escaping (_ result:JoinSessionResponse?,_ success: Bool, _ message: String) -> Void) {
      let url:String = Constants.SERVER_URL + Constants.GUEST + Constants.JOIN_SESSION
        let request = JoinSessionRequest(callId: callId);
        
        self.doPost(urlString: url, token: nil, data: request, type: JoinSessionResponse.self) { (result, success, error) in
            DispatchQueue.main.async {
                handleResult(result as? JoinSessionResponse,success,error?.message ?? NetworkMessages.defaultMessage)
            }
        }
    }
  
  private func doPost<T: Decodable>(urlString:String, token:String?, data:Encodable, type:T.Type, handleResult: @escaping (completionHandler)) {
  
     //Validate the URL
      guard let requestUrl = URL(string: urlString) else { handleResult(nil,false,NetworkError.invalidUrl(NetworkMessages.invalidUrl))
          return
      }
      
      //Create a url requset
      var request = URLRequest(url: requestUrl)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Accept")
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      
      if token != nil {
          request.setValue("Bearer " + token!, forHTTPHeaderField: "Authorization")
      }
      
      let jsonData = data.toJSONData()
      request.httpBody = jsonData
      
      let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
          if let e = error {
              handleResult(nil,false,NetworkError.genericError(e.localizedDescription))
              return
          }
          
          let res = response as! HTTPURLResponse
          if res.statusCode == 500 {
              
              handleResult(nil,false,NetworkError.internalServerError(self.getMessageInCaseOfFailure(data: data) ?? NetworkMessages.internalServerError))
              print("Error 500!")
              return
          }
          
          if res.statusCode == 404 {
              handleResult(nil,false,NetworkError.noDataFound(self.getMessageInCaseOfFailure(data: data) ?? NetworkMessages.internalServerError))
              return
          }
          
          // Convert HTTP Response Data to a String
          if let d = data, let dataString = String(data: d, encoding: .utf8) {
              print("Response data string:\n \(dataString)")
              
              //Check whether we can decode the data
              do {
                  let result = try JSONDecoder().decode(type.self, from: d)
                  handleResult(result,true,nil)
              } catch let error {
                  print(error.localizedDescription)
                  handleResult(nil,false,NetworkError.couldNotDecodeTheData(NetworkMessages.invalidFormat))
              }
          }
      }
      task.resume()
  }
  
  private func getMessageInCaseOfFailure(data:Data?)-> String? {
      guard let data = data else {
        return nil
      }
      let dataString = String(data: data, encoding: .utf8)
      print(dataString)
      let errorModel = try! JSONDecoder().decode(NetworkErrorDto.self, from: data)
      return errorModel.error
      
  }
  
}

public struct JoinSessionRequest : Encodable {
    var callId: String
}

public struct JoinSessionResponse : Decodable {
    var message: String?
    var apiKey: String
    var sessionId: String
    var token: String
    var callId: String
}


public enum NetworkError: Error {
    case invalidUrl(String)
    case authorisationExpired(String)
    case noResponse(String)
    case genericError(String)
    case internalServerError(String)
    case noDataFound(String)
    case couldNotDecodeTheData(String)
    case noData(String)
    
    var message: String {
        switch self {
        case .invalidUrl(let message), .authorisationExpired(let message),.genericError(let message),.noResponse(let message),.internalServerError(let message),.couldNotDecodeTheData(let message),.noData(let message),.noDataFound(let message):
            return message
        }
    }
}

struct NetworkErrorDto : Decodable {
    let timestamp : String?
    let status : Int?
    let error : String?
    let message : String?
    let path : String?
}

public class Constants {
    public static let SERVER_URL1                     = "http://192.168.7.80:7070"
    public static let SERVER_URL2                     = "https://aq-smartcollab.herokuapp.com"
    public static let SERVER_URL                      = "https://video-triage-staging.herokuapp.com"//"https://servicehero-us-production.herokuapp.com"//"https://go.servicehero.ai"
    
    public static let JOIN_SESSION:String             = "/session/join"
    public static let GUEST:String                    = "/guest"
}

public struct NetworkMessages {
    public static let invalidUrl                 = "The resource you are trying to access is not available."
    public static let networkMesssage            = "A working Internet connection is required."
    public static let defaultMessage             = "Something went wrong please try after some time. If the problem persists, please contact our support team."
    public static let internalServerError        = "Internal Server Error."
    public static let deviceNotConnected         = "Your device is not connected to internet."
    public static let noResponseFromServer       = "No response from the server."
    public static let invalidFormat              = "The data could not be decoded because of invalid format."
    public static let authenticationFailed       = "Server couldn't find the authenticated request."
    public static let timout                     = "Connection timeout"
}
