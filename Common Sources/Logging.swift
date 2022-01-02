//
// Use of this code is bound by the terms of the license set out in the
// LICENSE file included in the code's distribution.
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
