import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controlBar: ControlBarWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            let cameraOK = await PermissionsChecker.requestCameraPermission()
            if !cameraOK {
                showPermissionAlert()
            }
            controlBar = ControlBarWindowController()
            controlBar?.showWindow(nil)
        }
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "需要摄像头权限"
        alert.informativeText = "Lumia 需要访问摄像头以显示口播画面。请在系统设置中开启权限，然后重新启动 Lumia。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            PermissionsChecker.openCameraPrivacySettings()
        }
    }
}
