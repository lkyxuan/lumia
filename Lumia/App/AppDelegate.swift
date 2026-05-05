import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controlBarWindowController: ControlBarWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controlBarWindowController = ControlBarWindowController()
        controlBarWindowController?.showWindow(nil)
    }
}
