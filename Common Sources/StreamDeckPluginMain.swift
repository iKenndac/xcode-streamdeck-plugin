//
// Use of this code is bound by the terms of the license set out in the
// LICENSE file included in the code's distribution.
//
//  Created by Daniel Kennett on 2021-12-30.
//

import Foundation

@main
class StreamDeckPluginMain {

    private static var connectionManager: ESDConnectionManager? = nil

    static func main() {
        autoreleasepool {
            let arguments = CommandLine.arguments
            guard arguments.count == ESDSDKCommandLineInvocation.expectedNumberOfArguments else {
                print("Invalid argument count - got \(arguments.count), expected \(ESDSDKCommandLineInvocation.expectedNumberOfArguments)",
                      to: &stdError)
                exit(1)
            }

            // The plugin will be invoked with a series of arguments like:
            // …/plugin -port <port> -pluginUUID <uuid> -registerEvent <event> -info <info>
            let parameters = Array(arguments.dropFirst())
            let pairs: [[String]] = stride(from: 0, to: parameters.count, by: 2).map {
                let end = parameters.endIndex
                let chunkEnd = parameters.index($0, offsetBy: 2, limitedBy: end) ?? end
                return Array(parameters[$0..<chunkEnd])
            }

            var port: Int? = nil
            var uuid: String? = nil
            var registerEvent: String? = nil
            var info: String? = nil

            for pair in pairs {
                guard pair.count == 2, let key = pair.first, let value = pair.last else { continue }
                switch key {
                case ESDSDKCommandLineInvocation.portParameter: port = Int(value)
                case ESDSDKCommandLineInvocation.uuidParameter: uuid = value
                case ESDSDKCommandLineInvocation.infoParameter: info = value
                case ESDSDKCommandLineInvocation.registerEventParameter: registerEvent = value
                default: break
                }
            }

            guard let port = port, port > 0, let uuid = uuid, let registerEvent = registerEvent, let info = info else {
                print("Invalid parameters", to: &stdError)
                exit(1)
            }

            // To implement your own plugin, change the `createEventHandler()` method to create an instance of your
            // own logic. The `BasicPluginImplementation` class will get you started.
            let eventHandler = PluginImplementation.createEventHandler()
            connectionManager = ESDConnectionManager(port: port, uuid: uuid, registerEvent: registerEvent,
                                                     info: info, eventHandler: eventHandler)

            if connectionManager == nil {
                print("Unable to init connection manager — this usually means a failure parsing the info JSON.", to: &stdError)
                exit(1)
            }

            while true { RunLoop.current.run(mode: .default, before: .distantFuture) }
        }
    }
}


