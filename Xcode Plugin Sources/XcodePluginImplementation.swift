//
//  XcodePluginImplementation.swift
//  Stream Deck Xcode Plugin Binary
//
//  Created by Daniel Kennett on 2021-12-31.
//

import Foundation
import AppKit
import Combine

extension XcodeObserver.BreakpointsEnabledState {
    var contextImage: Data {
        switch self {
        case .disabled:
            return try! Data(contentsOf: PluginImplementation.urlForImage(fileName: "BreakpointsDisabled.png"))
        case .enabled:
            return try! Data(contentsOf: PluginImplementation.urlForImage(fileName: "BreakpointsEnabled.png"))
        case .unknown:
            return try! Data(contentsOf: PluginImplementation.urlForImage(fileName: "BreakpointsUnknown.png"))
        }
    }
}

extension XcodeObserver.DebuggerState {
    var pauseDebuggerContextImage: Data {
        switch self {
        case .notRunning:
            return try! Data(contentsOf: PluginImplementation.urlForImage(fileName: "PauseDebuggerUnknown.png"))
        case .running:
            return try! Data(contentsOf: PluginImplementation.urlForImage(fileName: "PauseDebugger.png"))
        case .paused:
            return try! Data(contentsOf: PluginImplementation.urlForImage(fileName: "ResumeDebugger.png"))
        }
    }

    var viewDebuggerContextImage: Data {
        switch self {
        case .notRunning:
            return try! Data(contentsOf: PluginImplementation.urlForImage(fileName: "ViewDebuggerUnknown.png"))
        case .running, .paused:
            return try! Data(contentsOf: PluginImplementation.urlForImage(fileName: "ViewDebugger.png"))
        }
    }
}


class XcodePluginImplementation: ESDConnectionManagerDelegate {

    var connectionManager: ESDConnectionManager? = nil
    var Xcode: XcodeObserver? = nil

    // MARK: - Constants

    enum ActionIdentifier: String, CaseIterable {
        case breakpointsEnabled = "org.danielkennett.xcode-streamdeck-plugin.toggle-breakpoints"
        case pauseDebugger = "org.danielkennett.xcode-streamdeck-plugin.pause-debugger"
        case viewDebugger = "org.danielkennett.xcode-streamdeck-plugin.view-debugger"
    }

    // MARK: - Global State

    private func updateAllButtons() {
        guard let Xcode = Xcode else {
            updateAllBreakpointButtons(with: .unknown)
            updateAllDebuggerButtons(with: .notRunning)
            return
        }
        
        updateAllBreakpointButtons(with: Xcode.breakpointsEnabledState)
        updateAllDebuggerButtons(with: Xcode.debuggerState)
    }

    // MARK: - Buttons

    private var activeButtonContexts: [ActionIdentifier: [ESDSDKContext]] = [:]

    private func handleButtonAdded(_ context: ESDSDKContext, for identifier: ActionIdentifier) {
        var contexts = activeButtonContexts[identifier, default: []]
        contexts.append(context)
        activeButtonContexts[identifier] = contexts

        switch identifier {
        case .breakpointsEnabled:
            updateBreakpointButton(context, with: Xcode?.breakpointsEnabledState ?? .unknown)
        case .pauseDebugger, .viewDebugger:
            updateDebuggerButton(context, of: identifier, with: Xcode?.debuggerState ?? .notRunning)
        }
    }

    private func handleButtonRemoved(_ context: ESDSDKContext) {
        ActionIdentifier.allCases.forEach({ identifier in
            var contexts = activeButtonContexts[identifier, default: []]
            contexts.removeAll(where: { $0 == context })
            activeButtonContexts[identifier] = contexts
        })
    }

    private func handleButtonTapped(_ context: ESDSDKContext, with identifier: ActionIdentifier) {
        guard let Xcode = Xcode else {
            connectionManager?.requestShowAlert(on: context, completionHandler: { _ in })
            return
        }

        let result: Result<Void, XcodeError> = {
            let debuggerState = Xcode.debuggerState
            switch identifier {
            case .breakpointsEnabled: return Xcode.toggleBreakpointsEnabled()
            case .pauseDebugger: return debuggerState == .paused ? Xcode.resumeDebugger() : Xcode.pauseDebugger()
            case .viewDebugger: return Xcode.triggerViewDebugger()
            }
        }()

        if case .failure(_) = result {
            connectionManager?.requestShowAlert(on: context, completionHandler: { _ in })
        }
    }

    // MARK: - Breakpoint Buttons

    private func updateBreakpointButton(_ context: ESDSDKContext, with state: XcodeObserver.BreakpointsEnabledState) {
        guard let connectionManager = connectionManager else { return }
        let image = state.contextImage
        connectionManager.setImage(image, type: .png, of: context, targeting: .hardwareOnly, completionHandler: { _ in })
    }

    private func updateAllBreakpointButtons(with state: XcodeObserver.BreakpointsEnabledState) {
        guard let connectionManager = connectionManager else { return }
        let image = state.contextImage

        for context in activeButtonContexts[.breakpointsEnabled, default: []] {
            // There's no need to update the icon in the Stream Deck app - just the hardware.
            connectionManager.setImage(image, type: .png, of: context, targeting: .hardwareOnly, completionHandler: { _ in })
        }
    }

    // MARK: - Debugger Buttons

