//
//  AppDelegate.swift
//  DTCamera
//
//  Created by Dan Jiang on 2019/9/16.
//  Copyright © 2019 Dan Jiang. All rights reserved.
//

import UIKit
import AVFoundation
import CocoaLumberjack
import DoraemonKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?


    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        if #available(iOS 10.0, *) {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            } catch {}
        }
        
        MediaViewController.theme = MediaCustomTheme()
        
        DDLog.add(DDTTYLogger.sharedInstance)

        let fileLogger = DDFileLogger() // File Logger
        fileLogger.rollingFrequency = 60 * 60 * 24 // 24 hours
        fileLogger.logFileManager.maximumNumberOfLogFiles = 7
        DDLog.add(fileLogger)
        
        DoraemonManager.shareInstance().install()

        return true
    }

}

