//
//  PluginImplementation.swift
//  Stream Deck Xcode Plugin Binary
//
//  Created by Daniel Kennett on 2021-12-31.
//

import Foundation

class PluginImplementation {

    /// Create an event handler for the plugin.
    static func createEventHandler() -> ESDConnectionManagerDelegate {
        return XcodePluginImplementation()
    }

    /// Returns the resources directory for the plugin.
    static var pluginContainerDirectory: URL {
        // Our plugin isn't a valid Bundle (the structure is wrong and we don't have an Info.plist), but
        // the API seems to return the binary's parent directory, which with the project structure we have
        // _is_ the container. We may want to check it's a `.sdPlugin`?
        return Bundle.main.bundleURL
    }

    static func urlForImage(fileName: String) -> URL {
        return pluginContainerDirectory.appendingPathComponent("images", isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

}
