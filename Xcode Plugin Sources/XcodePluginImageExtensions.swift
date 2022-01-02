//
// Use of this code is bound by the terms of the license set out in the
// LICENSE file included in the code's distribution.
//
//  Created by Daniel Kennett on 2022-01-02.
//

import Foundation

extension XcodeObserver.BreakpointsEnabledState {
    /// Return a toggle breakpoints action image for the given breakpoint state.
    var contextImage: Data {
        switch self {
        case .disabled: return try! Data(contentsOf: PluginImplementation.urlForImage(fileName: "BreakpointsDisabled.png"))
        case .enabled: return try! Data(contentsOf: PluginImplementation.urlForImage(fileName: "BreakpointsEnabled.png"))
        case .unknown: return try! Data(contentsOf: PluginImplementation.urlForImage(fileName: "BreakpointsUnknown.png"))
        }
    }
}

extension XcodeObserver.DebuggerState {
    /// Return a pause/continue action image for the given debugger state.
    var pauseDebuggerContextImage: Data {
        switch self {
        case .notRunning: return try! Data(contentsOf: PluginImplementation.urlForImage(fileName: "PauseDebuggerUnknown.png"))
        case .running: return try! Data(contentsOf: PluginImplementation.urlForImage(fileName: "PauseDebugger.png"))
        case .paused: return try! Data(contentsOf: PluginImplementation.urlForImage(fileName: "ResumeDebugger.png"))
        }
    }

    /// Return a view debugger action image for the given debugger state.
    var viewDebuggerContextImage: Data {
        switch self {
        case .notRunning: return try! Data(contentsOf: PluginImplementation.urlForImage(fileName: "ViewDebuggerUnknown.png"))
        case .running, .paused: return try! Data(contentsOf: PluginImplementation.urlForImage(fileName: "ViewDebugger.png"))
        }
    }
}
