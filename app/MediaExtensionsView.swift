//
//  MediaExtensionsView.swift
//  QLVideo
//

import Cocoa

final class MediaExtensionsView: NSView {

    @IBAction func ok(sender: NSButton) {
        let delegate = NSApp.delegate as! AppDelegate
        delegate.mainWindow.endSheet(self.window!)
    }

    @IBAction func openPrefs(sender: NSButton) {
        let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences?")!
        NSWorkspace.shared.open(url)
        let delegate = NSApp.delegate as! AppDelegate
        delegate.mainWindow.endSheet(self.window!)
    }
}
