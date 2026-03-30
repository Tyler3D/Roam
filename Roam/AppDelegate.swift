import FirebaseCore
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Keep this idempotent in case lifecycle wiring changes.
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        return true
    }
}
