import UIKit
import Flutter
import ox_common

@main
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        OCXCrashManager.shared.appLaunched()
        OCXCrashManager.shared.continueCallback = {
            OXCLaunchCoordinator.shared.start(window: self.window)
        }
        if OCXCrashManager.shared.showCrashAlert {
            
            self.window?.rootViewController = UIViewController()
            self.window?.makeKeyAndVisible()
            
            OCXCrashManager.shared.showWarningDialog()
            return false
        }
        
        OXCLaunchCoordinator.shared.start(window: self.window)
        
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    override func applicationDidBecomeActive(_ application: UIApplication) {
        signal(SIGPIPE, SIG_IGN)
        UIApplication.shared.applicationIconBadgeNumber = 0
    }
    
    override func applicationWillEnterForeground(_ application: UIApplication) {
        signal(SIGPIPE, SIG_IGN)
    }
    
    // Handle Universal Links
    override func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        if userActivity.activityType == NSUserActivityTypeBrowsingWeb {
            if let url = userActivity.webpageURL {
                let userDefault = UserDefaults.standard
                userDefault.setValue(url.absoluteString, forKey: OPENURLAPP)
                userDefault.synchronize()
                return true
            }
        }
        return false
    }
    
    override func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        
        var urlStr = url.isFileURL ? AppGroupHelper.shareScheme : url.absoluteString
        
        if url.host == AppGroupHelper.shareHost {
            if var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: true) {
                var queryItems = (urlComponents.queryItems ?? [])
            
                if let text = AppGroupHelper.loadDataForGourp(forKey: AppGroupHelper.shareDataURLKey) as? String {
                    queryItems.append(URLQueryItem(name: "text", value: text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)))
                    queryItems.append(URLQueryItem(name: "type", value: "text"))
                    AppGroupHelper.saveDataForGourp(nil, forKey: AppGroupHelper.shareDataURLKey)
                } else if let path = AppGroupHelper.loadDataForGourp(forKey: AppGroupHelper.shareDataFilePathKey) as? String {
                    queryItems.append(URLQueryItem(name: "path", value: path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)))
                    queryItems.append(URLQueryItem(name: "type", value: Tools.getFileType(from: URL(fileURLWithPath: path))))
                    AppGroupHelper.saveDataForGourp(nil, forKey: AppGroupHelper.shareDataFilePathKey)
                }
                
                urlComponents.queryItems = queryItems
                urlStr = urlComponents.url?.absoluteString ?? urlStr
            }
        } else if url.isFileURL {
            if var urlComponents = URLComponents(string: urlStr) {
                var queryItems = (urlComponents.queryItems ?? [])
                queryItems.append(URLQueryItem(name: "path", value: url.path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)))
                queryItems.append(URLQueryItem(name: "type", value: Tools.getFileType(from: url)))
                
                urlComponents.queryItems = queryItems
                urlStr = urlComponents.url?.absoluteString ?? urlStr
            }
        } else {
            return true
        }
        
        let userDefault = UserDefaults.standard
        userDefault.setValue(urlStr, forKey: OPENURLAPP)
        userDefault.synchronize()
        
        return true
    }
}
