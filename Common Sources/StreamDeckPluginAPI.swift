//
// Use of this code is bound by the terms of the license set out in the
// LICENSE file included in the code's distribution.
//
//  Created by Daniel Kennett on 2021-12-30.
//

import Foundation

// This file contains values and structures for communicating with the Stream Deck application using its
// WebSocket plugin API. Everything in here is an underlying implementation detail — for creating a plugin,
// see the README file and the BasicPluginImplementation class for instructions.

let kESDSDKVersion: Int = 2

enum ESDSDKTarget: Int, Codable {
    case hardwareAndSoftware = 0
    case hardwareOnly = 1
    case softwareOnly = 2
}

enum ESDSDKDeviceType: Int, Codable {
    case streamDeck = 0
    case streamDeckMini = 1
    case streamDeckXL = 2
    case streamDeckMobile = 3
    case corsairGKeys = 4
}

// MARK: - Command Line & Initial Setup

struct ESDSDKCommandLineInvocation {
    static let expectedNumberOfArguments: Int = 9
    static let portParameter: String = "-port"
    static let uuidParameter: String = "-pluginUUID"
    static let registerEventParameter: String = "-registerEvent"
    static let infoParameter: String = "-info"
}

// MARK: - Types

typealias ESDSDKContext = String
typealias ESDSDKSettings = (Any & Codable)
typealias ESDSDKMessageCompletionHandler = (ESDSDKError?) -> Void

struct ESDSDKState: RawRepresentable, ExpressibleByIntegerLiteral {
    static let all = ESDSDKState(rawValue: -1) // Special value - shouldn't make it to the raw protocol.

    init(integerLiteral value: Int) { rawValue = value }
    init(rawValue value: Int) { rawValue = value }
    let rawValue: Int
}

enum ESDSDKError: Error {
    case tranportError(Error)
    case invalidInput
    case notConnected
}

enum ESDSDKPlatform: String, Codable {
    case mac
    case windows
}

struct ESDSDKDeviceSize: Codable {

    init?(_ payload: [String: Any]) {
        guard let columns = payload["columns"] as? Int, let rows = payload["rows"] as? Int else { return nil }
        self.columns = columns
        self.rows = rows
    }

    let columns: Int
    let rows: Int
}

struct ESDSDKDeviceCoordinate: Codable {

    init?(_ payload: [String: Any]) {
        guard let column = payload["column"] as? Int, let row = payload["row"] as? Int else { return nil }
        self.column = column
        self.row = row
    }

    let column: Int
    let row: Int
}

enum ESDSDKTextAlignment: String, Codable {
    case top
    case middle
    case bottom
}

/// Information about a connected device.
struct ESDSDKDeviceInfo: Codable {
    let id: String
    let name: String
    let size: ESDSDKDeviceSize
    let type: ESDSDKDeviceType? // Can be nil.
}

/// Information about the host Stream Deck application and platform.
struct ESDSDKApplicationInfo: Codable {
    let language: String
    let platform: ESDSDKPlatform
    let platformVersion: String
    let version: String
}

struct ESDSDKColors: Codable {
    let buttonPressedBackgroundColor: String
    let buttonPressedBorderColor: String
    let buttonPressedTextColor: String
    let disabledColor: String
    let highlightColor: String
}

struct ESDSDKPluginRegistrationInfo: Codable {
    let application: ESDSDKApplicationInfo
    let devicePixelRatio: Int
    let colors: ESDSDKColors
    let devices: [ESDSDKDeviceInfo]

    var isRetina: Bool {
        return devicePixelRatio > 1
    }
}

// MARK: - WebSocket Messages

protocol ESDSDKMessage {
    var encodedMessage: Data? { get }
}

enum ESDSDKCommandName: String, Codable {
    case setSettings
    case getSettings
    case setGlobalSettings
    case getGlobalSettings
    case openUrl
    case logMessage

    case showAlert
    case showOk

    case setState
    case setTitle
    case setImage

    case switchToProfile
}

struct ESDSDKRegisterPluginMessage: Codable {
    let event: String
    let uuid: String
}

struct ESDSDKGenericWithContextMessage: ESDSDKMessage {
    let event: ESDSDKCommandName
    let context: ESDSDKContext

    var encodedMessage: Data? {
        let json = ["event": event.rawValue, "context": context]
        return try? JSONSerialization.data(withJSONObject: json, options: [])
    }
}


struct ESDSDKSetSettingsMessage: ESDSDKMessage {
    let event: ESDSDKCommandName = .setSettings
    let context: ESDSDKContext
    let payload: ESDSDKSettings

    var encodedMessage: Data? {
        let json = ["event": event.rawValue, "context": context, "payload": payload]
        return try? JSONSerialization.data(withJSONObject: json, options: [])
    }
}

struct ESDSDKSetGlobalSettingsMessage: ESDSDKMessage {
    let event: ESDSDKCommandName = .setGlobalSettings
    let context: String // Plugin UUID
    let payload: ESDSDKSettings

