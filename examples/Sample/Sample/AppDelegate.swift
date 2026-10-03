//
//  AppDelegate.swift
//
//  Copyright © 2016 Rivia Corp s.r.o.
//

import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow? = nil

    func applicationDidFinishLaunching(_: UIApplication) {
        if UserDefaults.standard.bool(forKey: "firstLaunch") == false {
            UserDefaults.standard.set(true, forKey: "firstLaunch")
            UserDefaults.standard.synchronize()
            let fileManager: FileManager = .default
            let fileNames: [String] = ["Image1.jpg", "Image2.jpg", "Image3.jpg", "Images.zip"]
            let documentsURL: URL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0] as URL
            let bundleURL: URL? = Bundle.main.resourceURL
            for file in fileNames {
                if let srcPath = bundleURL?.appendingPathComponent(file).path {
                    let toPath: String = documentsURL.appendingPathComponent(file).path
                    do {
                        try fileManager.copyItem(atPath: srcPath, toPath: toPath)
                    } catch {
                        // Bundled sample fixtures are best effort; keep launching if copying fails.
                    }
                }
            }
        }
    }

    func applicationWillResignActive(_: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of
        // temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the
        // application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should
        // use this method to pause the game.
    }

    func applicationDidEnterBackground(_: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application
        // state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate:
        // when the user quits.
    }

    func applicationWillEnterForeground(_: UIApplication) {
        // Called as part of the transition from the background to the inactive state; here you can undo many of the
        // changes made on entering the background.
    }

    func applicationDidBecomeActive(_: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the
        // application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillTerminate(_: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also
        // applicationDidEnterBackground:.
    }
}
