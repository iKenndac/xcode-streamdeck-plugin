//
//  XcodeObserver.swift
//  XcodeAccessibilityTest
//
//  Created by Daniel Kennett on 2021-12-30.
//

import Foundation
import AppKit
import Accessibility
import Combine

class XcodeObserver {

    static let bundleIdentifier: String = "com.apple.dt.Xcode"

    init(observing app: NSRunningApplication) {
        observedApp = app
        setupObservations(on: app)
        updateAllState()
    }

    deinit {
        unregisterObservations()
    }

    private let observedApp: NSRunningApplication

    // MARK: - API

    enum XcodeApplicationState {
        case running
        case notRunning
    }

    enum DebuggerState {
        case notRunning
        case running
        case paused
    }

    enum BreakpointsEnabledState {
        case disabled
        case enabled
        case unknown
    }

    /// The Xcode debugger state (whether the debugger is not running, running, or paused).
    @Published private(set) var debuggerState: DebuggerState = .notRunning

    /// The Xcode breakpoints enabled state (whether or not breakpoints are enabled).
    @Published private(set) var breakpointsEnabledState: BreakpointsEnabledState = .unknown

    /// The Xcode application state (whether or not the app is running). Once the state goes to `.notRunning`, the
    /// receiver is useless and should be discarded since new instances of Xcode will have a new PID.
    @Published private(set) var applicationState: XcodeApplicationState = .running

    /// Toggles whether breakpoints are enabled or not.
    ///
    /// - Note: The success state of this only informs if the message was successfully sent. Observers will be fired
    ///         when the state changes.
    func toggleBreakpointsEnabled() -> Result<Void, XcodeError> {
        guard case .success(let button) = toggleBreakpointsButton(in: observedApp) else {
            return .failure(.uiElementNotFound)
        }

        let result = button.press()
        updateBreakpointState()
        return result
    }

    /// Pause the running debug session, if able. Xcode will typically activate itself at this point.
    func pauseDebugger() -> Result<Void, XcodeError> {
        guard case .success(let button) = pauseDebuggerButton(in: observedApp) else {
            return .failure(.uiElementNotFound)
        }
        let result = button.press()
        // It probably takes a while for the button bar to update.
        updateRunningState()
        return result
    }

    /// Resume the paused debug session, if able.
    func resumeDebugger() -> Result<Void, XcodeError> {
        guard case .success(let button) = continueDebuggerButton(in: observedApp) else {
            return .failure(.uiElementNotFound)
        }
        let result = button.press()
        // It probably takes a while for the button bar to update.
        updateRunningState()
        return result
    }

    /// Trigger the view debugger, if able. Only available if the `debuggerState` is `.running` or `.paused`.
    func triggerViewDebugger() -> Result<Void, XcodeError> {
        guard case .success(let button) = viewDebuggerButton(in: observedApp) else {
            return .failure(.uiElementNotFound)
        }
        let result = button.press()
        // It probably takes a while for the button bar to update.
        updateRunningState()
        return result
    }

    // MARK: - Accessibility Observations

    private var observedBreakpointsItem: AXUIElement? = nil
    private var observedApplication: AXUIElement? = nil
    private var baseObserver: AXObserver? = nil
    private var isTerminatedObserver: NSKeyValueObservation? = nil

