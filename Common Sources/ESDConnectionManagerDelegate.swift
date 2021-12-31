//
//  ESDConnectionManagerDelegate.swift
//  Stream Deck Xcode Plugin Binary
//
//  Created by Daniel Kennett on 2021-12-31.
//

import Foundation

protocol ESDConnectionManagerDelegate {

    // MARK: - Connection & Setup

    /// Called when the plugin establishes communication with the Stream Deck host app.
    func connectionManagerDidEstablishConnectionToPluginHost(_ manager: ESDConnectionManager)

    /// Called when a Stream Deck hardware device is connected.
    ///
    /// - Parameters:
    ///   - manager: The connection manager that sent the message.
    ///   - deviceIdentifier: A unique token identifing the device.
    ///   - deviceInfo: Additional information about the device.
    func connectionManager(_ manager: ESDConnectionManager, deviceDidConnect deviceIdentifier: String,
                           deviceInfo: ESDSDKDeviceInfoEventPayload)

    /// Called when a Stream Deck hardware device is disconnected.
    ///
    /// - Parameters:
    ///   - manager: The connection manager that sent the message.
    ///   - deviceIdentifier: A unique token identifing the device.
    func connectionManager(_ manager: ESDConnectionManager, deviceDidDisconnect deviceIdentifier: String)

    // MARK: - Settings

    /// Called when global settings for the plugin are updated.
    ///
    /// - Parameters:
    ///   - manager: The connection manager that sent the message.
    ///   - settings: The updated settings.
    func connectionManager(_ manager: ESDConnectionManager, didReceiveGlobalSettings settings: ESDSDKSettings?)

    /// Called when settings for a particular action instance are updated.
    ///
    /// - Parameters:
    ///   - manager: The connection manager that sent the message.
    ///   - settings: The updated settings.
    ///   - actionIdentifier: The identifier of the action.
    ///   - deviceIdentifier: The identifier of the hardware device.
    ///   - context: The unique identifier for the action instance.
    func connectionManager(_ manager: ESDConnectionManager, didReceiveSettings settings: ESDSDKSettingsEventPayload,
                           for actionIdentifier: String, on deviceIdentifier: String, context: ESDSDKContext)

    /// Called when title parameters for a particular action instance are updated.
    ///
    /// - Parameters:
    ///   - manager: The connection manager that sent the message.
    ///   - parameters: The updated parameters.
    ///   - actionIdentifier: The identifier of the action.
    ///   - deviceIdentifier: The identifier of the hardware device.
    ///   - context: The unique identifier for the action instance.
    func connectionManager(_ manager: ESDConnectionManager,
                           didReceiveTitleParameters parameters: ESDSDKTitleParametersEventPayload,
                           for actionIdentifier: String, on deviceIdentifier: String, context: ESDSDKContext)

    // MARK: - Action Instance Events

    /// Called when a particular action instance key is about to be displayed onscreen.
    ///
    /// - Parameters:
    ///   - manager: The connection manager that sent the message.
    ///   - actionIdentifier: The identifier of the action.
    ///   - deviceIdentifier: The identifier of the hardware device.
    ///   - context: The unique identifier for the action instance.
    ///   - event: Additional details about the event.
    func connectionManager(_ manager: ESDConnectionManager, actionWillAppear actionIdentifier: String,
                           on deviceIdentifier: String, context: ESDSDKContext, event: ESDSDKVisibilityEventPayload)

    /// Called when a particular action instance key is about to no longer be displayed onscreen.
    ///
    /// - Parameters:
    ///   - manager: The connection manager that sent the message.
    ///   - actionIdentifier: The identifier of the action.
    ///   - deviceIdentifier: The identifier of the hardware device.
    ///   - context: The unique identifier for the action instance.
    ///   - event: Additional details about the event.
    func connectionManager(_ manager: ESDConnectionManager, actionWillDisappear actionIdentifier: String,
                           on deviceIdentifier: String, context: ESDSDKContext, event: ESDSDKVisibilityEventPayload)

    /// Called when a particular action instance key is pressed by the user.
    ///
    /// - Parameters:
    ///   - manager: The connection manager that sent the message.
    ///   - actionIdentifier: The identifier of the action.
    ///   - deviceIdentifier: The identifier of the hardware device.
    ///   - context: The unique identifier for the action instance.
    ///   - event: Additional details about the event.
    func connectionManager(_ manager: ESDConnectionManager, didReceiveKeyDownEventForAction actionIdentifier: String,
                           on deviceIdentifier: String, context: ESDSDKContext, event: ESDSDKKeyEventPayload)

    /// Called when a particular action instance key is released by the user.
    ///
    /// - Parameters:
    ///   - manager: The connection manager that sent the message.
    ///   - actionIdentifier: The identifier of the action.
    ///   - deviceIdentifier: The identifier of the hardware device.
    ///   - context: The unique identifier for the action instance.
    ///   - event: Additional details about the event.
    func connectionManager(_ manager: ESDConnectionManager, didReceiveKeyUpEventForAction actionIdentifier: String,
                           on deviceIdentifier: String, context: ESDSDKContext, event: ESDSDKKeyEventPayload)

    // MARK: - System Events

    /// Called when the system woke up from a sleep state.
    ///
    /// - Parameters:
    ///   - manager: The connection manager that sent the message.
    func connectionManagerDidEncounterSystemWakeUp(_ manager: ESDConnectionManager)

    /// Called when a monitored application launched.
    ///
    /// - Note: Monitored applications must be declared in the plugin's manifest JSON.
    ///         See: https://developer.elgato.com/documentation/stream-deck/sdk/manifest/
    ///
    /// - Parameters:
    ///   - manager: The connection manager that sent the message.
    ///   - bundleId: The bundle ID of the application that launched.
    func connectionManager(_ manager: ESDConnectionManager, monitoredApplicationDidLaunch bundleId: String)

    /// Called when a monitored application terminated.
    ///
    /// - Note: Monitored applications must be declared in the plugin's manifest JSON.
    ///         See: https://developer.elgato.com/documentation/stream-deck/sdk/manifest/
    ///
    /// - Parameters:
    ///   - manager: The connection manager that sent the message.
    ///   - bundleId: The bundle ID of the application that terminated.
    func connectionManager(_ manager: ESDConnectionManager, monitoredApplicationDidTerminate bundleId: String)

    // MARK: - Property Inspector

    /// Called when the property inspector for a particular action instance is displayed.
    ///
    /// - Parameters:
    ///   - manager: The connection manager that sent the message.
    ///   - actionIdentifier: The identifier of the action.
    ///   - deviceIdentifier: The identifier of the hardware device.
    ///   - context: The unique identifier for the action instance.
    func connectionManager(_ manager: ESDConnectionManager, propertyInspectorDidAppearForAction actionIdentifier: String,
                           on deviceIdentifier: String, context: ESDSDKContext)

    /// Called when the property inspector for a particular action instance is closed.
    ///
    /// - Parameters:
    ///   - manager: The connection manager that sent the message.
    ///   - actionIdentifier: The identifier of the action.
    ///   - deviceIdentifier: The identifier of the hardware device.
    ///   - context: The unique identifier for the action instance.
    func connectionManager(_ manager: ESDConnectionManager, propertyInspectorDidDisappearForAction actionIdentifier: String,
                           on deviceIdentifier: String, context: ESDSDKContext)

}
