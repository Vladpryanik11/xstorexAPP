import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var flowController: AppFlowController?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene,
              let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }

        if isRunningUnitTests {
            // Под XCTest приложение-хост не ходит в сеть и не показывает шлюзы.
            let window = UIWindow(windowScene: windowScene)
            window.rootViewController = UIViewController()
            window.makeKeyAndVisible()
            self.window = window
            return
        }

        let flow = AppFlowController(container: appDelegate.container, windowScene: windowScene)
        flowController = flow
        window = flow.mainWindow
        flow.start()

        if let url = connectionOptions.urlContexts.first?.url {
            flow.handle(url: url)
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        flowController?.handle(url: url)
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        flowController?.handleWillEnterForeground()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        flowController?.handleDidEnterBackground()
    }

    private var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
