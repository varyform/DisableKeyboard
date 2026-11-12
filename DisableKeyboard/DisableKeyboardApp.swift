import Carbon.HIToolbox
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

// ⌃⌥⌘K toggles the lock. Matched inside the event tap rather than registered as a hotkey: the
// tap sees keystrokes first, so this still works while everything else is swallowed — e.g. when
// the display is off and the menu bar can't be clicked.
private let toggleKeyCode = Int64(kVK_ANSI_K)
private let toggleModifiers: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]
private let checkedModifiers: CGEventFlags = toggleModifiers.union(.maskShift)

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var isKeyboardDisabled = false
    var eventTap: CFMachPort?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(
                systemSymbolName: "keyboard", accessibilityDescription: "Keyboard Toggle")
            button.toolTip = "Toggle keyboard (⌃⌥⌘K)"
            button.action = #selector(toggleKeyboard)
            button.target = self
        }

        // Installed up front so the shortcut can lock the keyboard too, not only unlock it.
        installEventTap()
        updateIcon()
    }

    @objc func toggleKeyboard() {
        guard eventTap != nil || installEventTap() else {
            showAccessibilityAlert()
            return
        }
        isKeyboardDisabled.toggle()
        updateIcon()
    }

    @discardableResult
    func installEventTap() -> Bool {
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
                    let delegate = Unmanaged<AppDelegate>.fromOpaque(refcon!).takeUnretainedValue()
                    // The tap's run loop source is on the main run loop.
                    return MainActor.assumeIsolated { delegate.handle(type, event) }
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        else {
            return false
        }

        eventTap = tap
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let passThrough = Unmanaged.passUnretained(event)

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // A permanent tap must survive these, or the shortcut silently stops working.
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return passThrough
        }

        if type == .keyDown || type == .keyUp, isToggleShortcut(event) {
            if type == .keyDown, event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                toggleKeyboard()
            }
            return nil
        }

        guard isKeyboardDisabled else { return passThrough }

        if type.rawValue == systemDefinedEventType,
            NSEvent(cgEvent: event)?.subtype.rawValue != auxControlButtonsSubtype
        {
            return passThrough
        }
        return nil
    }

    func isToggleShortcut(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.keyboardEventKeycode) == toggleKeyCode
            && event.flags.intersection(checkedModifiers) == toggleModifiers
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