    var encodedMessage: Data? {
        let json = ["event": event.rawValue, "context": context, "payload": payload]
        return try? JSONSerialization.data(withJSONObject: json, options: [])
    }
}

struct ESDSDKOpenUrlMessage: ESDSDKMessage {
    let event: ESDSDKCommandName = .openUrl
    let url: String

    var encodedMessage: Data? {
        let json: [String: Any] = ["event": event.rawValue, "payload": ["url": url]]
        return try? JSONSerialization.data(withJSONObject: json, options: [])
    }
}

struct ESDSDKLogMessage: ESDSDKMessage {
    let event: ESDSDKCommandName = .logMessage
    let message: String

    var encodedMessage: Data? {
        let json: [String: Any] = ["event": event.rawValue, "payload": ["message": message]]
        return try? JSONSerialization.data(withJSONObject: json, options: [])
    }
}

struct ESDSDKSetStateMessage: ESDSDKMessage {
    let event: ESDSDKCommandName = .setState
    let context: ESDSDKContext
    let state: ESDSDKState

    var encodedMessage: Data? {
        let json: [String: Any] = ["event": event.rawValue, "context": context, "payload": ["state": state.rawValue]]
        return try? JSONSerialization.data(withJSONObject: json, options: [])
    }
}

struct ESDSDKSetTitleMessage: ESDSDKMessage {
    let event: ESDSDKCommandName = .setTitle
    let title: String?
    let state: ESDSDKState
    let context: ESDSDKContext
    let target: ESDSDKTarget

    var encodedMessage: Data? {
        var payload: [String: Any] = ["target": target.rawValue]

        // The "all" value is something we invented — it's expressed by an absence of a value in the underlying protocol.
        if state != .all { payload["state"] = state.rawValue }
        if let title = title { payload["title"] = title }

        let json: [String: Any] = ["event": event.rawValue, "context": context, "payload": payload]
        return try? JSONSerialization.data(withJSONObject: json, options: [])
    }
}

struct ESDSDKSetImageMessage: ESDSDKMessage {
    let event: ESDSDKCommandName = .setImage
    let encodedImage: String?
    let state: ESDSDKState
    let context: ESDSDKContext
    let target: ESDSDKTarget

    var encodedMessage: Data? {
        var payload: [String: Any] = ["target": target.rawValue]

        // The "all" value is something we invented — it's expressed by an absence of a value in the underlying protocol.
        if state != .all { payload["state"] = state.rawValue }
        if let image = encodedImage { payload["image"] = image }

        let json: [String: Any] = ["event": event.rawValue, "context": context, "payload": payload]
        return try? JSONSerialization.data(withJSONObject: json, options: [])
    }
}

struct ESDSDKSwitchToProfileMessage: ESDSDKMessage {
    let event: ESDSDKCommandName = .switchToProfile
    let context: ESDSDKContext // Plugin UUID
    let deviceIdentifier: String
    let profileName: String?

    var encodedMessage: Data? {
        var json: [String: Any] = ["event": event.rawValue, "context": context, "device": deviceIdentifier]
        // If the profile field is missing or empty, the Stream Deck application will switch back to the
        // previously selected profile.
        let name = profileName ?? ""
        json["payload"] = ["profile": name]
        return try? JSONSerialization.data(withJSONObject: json, options: [])
    }
}


// MARK: - Events

enum ESDSDKEventCommonKeys: String {
    case action
    case event
    case context
    case payload
    case device
    case deviceInfo
}

enum ESDSDKEventName: String, Codable {
    case keyDown = "keyDown"
    case keyUp = "keyUp"
    case willAppear = "willAppear"
    case willDisappear = "willDisappear"
    case deviceDidConnect = "deviceDidConnect"
    case deviceDidDisconnect = "deviceDidDisconnect"
    case applicationDidLaunch = "applicationDidLaunch"
    case applicationDidTerminate = "applicationDidTerminate"
    case systemDidWakeUp = "systemDidWakeUp"
    case titleParametersDidChange = "titleParametersDidChange"
    case didReceiveSettings = "didReceiveSettings"
    case didReceiveGlobalSettings = "didReceiveGlobalSettings"
    case propertyInspectorDidAppear = "propertyInspectorDidAppear"
    case propertyInspectorDidDisappear = "propertyInspectorDidDisappear"
}

struct ESDSDKKeyEventPayload {

    init?(_ payload: [String: Any]) {
        settings = payload["settings"] as? ESDSDKSettings
        let rawState = payload["state"] as? Int
        let rawUserDesiredState = payload["userDesiredState"] as? Int

        guard let isInMultiAction = payload["isInMultiAction"] as? Bool else { return nil }

        guard let rawCoordinates = payload["coordinates"] as? [String: Any],
              let coordinates = ESDSDKDeviceCoordinate(rawCoordinates) else { return nil }

        if let rawState = rawState {
            self.state = ESDSDKState(rawValue: rawState)
        } else {
            self.state = nil
        }

        if let rawUserDesiredState = rawUserDesiredState {
            self.userDesiredState = ESDSDKState(rawValue: rawUserDesiredState)
        } else {
            self.userDesiredState = nil
        }

        self.isInMultiAction = isInMultiAction
        self.coordinates = coordinates
    }

