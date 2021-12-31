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
    var contextImage: Data {
        switch self {
        case .notRunning:
            return try! Data(contentsOf: PluginImplementation.urlForImage(fileName: "PauseDebuggerUnknown.png"))
        case .running:
            return try! Data(contentsOf: PluginImplementation.urlForImage(fileName: "PauseDebugger.png"))
        case .paused:
            return try! Data(contentsOf: PluginImplementation.urlForImage(fileName: "ResumeDebugger.png"))
        }
    }
}


class XcodePluginImplementation: ESDConnectionManagerDelegate {

    var connectionManager: ESDConnectionManager? = nil
    var Xcode: XcodeObserver? = nil

    // MARK: - Constants

    let breakpointActionIdentifier: String = "org.danielkennett.xcode-streamdeck-plugin.toggle-breakpoints"
    let pauseDebuggerActionIdentifier: String = "org.danielkennett.xcode-streamdeck-plugin.pause-debugger"

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

    // MARK: - Breakpoint Buttons

    private var breakpointButtonContexts: [ESDSDKContext] = []

    private func handleBreakpointButtonAdded(_ context: ESDSDKContext) {
        breakpointButtonContexts.append(context)
        updateBreakpointButton(context, with: Xcode?.breakpointsEnabledState ?? .unknown)
    }

    private func handleBreakpointButtonRemoved(_ context: ESDSDKContext) {
        breakpointButtonContexts.removeAll(where: { $0 == context })
    }

    private func updateBreakpointButton(_ context: ESDSDKContext, with state: XcodeObserver.BreakpointsEnabledState) {
        guard let connectionManager = connectionManager else { return }
        let image = state.contextImage
        connectionManager.setImage(image, type: .png, of: context, targeting: .hardwareOnly, completionHandler: { _ in })
    }

    private func updateAllBreakpointButtons(with state: XcodeObserver.BreakpointsEnabledState) {
        guard let connectionManager = connectionManager else { return }
        let image = state.contextImage

        for context in breakpointButtonContexts {
            // There's no need to update the icon in the Stream Deck app - just the hardware.
            connectionManager.setImage(image, type: .png, of: context, targeting: .hardwareOnly, completionHandler: { _ in })
        }
    }

    // MARK: - Debugger Buttons

    private var debuggerButtonContexts: [ESDSDKContext] = []

    private func handleDebuggerButtonAdded(_ context: ESDSDKContext) {
        debuggerButtonContexts.append(context)
        updateDebuggerButton(context, with: Xcode?.debuggerState ?? .notRunning)
    }

    private func handleDebuggerButtonRemoved(_ context: ESDSDKContext) {
        debuggerButtonContexts.removeAll(where: { $0 == context })
    }

    private func updateDebuggerButton(_ context: ESDSDKContext, with state: XcodeObserver.DebuggerState) {
        guard let connectionManager = connectionManager else { return }
        let image = state.contextImage
        connectionManager.setImage(image, type: .png, of: context, targeting: .hardwareOnly, completionHandler: { _ in })
    }

    private func updateAllDebuggerButtons(with state: XcodeObserver.DebuggerState) {
        guard let connectionManager = connectionManager else { return }
        let image = state.contextImage

        for context in debuggerButtonContexts {
            // There's no need to update the icon in the Stream Deck app - just the hardware.
            connectionManager.setImage(image, type: .png, of: context, targeting: .hardwareOnly, completionHandler: { _ in })
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
            .sink(receiveValue: { [weak self] state in
                self?.updateAllBreakpointButtons(with: state)
            }).store(in: &observers)

        XcodeAPI.$debuggerState
            .removeDuplicates()
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

    // MARK: - Button Handlers

    private func handleBreakpointButtonTapped(_ context: ESDSDKContext) {
        guard let Xcode = Xcode else {
            connectionManager?.requestShowAlert(on: context, completionHandler: { _ in })
            return
        }

        if case .failure(_) = Xcode.toggleBreakpointsEnabled() {
            connectionManager?.requestShowAlert(on: context, completionHandler: { _ in })
        }
    }

    private func handleDebuggerButtonTapped(_ context: ESDSDKContext) {
        guard let Xcode = Xcode else {
            connectionManager?.requestShowAlert(on: context, completionHandler: { _ in })
            return
        }

        let result: Result<Void, XcodeError> = {
            if Xcode.debuggerState == .paused {
                return Xcode.resumeDebugger()
            } else {
                return Xcode.pauseDebugger()
            }
        }()

        if case .failure(_) = result {
            connectionManager?.requestShowAlert(on: context, completionHandler: { _ in })
        }
    }

    // MARK: - Plugin Delegates

    func connectionManagerDidEstablishConnectionToPluginHost(_ manager: ESDConnectionManager) {
        connectionManager = manager
        handleXcodeLaunched()
    }

    func connectionManager(_ manager: ESDConnectionManager, actionWillAppear actionIdentifier: String,
                           on deviceIdentifier: String, context: ESDSDKContext, event: ESDSDKVisibilityEventPayload) {
        switch actionIdentifier {
        case breakpointActionIdentifier: handleBreakpointButtonAdded(context)
        case pauseDebuggerActionIdentifier: handleDebuggerButtonAdded(context)
        default: break
        }
    }

    func connectionManager(_ manager: ESDConnectionManager, actionWillDisappear actionIdentifier: String,
                           on deviceIdentifier: String, context: ESDSDKContext, event: ESDSDKVisibilityEventPayload) {
        switch actionIdentifier {
        case breakpointActionIdentifier: handleBreakpointButtonRemoved(context)
        case pauseDebuggerActionIdentifier: handleDebuggerButtonRemoved(context)
        default: break
        }
    }

    func connectionManager(_ manager: ESDConnectionManager, didReceiveKeyDownEventForAction actionIdentifier: String,
                           on deviceIdentifier: String, context: ESDSDKContext, event: ESDSDKKeyEventPayload) {

        switch actionIdentifier {
        case breakpointActionIdentifier: handleBreakpointButtonTapped(context)
        case pauseDebuggerActionIdentifier: handleDebuggerButtonTapped(context)
        default: break
        }
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
