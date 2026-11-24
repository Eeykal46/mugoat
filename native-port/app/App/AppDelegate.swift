import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Crash log for every crash, also before the game starts: the last run's file is kept as
        // crash-previous.log (Settings › Device › Share Logs sends both).
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let last = documents.appendingPathComponent("crash-last.log"), previous = documents.appendingPathComponent("crash-previous.log")
        if let size = (try? FileManager.default.attributesOfItem(atPath: last.path))?[.size] as? NSNumber, size.intValue > 0 {
            try? FileManager.default.removeItem(at: previous)
            try? FileManager.default.moveItem(at: last, to: previous)
        }
        PGInstallCrashLog(last.path)
        NSSetUncaughtExceptionHandler { exception in
            PGCrashLogLine("UNCAUGHT EXCEPTION: \(exception.name.rawValue): \(exception.reason ?? "")")
            for symbol in exception.callStackSymbols.prefix(40) { PGCrashLogLine(symbol) }
        }
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = NativePortViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}
