//
//  LoginViewController.swift
//  LiveMap
//
//  Created by 默司 on 2016/10/18.
//  Copyright © 2016年 默司. All rights reserved.
//

import UIKit
import FirebaseAuth
import MapKit
import CoreLocation
import Kingfisher
import SocketIO
import SwiftyJSON

class MapViewController: UIViewController, CLLocationManagerDelegate, MKMapViewDelegate {

    @IBOutlet var mapview: MKMapView!
    
    let locationManager = CLLocationManager()
    
    var initialized: Bool = false
    var annotations: [String: UserAnnotation]!
    
    var user: FIRUser!
    var socket: SocketIOClient!
    
    var alert: UIAlertController?
    var currentSid: String!
    
    // MARK: Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        //user
        self.user = FIRAuth.auth()!.currentUser!
        
        //socket
        self.socket = API.shared.sharedSocket()!
        self.listenSocket()
        
        //設定 MapView
        self.mapview.showsUserLocation = false
        self.mapview.delegate = self
        
        //設定 Location Manager
        self.locationManager.activityType = .fitness
        self.locationManager.delegate = self
        
        self.locationManager.requestWhenInUseAuthorization()
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        //連線
        self.socket.connect()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        try? FIRAuth.auth()?.signOut()
        
        self.socket.disconnect()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    // MARK: Delegates
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        
        guard let location = locations.first else {
            return
        }
        
        if !initialized {
            self.mapview.region = MKCoordinateRegionMakeWithDistance(location.coordinate, 10000, 10000)
            initialized = true
        }
        
        //send broadcast
        print("emit", "update")
        self.socket.emit("update", [
            "location": ["coordinates": [location.coordinate.longitude, location.coordinate.latitude]]
        ])
        
    }
    
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        
        guard let annotation = annotation as? UserAnnotation else {
            return nil
        }
        
        if let view = mapView.dequeueReusableAnnotationView(withIdentifier: annotation.sid) {
            return view
        } else {
            let view = UserAnnotationView(annotation: annotation, reuseIdentifier: annotation.sid)
            
            return view
        }
    }
    
    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        print("select")
        //mapView.deselectAnnotation(view.annotation, animated: true)
    }
    
    // MARK: Actions
    
    ///
    /// # Socket Lifecycle
    ///
    func listenSocket() {
        
        self.socket.on("welcome", callback: {[unowned self] (data, _) in
            
            let root = JSON(data[0]);
            
            self.currentSid = root["sid"].stringValue
            self.annotations = [String: UserAnnotation]()
            self.mapview.removeAnnotations(self.mapview.annotations)
            
            if let list = root["list"].array {
                print(list)
                
                for item in list {
                    self.createAnnotation(withData: item)
                }
            }
            
            //Alert 初始化
            self.alert?.dismiss(animated: true, completion: nil)
            self.alert = nil
            
            //開始更新定位
            self.locationManager.startUpdatingLocation()
        })
        
        //有人加入
        self.socket.on("join", callback: {[unowned self] (data, _) in
            self.createAnnotation(withData: JSON(data[0]))
        })
        
        //更新資料
        self.socket.on("update", callback: {[unowned self] (data, _) in
            if (data.count > 1) {
                let count = JSON(data[1])["count"].intValue
                
                if count != self.annotations.count {
                    print("refresh list", count, self.annotations.count)
                    self.socket.emit("refresh")
                }
            }
            
            self.updateAnnotation(data: JSON(data[0]))
        })
        
        //重新取回使用者列表
        self.socket.on("refresh", callback:  {[unowned self] (data, _) in
            let root = JSON(data[0])
            
            self.annotations = [String: UserAnnotation]()
            self.mapview.removeAnnotations(self.mapview.annotations)
            
            if let list = root["list"].array {
                for item in list {
                    self.createAnnotation(withData: item)
                }
            }
        })
        
        //被踢除
        //self.socket.on("kick", callback: {[unowned self] (_, _) in})
        
        //發生錯誤
        self.socket.on("error", callback: {[unowned self] (_, _) in
            self.leave(self.currentSid)
            self.createErrorAlert()
        })
        
        //有人離開，不包含自己
        self.socket.on("leave", callback: {[unowned self] (data, _) in
            let sid = JSON(data[0])["sid"].stringValue
            self.leave(sid)
        })
        
        self.socket.onAny({ (event) in
            print(event.event)
        })
    }
    
    func createErrorAlert() {
        guard self.alert == nil else {
            return
        }
        
        let alert = UIAlertController(title: "連線發生錯誤", message: "是否要離開？", preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: "等待", style: .cancel, handler: {[unowned self] (_) in
            DispatchQueue(label: "waiting").asyncAfter(deadline: .now() + 5, execute: {
                self.alert = nil
            })
        }))
        
        alert.addAction(UIAlertAction(title: "離開", style: .default, handler: {[unowned self] (_) in
            let _ = self.navigationController?.popViewController(animated: true)
        }))
        
        self.present(alert, animated: true, completion: nil)
        self.alert = alert
    }
    
    func createAnnotation(withData data: JSON) {
        print(data)
        
        guard let sid = data["sid"].string else {
            return
        }
        
        guard self.annotations[sid] == nil else {
            print("annotation is exists. ", sid == self.currentSid)
            return
        }
        
        let displayName = data["displayName"].stringValue
        let avatar = data["avatar"].stringValue
        let coordinates = data["location"]["coordinates"]
        let coord = CLLocationCoordinate2D(latitude: coordinates[1].doubleValue, longitude: coordinates[0].doubleValue)
        
        let annotation = UserAnnotation(sid: sid, displayName: displayName, avatar: avatar, coordinate: coord)
        
        self.annotations[sid] = annotation
        self.mapview.addAnnotation(annotation)
    }
    
    func updateAnnotation(data: JSON) {
        guard let sid = data["sid"].string else {
            fatalError("sid is required")
        }
        
        guard let annotation = self.annotations[sid] else {
            print("cannot find annotation with sid")
            return
        }
        
        let displayName = data["displayName"].string
        let avatar = data["avatar"].string
        let coordinates = data["location"]["coordinates"]
        let coord = CLLocationCoordinate2D(latitude: coordinates[1].doubleValue, longitude: coordinates[0].doubleValue)
        
        if let displayName = displayName {
            annotation.displayName = displayName
        }
        
        if let avatar = avatar {
            annotation.avatar = avatar
        }
        
        UIView.animate(withDuration: 0.3) {
            annotation.coordinate = coord
        }
    }
    
    func leave(_ sid: String?) {
        guard let sid = sid else {
            return
        }
        
        if let annotation = self.annotations[sid] {
            mapview.removeAnnotation(annotation);
        }
        
        if let index = self.annotations.keys.index(of: sid) {
            self.annotations.remove(at: index)
        }
    }
    
    ///
    /// # 顯示設定畫面
    ///
    func showSettingsView() {
        //TODO: Show setting view
    }
}

