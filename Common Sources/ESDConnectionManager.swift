//
//  ESDConnectionManager.swift
//  Stream Deck Xcode Plugin Binary
//
//  Created by Daniel Kennett on 2021-12-31.
//

import Foundation

/// Handles the WebSocket communication with the Stream Deck plugin host.
class ESDConnectionManager: NSObject, URLSessionWebSocketDelegate {

    init?(port: Int, uuid: String, registerEvent: String, info: String, eventHandler: ESDConnectionManagerDelegate) {
        self.port = port
        self.pluginUUID = uuid
        self.registerEvent = registerEvent
        self.eventHandler = eventHandler

        guard let infoData = info.data(using: .utf8),
              let registrationInfo = try? JSONDecoder().decode(ESDSDKPluginRegistrationInfo.self, from: infoData) else {
                  return nil
              }

        self.registrationInfo = registrationInfo
        super.init()

        // Since we're using URLSession for a socket, there's no need for any caching or other on-disk storage.
        let config = URLSessionConfiguration.ephemeral
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: .main)

        setupWebSocket()
    }

    // MARK: - Basic State

    private let port: Int
    private let pluginUUID: String
    private let registerEvent: String
    private let registrationInfo: ESDSDKPluginRegistrationInfo

    // Although we're using the delegate pattern, the connection manager is the only thing with a reference
    // to the event handler, and as such requires an owning reference (i.e., not a weak one).
    private let eventHandler: ESDConnectionManagerDelegate

    // MARK: - WebSocket

    private var session: URLSession!
    private var socket: URLSessionWebSocketTask?

    private func setupWebSocket() {
        socket = session.webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)")!)
        socket?.maximumMessageSize = 5 * 1024 * 1024 // We're passing images back and forth, so let's have a big buffer.
        socket?.resume()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol proto: String?) {

        print("Plugin websocket opened with protocol: \(proto ?? "nil"), registering…")

        // URLSession's WebSocket API is a bit weird — we have to continually ask it to receive the next message.
        recursivelyReceiveMessages()

        let message = ESDSDKRegisterPluginMessage(event: registerEvent, uuid: pluginUUID)
        let messageData = try! JSONEncoder().encode(message)
        socket?.send(.data(messageData)) { [weak self] error in
            if let error = error {
                self?.handleSendFailure(error)
            } else {
                guard let self = self else { return }
                self.eventHandler.connectionManagerDidEstablishConnectionToPluginHost(self)
            }
        }
    }

    func recursivelyReceiveMessages() {
        // If we have no socket, we're done.
        guard let socket = socket else { return }
        socket.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .data(let data):
                    self?.handleReceivedMessage(data)
                case .string(let string):
                    if let data = string.data(using: .utf8) { self?.handleReceivedMessage(data) }
                @unknown default: break
                }

            case .failure(_):
                // I'm unsure if we should just try again on a failure - maybe this times out?
                // If we've otherwise failed, we'll be immediately terminated anyway.
                break
            }

            self?.recursivelyReceiveMessages()
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("Plugin websocket closed with code, exiting: \(closeCode)", to: &stdError)
        socket?.cancel()
        socket = nil
        exit(0)
    }

    private func handleSendFailure(_ error: Error) {
        print("Plugin websocket failed to write with error, exiting: \(error)", to: &stdError)
        socket?.cancel()
        socket = nil
        exit(1)
    }

    // MARK: - Public API: Settings

    /// Apply settings for the given action context.
    ///
    /// - Parameters:
    ///   - settings: The settings to apply.
    ///   - context: The context to set settings for.
    ///   - completionHandler: The completion handler to be called when the settings are set.
    func setSettings(_ settings: ESDSDKSettings, for context: ESDSDKContext,
                     completionHandler: @escaping ESDSDKMessageCompletionHandler) {
        sendMessage(ESDSDKSetSettingsMessage(context: context, payload: settings),
                    completionHandler: completionHandler)
    }

    /// Request the settings for the given action context. A `connectionManager(_:, didReceiveSettingsForAction:…)`
    /// message will be delivered to the delegate at a later time.
    ///
    /// - Parameter context: The context to request settings for.
    /// - Parameter completionHandler: The completion handler to be called when the message is sent.
    func requestSettings(for context: ESDSDKContext, completionHandler: @escaping ESDSDKMessageCompletionHandler) {
        sendMessage(ESDSDKGenericWithContextMessage(event: .getSettings, context: context),
                    completionHandler: completionHandler)
    }

    /// Apply global settings for the plugin.
    ///
    /// - Parameters:
    ///   - settings: The settings to apply.
    ///   - completionHandler: The completion handler to be called when the message is sent.
    func setGlobalSettings(_ settings: ESDSDKSettings, completionHandler: @escaping ESDSDKMessageCompletionHandler) {
        sendMessage(ESDSDKSetGlobalSettingsMessage(context: pluginUUID, payload: settings),
                    completionHandler: completionHandler)
    }

    /// Request global settings for the plugin. A `connectionManager(_:, didReceiveGlobalSettings:)`
    /// message will be delivered to the delegate at a later time.
    ///
    /// - Parameter completionHandler: The completion handler to be called when the message is sent.
    func requestGlobalSettings(completionHandler: @escaping ESDSDKMessageCompletionHandler) {
        sendMessage(ESDSDKGenericWithContextMessage(event: .getGlobalSettings, context: pluginUUID),
                    completionHandler: completionHandler)
    }

    // MARK: - Public API: Misc

    /// Request the given URL is opened in the system default web browser.
    ///
    /// - Parameters:
    ///   - url: The URL to open.
    ///   - completionHandler: The completion handler to be called when the message is sent.
    func requestOpenUrl(_ url: URL, completionHandler: @escaping ESDSDKMessageCompletionHandler) {
        sendMessage(ESDSDKOpenUrlMessage(url: url.absoluteString), completionHandler: completionHandler)
    }

    /// Request the given message is logged to the Stream Deck host log file.
    ///
    /// - Parameters:
    ///   - logMessage: The message to log.
    ///   - completionHandler: The completion handler to be called when the message is sent.
    func requestLogMessage(_ logMessage: String, completionHandler: @escaping ESDSDKMessageCompletionHandler) {
        sendMessage(ESDSDKLogMessage(message: logMessage), completionHandler: completionHandler)
    }

    // MARK: Public API: Titles, Images & States

    /// Set the given action context to the specified state.
    ///
    /// - Parameters:
    ///   - state: The state to set the action to. `.all` is not a valid value.
    /// - Parameter context: The context to request settings for.
    /// - Parameter completionHandler: The completion handler to be called when the message is sent.
    func setState(_ state: ESDSDKState, on context: ESDSDKContext,
                  completionHandler: @escaping ESDSDKMessageCompletionHandler) {

        guard state != .all else {
            completionHandler(.invalidInput)
            return
        }

        sendMessage(ESDSDKSetStateMessage(context: context, state: state), completionHandler: completionHandler)
    }

    /// Set the title of the given action context.
    ///
    /// - Parameters:
    ///   - title: The title to set.
    ///   - state: The state on which to set the title on, or `.all`.
    ///   - context: The context of the action to set the title of.
    ///   - target: The target of the title — hardware, software, or both.
    ///   - completionHandler: The completion handler to be called when the message is sent.
    func setTitle(_ title: String?, in state: ESDSDKState = .all, of context: ESDSDKContext,
                  targeting target: ESDSDKTarget = .hardwareAndSoftware,
                  completionHandler: @escaping ESDSDKMessageCompletionHandler) {

        sendMessage(ESDSDKSetTitleMessage(title: title, state: state, context: context, target: target),
                    completionHandler: completionHandler)
    }

    struct ImageType {
        static let png = ImageType(mimeType: "image/png")
        static let jpeg = ImageType(mimeType: "image/jpg")
        let mimeType: String
    }

    /// Set the image of the given action context.
    ///
    /// - Parameters:
    ///   - imageData: The image data to set.
    ///   - type: The type of the given image data.
    ///   - state: The state on which to set the image on, or `.all`.
    ///   - context: The context of the action to set the image of.
    ///   - target: The target of the image — hardware, software, or both.
    ///   - completionHandler: The completion handler to be called when the message is sent.
    func setImage(_ imageData: Data?, type: ImageType, in state: ESDSDKState = .all, of context: ESDSDKContext,
                  targeting target: ESDSDKTarget = .hardwareAndSoftware,
                  completionHandler: @escaping ESDSDKMessageCompletionHandler) {

        setBase64Image(imageData?.base64EncodedString(), type: type, in: state, of: context, targeting: target,
                       completionHandler: completionHandler)
    }

    /// Set the image of the given action context.
    ///
    /// - Note: The underlying protocol encodes image as Base64 for transmission. If you already have this cached,
    ///         calling this message with that cached encoding will be more efficient than using `setImage(_:, …)`.
    ///
    /// - Parameters:
    ///   - encodedImage: The base64-encoded image data to set.
    ///   - type: The type of the given image data.
    ///   - state: The state on which to set the image on, or `.all`.
    ///   - context: The context of the action to set the image of.
    ///   - target: The target of the image — hardware, software, or both.
    ///   - completionHandler: The completion handler to be called when the message is sent.
    func setBase64Image(_ encodedImage: String?, type: ImageType, in state: ESDSDKState = .all,
                        of context: ESDSDKContext, targeting target: ESDSDKTarget = .hardwareAndSoftware,
                        completionHandler: @escaping ESDSDKMessageCompletionHandler) {

        let imageWithHeader: String? = {
            guard let encodedImage = encodedImage else { return nil }
            return "data:\(type.mimeType);base64,".appending(encodedImage)
        }()

        sendMessage(ESDSDKSetImageMessage(encodedImage: imageWithHeader, state: state, context: context, target: target),
                    completionHandler: completionHandler)
    }

    // MARK: Public API: Alerts & Other State

    /// Show a temporary warning icon on the given action context.
    ///
    /// - Parameters:
    ///   - context: The context to show an alert on.
    ///   - completionHandler: The completion handler to be called when the message is sent.
    func requestShowAlert(on context: ESDSDKContext, completionHandler: @escaping ESDSDKMessageCompletionHandler) {
        sendMessage(ESDSDKGenericWithContextMessage(event: .showAlert, context: context),
                    completionHandler: completionHandler)
    }

    /// Show a temporary 'OK' checkmark on the given action context.
    ///
    /// - Parameters:
    ///   - context: The context to show an alert on.
    ///   - completionHandler: The completion handler to be called when the message is sent.
    func requestShowOK(on context: ESDSDKContext, completionHandler: @escaping ESDSDKMessageCompletionHandler) {
        sendMessage(ESDSDKGenericWithContextMessage(event: .showOk, context: context),
                    completionHandler: completionHandler)
    }

    // MARK: - Message Sending

    private func sendMessage(_ message: ESDSDKMessage, completionHandler: @escaping ESDSDKMessageCompletionHandler) {
        guard let messageData = message.encodedMessage else {
            completionHandler(.invalidInput)
            return
        }

        guard let socket = socket else {
            completionHandler(.notConnected)
            return
        }

        socket.send(.data(messageData), completionHandler: { [weak self] error in
            if let error = error {
                completionHandler(.tranportError(error))
                self?.handleSendFailure(error)
                return
            }

            completionHandler(nil)
        })
    }

    // MARK: - Event Handling

    private func handleReceivedMessage(_ data: Data) {
        // Messages are a bit dynamic (i.e., you have to parse the JSON to find out what structure it'll be in),
        // which makes using Codable a bit of a pain.

        guard let decodedJSON = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            print("Got invalid JSON!", to: &stdError)
            return
        }

        // Event name is required.
        guard let rawEventName = decodedJSON[ESDSDKEventCommonKeys.event.rawValue] as? String else {
            print("Got valid JSON, but no event name!", to: &stdError)
            return
        }

        guard let eventName = ESDSDKEventName(rawValue: rawEventName) else {
            print("Got valid JSON, but unknown event name!", to: &stdError)
            return
        }

        // The rest are optional depending on the event.
        let context = decodedJSON[ESDSDKEventCommonKeys.context.rawValue] as? ESDSDKContext
        let actionIdentifier = decodedJSON[ESDSDKEventCommonKeys.action.rawValue] as? String
        let deviceIdentifier = decodedJSON[ESDSDKEventCommonKeys.device.rawValue] as? String
        let deviceInfo = decodedJSON[ESDSDKEventCommonKeys.deviceInfo.rawValue] as? [String: Any]
        let rawPayload = decodedJSON[ESDSDKEventCommonKeys.payload.rawValue] as? [String: Any]

        switch eventName {
        case .keyDown, .keyUp:
            guard let actionIdentifier = actionIdentifier, let context = context, let deviceIdentifier = deviceIdentifier,
                  let rawPayload = rawPayload, let payload = ESDSDKKeyEventPayload(rawPayload) else {
                print("Got key event, but invalid payload for it!", to: &stdError)
                return
            }

            if eventName == .keyUp {
                eventHandler.connectionManager(self, didReceiveKeyUpEventForAction: actionIdentifier, on: deviceIdentifier,
                                               context: context, event: payload)
            } else if eventName == .keyDown {
                eventHandler.connectionManager(self, didReceiveKeyDownEventForAction: actionIdentifier, on: deviceIdentifier,
                                               context: context, event: payload)
            }

        case .willAppear, .willDisappear:
            guard let actionIdentifier = actionIdentifier, let context = context, let deviceIdentifier = deviceIdentifier,
                  let rawPayload = rawPayload, let payload = ESDSDKVisibilityEventPayload(rawPayload) else {
                print("Got visibility event, but invalid payload for it!", to: &stdError)
                return
            }

            if eventName == .willAppear {
                eventHandler.connectionManager(self, actionWillAppear: actionIdentifier, on: deviceIdentifier,
                                               context: context, event: payload)
            } else if eventName == .willDisappear {
                eventHandler.connectionManager(self, actionWillDisappear: actionIdentifier, on: deviceIdentifier,
                                               context: context, event: payload)
            }

        case .deviceDidConnect:
            guard let deviceIdentifier = deviceIdentifier, let deviceInfo = deviceInfo,
                    let payload = ESDSDKDeviceInfoEventPayload(deviceInfo) else {
                        print("Got device connected event, but invalid payload for it!", to: &stdError)
                return
            }

            eventHandler.connectionManager(self, deviceDidConnect: deviceIdentifier, deviceInfo: payload)

        case .deviceDidDisconnect:
            guard let deviceIdentifier = deviceIdentifier else {
                print("Got device disconnected event, but invalid payload for it!", to: &stdError)
                return
            }

            eventHandler.connectionManager(self, deviceDidDisconnect: deviceIdentifier)

        case .applicationDidLaunch, .applicationDidTerminate:
            guard let rawPayload = rawPayload, let payload = ESDSDKApplicationLifecycleEventPayload(rawPayload) else {
                print("Got application lifecycle event, but invalid payload for it!", to: &stdError)
                return
            }

            if eventName == .applicationDidLaunch {
                eventHandler.connectionManager(self, monitoredApplicationDidLaunch: payload.applicationBundleId)
            } else if eventName == .applicationDidTerminate {
                eventHandler.connectionManager(self, monitoredApplicationDidTerminate: payload.applicationBundleId)
            }

        case .systemDidWakeUp:
            eventHandler.connectionManagerDidEncounterSystemWakeUp(self)

        case .titleParametersDidChange:
            guard let actionIdentifier = actionIdentifier, let context = context, let deviceIdentifier = deviceIdentifier,
                  let rawPayload = rawPayload, let payload = ESDSDKTitleParametersEventPayload(rawPayload) else {
                print("Got title parameters event, but invalid payload for it!", to: &stdError)
                return
            }

            eventHandler.connectionManager(self, didReceiveTitleParameters: payload, for: actionIdentifier,
                                           on: deviceIdentifier, context: context)

        case .didReceiveSettings:
            guard let actionIdentifier = actionIdentifier, let context = context, let deviceIdentifier = deviceIdentifier,
                  let rawPayload = rawPayload, let payload = ESDSDKSettingsEventPayload(rawPayload) else {
                print("Got settings event, but invalid payload for it!", to: &stdError)
                return
            }

            eventHandler.connectionManager(self, didReceiveSettings: payload, for: actionIdentifier,
                                           on: deviceIdentifier, context: context)

        case .didReceiveGlobalSettings:
            guard let rawPayload = rawPayload, let payload = ESDSDKGlobalSettingsEventPayload(rawPayload) else {
                print("Got global settings event, but invalid payload for it!", to: &stdError)
                return
            }

            eventHandler.connectionManager(self, didReceiveGlobalSettings: payload.settings)

        case .propertyInspectorDidAppear, .propertyInspectorDidDisappear:
            guard let actionIdentifier = actionIdentifier, let context = context,
                  let deviceIdentifier = deviceIdentifier else {
                print("Got property inspector event, but invalid payload for it!", to: &stdError)
                return
            }

            if eventName == .propertyInspectorDidAppear {
                eventHandler.connectionManager(self, propertyInspectorDidAppearForAction: actionIdentifier,
                                               on: deviceIdentifier, context: context)

            } else if eventName == .propertyInspectorDidDisappear {
                eventHandler.connectionManager(self, propertyInspectorDidDisappearForAction: actionIdentifier,
                                               on: deviceIdentifier, context: context)
            }
        }
    }

}
