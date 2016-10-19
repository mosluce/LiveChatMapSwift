//
//  ViewController.swift
//  LiveChatMap
//
//  Created by 默司 on 2016/10/19.
//  Copyright © 2016年 默司. All rights reserved.
//

import UIKit
import FirebaseAuth
import FirebaseAuthUI
import SVProgressHUD
import SDCAlertView

class ViewController: UIViewController, FIRAuthUIDelegate {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        self.navigationController?.navigationBar.tintColor = UIColor.white
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if let user = FIRAuth.auth()?.currentUser {
            SVProgressHUD.show(withStatus: "載入中...")
            user.getTokenForcingRefresh(true, completion: {[unowned self] (token, error) in
                SVProgressHUD.dismiss()
                
                if let error = error {
                    return self.didLoginFailure(error)
                }
                
                API.shared.set(firebaseToken: token)
                
                self.presentMapView()
            })
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        let logout = UIBarButtonItem()
        logout.title = "登出"
        self.navigationItem.backBarButtonItem = logout
        self.navigationItem.title = "聊天地圖"
    }
    
    func didLoginFailure(_ error: Error) {
        AlertController.alert(withTitle: "登入失敗")
    }
    
    func presentMapView() {
        self.performSegue(withIdentifier: "MapView", sender: self)
    }
    
    @IBAction func presentLoginView(_ sender: Any) {
        let authUI = FIRAuthUI.default()!
        authUI.delegate = self
        self.present(authUI.authViewController(), animated: true, completion: nil)
    }
    
    func authUI(_ authUI: FIRAuthUI, didSignInWith user: FIRUser?, error: Error?) {
        if let error = error {
            return didLoginFailure(error);
        }
    }
}

