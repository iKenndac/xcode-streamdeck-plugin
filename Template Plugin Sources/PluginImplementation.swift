//
// Use of this code is bound by the terms of the license set out in the
// LICENSE file included in the code's distribution.
//
//  Created by Daniel Kennett on 2021-12-31.
//

import Foundation

class PluginImplementation {

    /// Create an event handler for the plugin. Change this to return an instance of your plugin class!
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

    /// Returns the full URL for the image with the given file name.
    ///
    /// - Note: This method assumes that images are in the `images` subdirectory of the plugin.
    static func urlForImage(fileName: String) -> URL {
        return pluginContainerDirectory.appendingPathComponent("images", isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

}
