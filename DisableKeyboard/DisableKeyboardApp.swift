import IOKit
import SwiftUI

@main
struct DisableKeyboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

// Media/function-row keys (brightness, volume, play/pause, backlight) arrive as
// NX_SYSDEFINED events, which CGEventType has no case for.
private let systemDefinedEventType: UInt32 = 14
// NX_SUBTYPE_AUX_CONTROL_BUTTONS; other subtypes (e.g. 7, aux mouse buttons) must pass.
private let auxControlButtonsSubtype: Int16 = 8

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var isKeyboardDisabled = false
    var eventTap: CFMachPort?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(
                systemSymbolName: "keyboard", accessibilityDescription: "Keyboard Toggle")
            button.action = #selector(toggleKeyboard)
            button.target = self
        }

        updateIcon()
    }

    @objc func toggleKeyboard() {
        if isKeyboardDisabled {
            enableKeyboard()
        } else {
            disableKeyboard()
        }
        isKeyboardDisabled.toggle()
        updateIcon()
    }

    func disableKeyboard() {
        let eventMask =
            (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << systemDefinedEventType)

        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(eventMask),
                callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                    if type.rawValue == systemDefinedEventType,
                        NSEvent(cgEvent: event)?.subtype.rawValue != auxControlButtonsSubtype
                    {
                        return Unmanaged.passUnretained(event)
                    }
                    return nil
                },
                userInfo: nil
            )
        else {
            showAccessibilityAlert()
            return
        }

        eventTap = tap
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func enableKeyboard() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
    }

    func updateIcon() {
        if let button = statusItem?.button {
            let symbolName = isKeyboardDisabled ? "keyboard.fill" : "keyboard"
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        }
    }

    func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText =
            "Grant accessibility permissions in System Preferences > Security & Privacy > Privacy > Accessibility"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