    private func updateDebuggerButton(_ context: ESDSDKContext, of identifier: ActionIdentifier,
                                      with state: XcodeObserver.DebuggerState) {
        guard let connectionManager = connectionManager else { return }
        guard let image: Data = {
            switch identifier {
            case .breakpointsEnabled: return nil
            case .pauseDebugger: return state.pauseDebuggerContextImage
            case .viewDebugger: return state.viewDebuggerContextImage
            }
        }() else { return }
        connectionManager.setImage(image, type: .png, of: context, targeting: .hardwareOnly) { _ in }
    }

    private func updateAllDebuggerButtons(with state: XcodeObserver.DebuggerState) {
        guard let connectionManager = connectionManager else { return }
        let pauseDebuggerImage = state.pauseDebuggerContextImage
        let viewDebuggerImage = state.viewDebuggerContextImage

        for context in activeButtonContexts[.pauseDebugger, default: []] {
            connectionManager.setImage(pauseDebuggerImage, type: .png, of: context, targeting: .hardwareOnly) { _ in }
        }

        for context in activeButtonContexts[.viewDebugger, default: []] {
            connectionManager.setImage(viewDebuggerImage, type: .png, of: context, targeting: .hardwareOnly) { _ in }
        }
    }

    // MARK: - Observing Xcode

    private var observers: Set<AnyCancellable> = []

    private func handleXcodeLaunched() {
        let bundleId = XcodeObserver.bundleIdentifier
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else {
            handleXcodeTerminated()
            return
        }

        observers.removeAll()
        let XcodeAPI = XcodeObserver(observing: app)
        self.Xcode = XcodeAPI

        XcodeAPI.$breakpointsEnabledState
            .removeDuplicates()
            .debounce(for: .seconds(0.25), scheduler: RunLoop.main)
            .sink(receiveValue: { [weak self] state in
                self?.updateAllBreakpointButtons(with: state)
            }).store(in: &observers)

        XcodeAPI.$debuggerState
            .removeDuplicates()
            .debounce(for: .seconds(0.25), scheduler: RunLoop.main)
            .sink(receiveValue: { [weak self] state in
                self?.updateAllDebuggerButtons(with: state)
            }).store(in: &observers)

        updateAllButtons()
    }

    private func handleXcodeTerminated() {
        observers.removeAll()
        Xcode = nil
        updateAllButtons()
    }

    // MARK: - Plugin Delegates

    func connectionManagerDidEstablishConnectionToPluginHost(_ manager: ESDConnectionManager) {
        connectionManager = manager
        handleXcodeLaunched()
    }

    func connectionManager(_ manager: ESDConnectionManager, actionWillAppear actionIdentifier: String,
                           on deviceIdentifier: String, context: ESDSDKContext, event: ESDSDKVisibilityEventPayload) {

        guard let identifier = ActionIdentifier(rawValue: actionIdentifier) else { return }
        handleButtonAdded(context, for: identifier)
    }

    func connectionManager(_ manager: ESDConnectionManager, actionWillDisappear actionIdentifier: String,
                           on deviceIdentifier: String, context: ESDSDKContext, event: ESDSDKVisibilityEventPayload) {

        handleButtonRemoved(context)
    }

    func connectionManager(_ manager: ESDConnectionManager, didReceiveKeyDownEventForAction actionIdentifier: String,
                           on deviceIdentifier: String, context: ESDSDKContext, event: ESDSDKKeyEventPayload) {

        guard let identifier = ActionIdentifier(rawValue: actionIdentifier) else { return }
        handleButtonTapped(context, with: identifier)
    }

    func connectionManager(_ manager: ESDConnectionManager, didReceiveKeyUpEventForAction actionIdentifier: String, on deviceIdentifier: String, context: ESDSDKContext, event: ESDSDKKeyEventPayload) {

    }

    func connectionManagerDidEncounterSystemWakeUp(_ manager: ESDConnectionManager) {
        handleXcodeTerminated()
        handleXcodeLaunched()
    }

    func connectionManager(_ manager: ESDConnectionManager, monitoredApplicationDidLaunch bundleId: String) {
        handleXcodeLaunched()
    }

    func connectionManager(_ manager: ESDConnectionManager, monitoredApplicationDidTerminate bundleId: String) {
        handleXcodeTerminated()
    }

    // MARK: - No Man's Land

    func connectionManager(_ manager: ESDConnectionManager, deviceDidConnect deviceIdentifier: String,
                           deviceInfo: ESDSDKDeviceInfoEventPayload) {}

    func connectionManager(_ manager: ESDConnectionManager, deviceDidDisconnect deviceIdentifier: String) {}

    func connectionManager(_ manager: ESDConnectionManager, didReceiveGlobalSettings settings: ESDSDKSettings?) {}

    func connectionManager(_ manager: ESDConnectionManager, didReceiveSettings settings: ESDSDKSettingsEventPayload,
                           for actionIdentifier: String, on deviceIdentifier: String, context: ESDSDKContext) {}

    func connectionManager(_ manager: ESDConnectionManager,
                           didReceiveTitleParameters parameters: ESDSDKTitleParametersEventPayload,
                           for actionIdentifier: String, on deviceIdentifier: String, context: ESDSDKContext) {}

    func connectionManager(_ manager: ESDConnectionManager,
                           propertyInspectorDidAppearForAction actionIdentifier: String,
                           on deviceIdentifier: String, context: ESDSDKContext) {}

    func connectionManager(_ manager: ESDConnectionManager,
                           propertyInspectorDidDisappearForAction actionIdentifier: String,
                           on deviceIdentifier: String, context: ESDSDKContext) {}
}