    private func setupObservations(on app: NSRunningApplication) {
        unregisterObservations()

        isTerminatedObserver = observedApp.observe(\.isTerminated) { [weak self] app, change in
            self?.updateXcodeAppState()
        }

        var observer: AXObserver?
        let observerError = AXObserverCreate(app.processIdentifier, { observer, element, notificationName, context in
            guard let context = context else { return }
            let me: XcodeObserver = Unmanaged.fromOpaque(context).takeUnretainedValue()
            me.handleNotification(notificationName as String)
        }, &observer)

        guard observerError == .success, let observer = observer else {
            // TODO: Bail out entirely?
            print("Failed with observer error: \(observerError)")
            return
        }

        baseObserver = observer
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), CFRunLoopMode.commonModes)

        // Now we have a callback etc set up, we can add individual observations.
        let context = Unmanaged.passUnretained(self).toOpaque()

        // We want MainWindowChanged to update breakpoint etc state from the frontmost Xcode window.
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        observedApplication = axApp
        AXObserverAddNotification(observer, axApp, kAXMainWindowChangedNotification as CFString, context)
        AXObserverAddNotification(observer, axApp, kAXApplicationActivatedNotification as CFString, context)
        AXObserverAddNotification(observer, axApp, kAXApplicationDeactivatedNotification as CFString, context)

        // We want MenuItemSelected on the toggle breakpoints menu item so we can update breakpoint state when
        // the user changes breakpoints on/off in the app. Unfortunately, the debug bar button doesn't emit events.
        if case .success(let item) = toggleBreakpointsMenuItem(in: app, debugMenuName: debugMenuEnglishTitle) {
            // The button doesn't seem to emit any events :(
            AXObserverAddNotification(observer, item, kAXMenuItemSelectedNotification as CFString, context)
            observedBreakpointsItem = item
        }

        // TODO: Poll to catch the debug bar button changes?
    }

    private func unregisterObservations() {
        isTerminatedObserver?.invalidate()
        isTerminatedObserver = nil
        if let observer = baseObserver {
            if let menuItem = observedBreakpointsItem {
                AXObserverRemoveNotification(observer, menuItem, kAXMenuItemSelectedNotification as CFString)
            }
            if let app = observedApplication {
                AXObserverRemoveNotification(observer, app, kAXMainWindowChangedNotification as CFString)
                AXObserverRemoveNotification(observer, app, kAXApplicationActivatedNotification as CFString)
                AXObserverRemoveNotification(observer, app, kAXApplicationDeactivatedNotification as CFString)
            }

            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), CFRunLoopMode.commonModes)

            baseObserver = nil
            observedBreakpointsItem = nil
            observedApplication = nil
        }
    }

    // MARK: - Reacting to AX Observations & Updating State

    private func handleNotification(_ notificationName: String) {
        switch notificationName {
        case kAXMenuItemSelectedNotification:
            updateBreakpointState()
        case kAXMainWindowChangedNotification:
            invalidateCachedElements()
            updateAllState()
        case kAXApplicationActivatedNotification, kAXApplicationDeactivatedNotification:
            updateAllState()
        default: break
        }
    }

    private func updateAllState() {
        updateBreakpointState()
        updateRunningState()
        updateXcodeAppState()
    }

    private func updateXcodeAppState() {
        applicationState = observedApp.isTerminated ? .notRunning : .running
    }

    private func updateBreakpointState() {
        switch toggleBreakpointsButton(in: observedApp) {
        case .failure(_): breakpointsEnabledState = .unknown
        case .success(let uiItem):
            let value: Int? = uiItem.valueOfAttribute(kAXValueAttribute)
            switch value {
            case .none: breakpointsEnabledState = .unknown
            case NSControl.StateValue.off.rawValue: breakpointsEnabledState = .disabled
            case NSControl.StateValue.on.rawValue: breakpointsEnabledState = .enabled
            default: breakpointsEnabledState = .unknown
            }
        }
    }

    private func updateRunningState() {
        switch (pauseDebuggerButton(in: observedApp), continueDebuggerButton(in: observedApp)) {
        case (.success, .failure): debuggerState = .running
        case (.failure, .success): debuggerState = .paused
        case (.failure, .failure): debuggerState = .notRunning
        default: debuggerState = .notRunning
        }
    }

    // MARK: - Internal (Caching)

    private func invalidateCachedElements() {
        _cachedDebugBar = nil
        _cachedToggleBreakpointsButton = nil
    }

    // The pause/continue/view debugger buttons aren't cached as they appear/disappear, and that's part of the logic.
    private var _cachedDebugBar: AXUIElement? = nil
    private var _cachedToggleBreakpointsButton: AXUIElement? = nil

    private func debugBar(in app: NSRunningApplication) -> Result<AXUIElement, XcodeError> {
        if let cached = _cachedDebugBar { return .success(cached) }
        switch _uncachedDebugBar(in: app) {
        case .failure(let error): return .failure(error)
        case .success(let bar):
            _cachedDebugBar = bar
            return .success(bar)
        }
    }

    private func toggleBreakpointsButton(in app: NSRunningApplication) -> Result<AXUIElement, XcodeError> {
        if let cached = _cachedToggleBreakpointsButton { return .success(cached) }
        switch _uncachedToggleBreakpointsButton(in: app) {
        case .failure(let error): return .failure(error)
        case .success(let button):
            _cachedToggleBreakpointsButton = button
            return .success(button)
        }
    }

    // MARK: - Internal (Debug Bar)

    // Have seen descriptions: ["Breakpoints", "pause", "step over", "step in", "step out", "Debug View Hierarchy",
    // "Debug Memory Graph", "Environment Overrides", "Simulate Location", "stack frames", "hide debug area"]
    private let debugBarBreakpointButtonDescription: String = "Breakpoints"
    private let debugBarPauseInDebuggerButtonDescription: String = "pause"
    private let debugBarContinueExecutionButtonDescription: String = "continue"
    private let debugBarViewDebuggerButtonDescription: String = "Debug View Hierarchy"

    private func _uncachedToggleBreakpointsButton(in app: NSRunningApplication) -> Result<AXUIElement, XcodeError> {
        switch debugBar(in: app) {
        case .failure(let error): return .failure(error)
        case .success(let debugBar):
            guard let button = debugBar.childElements.first(where: {
                $0.stringValueOfAttribute(kAXDescription) == debugBarBreakpointButtonDescription
            }) else { return .failure(.uiElementNotFound) }
            return .success(button)
        }
    }

    private func pauseDebuggerButton(in app: NSRunningApplication) -> Result<AXUIElement, XcodeError> {
        switch debugBar(in: app) {
        case .failure(let error): return .failure(error)
        case .success(let debugBar):
            guard let button = debugBar.childElements.first(where: {
                $0.stringValueOfAttribute(kAXDescription) == debugBarPauseInDebuggerButtonDescription
            }) else { return .failure(.uiElementNotFound) }
            return .success(button)
        }
    }

    private func continueDebuggerButton(in app: NSRunningApplication) -> Result<AXUIElement, XcodeError> {
        switch debugBar(in: app) {
        case .failure(let error): return .failure(error)
        case .success(let debugBar):
            guard let button = debugBar.childElements.first(where: {
                $0.stringValueOfAttribute(kAXDescription) == debugBarContinueExecutionButtonDescription
            }) else { return .failure(.uiElementNotFound) }
            return .success(button)
        }
    }

    private func viewDebuggerButton(in app: NSRunningApplication) -> Result<AXUIElement, XcodeError> {
        switch debugBar(in: app) {
        case .failure(let error): return .failure(error)
        case .success(let debugBar):
            guard let button = debugBar.childElements.first(where: {
                $0.stringValueOfAttribute(kAXDescription) == debugBarViewDebuggerButtonDescription
            }) else { return .failure(.uiElementNotFound) }
            return .success(button)
        }
    }

    private let mainContentAreaIdentifier: String = "Workspace window tab content"
    private let editorAreaDescription: String = "editor area"
    private let debugBarDescription: String = "debug bar"

    private func _uncachedDebugBar(in app: NSRunningApplication) -> Result<AXUIElement, XcodeError> {

        let app = AXUIElementCreateApplication(app.processIdentifier)

        // The main window _appears_ to be the frontmost one, even if Xcode is backgrounded. Hidden?
        guard let mainWindow: AXUIElement = app.valueOfAttribute(kAXMainWindowAttribute) else {
            return .failure(.uiElementNotFound)
        }

        // The main window has a "tab content" container.
        guard let mainContent = mainWindow.childElements.first(where: {
            $0.stringValueOfAttribute(kAXIdentifierAttribute) == mainContentAreaIdentifier
        }) else { return .failure(.uiElementNotFound) }

        // The item with description "editor area" appears to only have one child item.
        guard let editorArea = mainContent.childElements.first(where: {
            $0.stringValueOfAttribute(kAXDescription) == editorAreaDescription
        })?.childElements.first else { return .failure(.uiElementNotFound) }

        // Finally, we can find the debug bar.
        guard let debugBar = editorArea.childElements.first(where: {
            $0.stringValueOfAttribute(kAXDescription) == debugBarDescription
        }) else { return .failure(.uiElementNotFound) }

        return .success(debugBar)
    }

    // MARK: - Internal (Menu Bar)

    private let debugMenuEnglishTitle: String = "Debug"
    private let pauseOrContinueMenuItemIdentifier: String = "pauseOrContinue:"
    private let pauseMenuItemEnglishTitle: String = "Pause"
    private let continueMenuItemEnglishTitle: String = "Continue"
    private let toggleBreakpointsMenuItemIdentifier: String = "toggleBreakpoints:"
    private let breakpointsActiveMenuEnglishTitle = "Deactivate Breakpoints"
    private let breakpointsInactiveMenuEnglishTitle = "Activate Breakpoints"

    private func toggleBreakpointsMenuItem(in app: NSRunningApplication, debugMenuName: String) -> Result<AXUIElement, XcodeError> {
        return debugMenuItem(with: toggleBreakpointsMenuItemIdentifier, in: app, debugMenuName: debugMenuName)
    }

    private func pauseOrContinueMenuItem(in app: NSRunningApplication, debugMenuName: String) -> Result<AXUIElement, XcodeError> {
        return debugMenuItem(with: pauseOrContinueMenuItemIdentifier, in: app, debugMenuName: debugMenuName)
    }

    private func debugMenuItem(with identifier: String, in app: NSRunningApplication, debugMenuName: String) -> Result<AXUIElement, XcodeError> {
        let app = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &value)
        guard let rawMenubar = value else { return .failure(.uiElementNotFound) }
        let menuBar = rawMenubar as! AXUIElement

        guard let debugMenu = menuBar.childElements.first(where: {
            $0.stringValueOfAttribute(kAXTitleAttribute) == debugMenuName
        }) else { return .failure(.uiElementNotFound) }

        // The menu bar item has one child, which I assume is the menu. The menu then has children.
        guard let debugMenuItems = debugMenu.childElements.first?.childElements else { return .failure(.uiElementNotFound) }

        guard let targetMenuItem: AXUIElement = debugMenuItems.first(where: {
            $0.stringValueOfAttribute(kAXIdentifierAttribute) == identifier
        }) else { return .failure(.uiElementNotFound) }

        return .success(targetMenuItem)
    }
}

