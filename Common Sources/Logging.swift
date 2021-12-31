//
//  Logging.swift
//  Stream Deck Xcode Plugin Binary
//
//  Created by Daniel Kennett on 2021-12-31.
//

import Foundation

var stdError = FileHandle.standardError
var stdOutput = FileHandle.standardOutput

extension FileHandle: TextOutputStream {
    public func write(_ string: String) {
        write(Data(string.utf8))
    }
}