class UserAnnotation: NSObject, MKAnnotation {
    var sid: String
    var displayName: String
    var lastMessage: String?
    
    var avatar: String? {
        didSet {
            if(self.avatar != oldValue) {
                delegate?.didAvatarUpdata(self.avatar)
            }
        }
    }
    
    weak var delegate: UserAnnotationDelegate?
    
    var title: String? {
        return displayName
    }
    
    var subtitle: String? {
        return lastMessage
    }
    
    dynamic var coordinate: CLLocationCoordinate2D
    
    required init(sid: String, displayName: String, avatar: String, coordinate: CLLocationCoordinate2D) {
        self.sid = sid
        self.displayName = displayName
        self.avatar = avatar
        
        self.coordinate = coordinate
        
        super.init()
    }
}

protocol UserAnnotationDelegate: class {
    func didAvatarUpdata(_ avatar: String?)
}

class UserAnnotationView: MKAnnotationView, UserAnnotationDelegate {
    var imageView: UIImageView!
    
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        
        guard let annotation = annotation as? UserAnnotation  else {
            return
        }
        
        annotation.delegate = self
        
        self.backgroundColor = UIColor.white
        self.frame = CGRect(x: 0, y: 0, width: 40, height: 40)
        self.layer.cornerRadius = self.frame.width / 2
        
        self.imageView = UIImageView()
        self.imageView.frame = self.frame.insetBy(dx: 3, dy: 3)
        self.imageView.contentMode = .scaleAspectFill
        self.imageView.layer.cornerRadius = self.imageView.frame.width / 2
        self.imageView.clipsToBounds = true
        
        self.addSubview(self.imageView)
        self.imageView.center = self.center
        
        if let url = annotation.avatar {
            self.imageView.kf.setImage(with: URL(string: url))
        } else {
            self.imageView.kf.setImage(with: URL(string: "https://mc-heads.net/avatar/\(annotation.sid)/100.png"))
        }
        
        self.canShowCallout = true
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    func didAvatarUpdata(_ avatar: String?) {
        if let url = avatar {
            self.imageView.kf.setImage(with: URL(string: url))
        }
    }
}
