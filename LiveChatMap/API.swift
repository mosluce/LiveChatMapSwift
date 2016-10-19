//
//  API.swift
//  LiveMap
//
//  Created by 默司 on 2016/10/18.
//  Copyright © 2016年 默司. All rights reserved.
//

import UIKit
import SwiftyJSON
import SocketIO
import FirebaseAuth

class API: NSObject {
    static let shared = API();

    typealias APICompletion = (_ data: JSON?, _ response: HTTPURLResponse?, _ error: Error?) -> Void
    
    private let apiUrl = "https://livechat-map.herokuapp.com";
//    let apiUrl = "http://192.168.168.22:3000";
    
    private var firebaseToken: String?
    private var socket: SocketIOClient?
    
    func request(httpMethod: String, path: String, body: JSON?, completion: @escaping APICompletion) {
        let session = URLSession.shared
        var req = URLRequest(url: URL(string: apiUrl.appending(path))!);
        
        req.httpMethod = httpMethod;
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let body = body {
            req.httpBody = try? body.rawData()
        }
        
        session.dataTask(with: req) { (data, res, error) in
            if let data = data {
                completion(JSON(data: data), res as? HTTPURLResponse, error)
            } else {
                completion(nil, res as? HTTPURLResponse, error)
            }
        }.resume()
    }
    
    func sharedSocket(createNew: Bool = true) -> SocketIOClient? {
        guard self.socket == nil else {
            return self.socket
        }
        
        if !createNew {
            return nil
        }
        
        if let firebaseToken = self.firebaseToken, let url = URL(string: apiUrl) {
            let socket = SocketIOClient(socketURL: url, config: [.log(true), .forcePolling(true), .extraHeaders(["firebaseToken": firebaseToken])])
            self.socket = socket
            return socket
        } else {
            return nil
        }
    }
    
    func set(firebaseToken: String?) {
        self.firebaseToken = firebaseToken
    }
}
