import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controlBar: ControlBarWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controlBar = ControlBarWindowController()
        controlBar?.showWindow(nil)
    }
}