    let settings: ESDSDKSettings?
    let coordinates: ESDSDKDeviceCoordinate
    let state: ESDSDKState?
    let userDesiredState: ESDSDKState?
    let isInMultiAction: Bool
}

struct ESDSDKVisibilityEventPayload {

    init?(_ payload: [String: Any]) {
        settings = payload["settings"] as? ESDSDKSettings
        let rawState = payload["state"] as? Int

        guard let isInMultiAction = payload["isInMultiAction"] as? Bool else { return nil }

        if let rawState = rawState {
            self.state = ESDSDKState(rawValue: rawState)
        } else {
            self.state = nil
        }

        guard let rawCoordinates = payload["coordinates"] as? [String: Any],
              let coordinates = ESDSDKDeviceCoordinate(rawCoordinates) else { return nil }

        self.isInMultiAction = isInMultiAction
        self.coordinates = coordinates
    }

    let settings: ESDSDKSettings?
    let coordinates: ESDSDKDeviceCoordinate
    let state: ESDSDKState?
    let isInMultiAction: Bool
}

struct ESDSDKDeviceInfoEventPayload: Codable {

    init?(_ payload: [String: Any]) {
        guard let rawType = payload["type"] as? Int, let type = ESDSDKDeviceType(rawValue: rawType),
            let rawSize = payload["size"] as? [String: Any], let size = ESDSDKDeviceSize(rawSize),
            let name = payload["name"] as? String else { return nil }

        self.name = name
        self.type = type
        self.size = size
    }

    let name: String
    let type: ESDSDKDeviceType
    let size: ESDSDKDeviceSize
}

struct ESDSDKApplicationLifecycleEventPayload: Codable {

    init?(_ payload: [String: Any]) {
        guard let applicationBundleId = payload["application"] as? String else { return nil }
        self.applicationBundleId = applicationBundleId
    }

    let applicationBundleId: String
}

struct ESDSDKGlobalSettingsEventPayload {
    init?(_ payload: [String: Any]) {
        settings = payload["settings"] as? ESDSDKSettings
    }

    let settings: ESDSDKSettings?
}

struct ESDSDKSettingsEventPayload {

    init?(_ payload: [String: Any]) {
        settings = payload["settings"] as? ESDSDKSettings
        guard let isInMultiAction = payload["isInMultiAction"] as? Bool else { return nil }

        guard let rawCoordinates = payload["coordinates"] as? [String: Any],
              let coordinates = ESDSDKDeviceCoordinate(rawCoordinates) else { return nil }

        self.isInMultiAction = isInMultiAction
        self.coordinates = coordinates
    }

    let settings: ESDSDKSettings?
    let coordinates: ESDSDKDeviceCoordinate
    let isInMultiAction: Bool
}

struct ESDSDKTitleParametersEventPayload {

    init?(_ payload: [String: Any]) {
        settings = payload["settings"] as? ESDSDKSettings
        let rawState = payload["state"] as? Int
        guard let title = payload["title"] as? String else { return nil }

        guard let rawCoordinates = payload["coordinates"] as? [String: Any],
              let coordinates = ESDSDKDeviceCoordinate(rawCoordinates) else { return nil }

        guard let rawParameters = payload["titleParameters"] as? [String: Any],
              let titleParameters = ESDSDKTitleParameters(rawParameters) else { return nil }

        if let rawState = rawState {
            self.state = ESDSDKState(rawValue: rawState)
        } else {
            self.state = nil
        }

        self.coordinates = coordinates
        self.title = title
        self.titleParameters = titleParameters
    }

    let settings: ESDSDKSettings?
    let coordinates: ESDSDKDeviceCoordinate
    let state: ESDSDKState?
    let title: String
    let titleParameters: ESDSDKTitleParameters
}

struct ESDSDKTitleParameters: Codable {

    init?(_ payload: [String: Any]) {

        guard let fontFamily = payload["fontFamily"] as? String, let fontSize = payload["fontSize"] as? Int,
              let fontStyle = payload["fontStyle"] as? String, let fontUnderline = payload["fontUnderline"] as? Bool,
              let showTitle = payload["showTitle"] as? Bool, let titleColor = payload["titleColor"] as? String else {
                  return nil
              }

        guard let rawTitleAlignment = payload["titleAlignment"] as? String,
              let titleAlignment = ESDSDKTextAlignment(rawValue: rawTitleAlignment) else { return nil }

        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.fontStyle = fontStyle
        self.fontUnderline = fontUnderline
        self.showTitle = showTitle
        self.titleAlignment = titleAlignment
        self.titleColor = titleColor
    }

    let fontFamily: String
    let fontSize: Int
    let fontStyle: String
    let fontUnderline: Bool
    let showTitle: Bool
    let titleAlignment: ESDSDKTextAlignment
    let titleColor: String
}