enum XcodeError: Error {
    case uiElementNotFound
    case unknownBreakpointState
    case notSupportedByElement
    case accessibilityError(error: AXError)
}

extension AXUIElement {

    /// Returns the value of the given string attribute.
    ///
    /// - Parameter attributeName: The name of the attribute (like `kAXTitleAttribute`).
    /// - Returns: The value, or `nil` if the receiver doesn't support the given attribute name or it does but it isn't a string.
    func stringValueOfAttribute(_ attributeName: String) -> String? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(self, attributeName as CFString, &value)
        guard error == .success || error == .attributeUnsupported || error == .noValue else {
            print("### Warning: Got error when attempting to get attribute value: \(error.rawValue)")
            return nil
        }

        guard let maybeString = value else { return nil }
        guard CFGetTypeID(maybeString) == CFStringGetTypeID() else {
            print("### Warning: Got \(CFGetTypeID(maybeString)) instead of string when attempting to get attribute value: \(error.rawValue)")
            return nil
        }

        return (maybeString as! CFString) as String
    }

    /// Returns the value of the given attribute.
    ///
    /// - Returns: The value, or `nil` if the receiver doesn't support the given attribute name or it does but it
    ///            doesn't match the target return type.
    func valueOfAttribute<T>(_ attributeName: String) -> T? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(self, attributeName as CFString, &value)
        guard error == .success || error == .attributeUnsupported || error == .noValue else {
            print("### Warning: Got error when attempting to get attribute value: \(error.rawValue)")
            return nil
        }

        return value as? T
    }

    /// Returns the child UI elements of the receiver, if any.
    var childElements: [AXUIElement] {
        var children: CFArray?
        let error = AXUIElementCopyAttributeValues(self, kAXChildrenAttribute as CFString, 0, 100, &children)
        guard error == .success else {
            print("### Warning: Got error when attempting to get child items: \(error.rawValue)")
            return []
        }
        guard let childItems = children as? [AXUIElement] else {
            print("### Warning: Couldn't cast child return to [AXUIElement]: \(String(describing: children))")
            return []
        }
        return childItems
    }

    /// Returns the attribute names supported by the receiver.
    var attributeNames: [String] {
        var targetNames: CFArray?
        let error = AXUIElementCopyAttributeNames(self, &targetNames)
        guard error == .success else { return [] }
        return targetNames as? [String] ?? []
    }

    /// Returns the action names supported by the receiver.
    var actionNames: [String] {
        var actionNames: CFArray?
        let error = AXUIElementCopyActionNames(self, &actionNames)
        guard error == .success else { return [] }
        return actionNames as? [String] ?? []
    }

    /// Performs the "press" action, if supported by the receiver.
    ///
    /// - Returns: Returns an error on failure, otherwise an empty success value.
    func press() -> Result<Void, XcodeError> {
        guard actionNames.contains(kAXPressAction) else {
            print("### Warning: Asked to press an element that doesn't support it!")
            return .failure(.notSupportedByElement)
        }

        let error = AXUIElementPerformAction(self, kAXPressAction as CFString)
        if error != .success {
            print("### Warning: Got error pressing an element: \(error.rawValue)")
            return .failure(.accessibilityError(error: error))
        }

        return .success(())
    }

}
