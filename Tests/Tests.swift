//
//  Tests.swift
//  Tests
//
//  Created by Daniel Kennett on 2022-01-07.
//

import XCTest

class Tests: XCTestCase {

    func testFirstDebounceIsImmediate() async {
        let debouncer = KeyedDebouncer(delay: 0.1)
        let executed = expectation(description: "Executed")
        await debouncer.debounce(on: "immediate", action: { executed.fulfill() })
        await waitForExpectations(timeout: 0.0, handler: nil)
    }

    func testFirstDebounceIsImmediateOverMultipleKeys() async {
        let debouncer = KeyedDebouncer(delay: 0.1)
        let executed = expectation(description: "Executed First")
        let executedSecondKey = expectation(description: "Executed Second")
        await debouncer.debounce(on: "immediate-1", action: { executed.fulfill() })
        await debouncer.debounce(on: "immediate-2", action: { executedSecondKey.fulfill() })
        await waitForExpectations(timeout: 0.0, handler: nil)
    }

    func testSecondDebounceIsNotImmediate() async {
        let debouncer = KeyedDebouncer(delay: 0.1)
        let executed = expectation(description: "Executed")
        let hasntExecutedAgain = expectation(description: "Hasn't Executed Again")
        let executedAgain = expectation(description: "Has Executed Again")
        hasntExecutedAgain.isInverted = true
        await debouncer.debounce(on: "notimmediate", action: { executed.fulfill() })
        await debouncer.debounce(on: "notimmediate", action: { hasntExecutedAgain.fulfill(); executedAgain.fulfill() })

        wait(for: [executed, hasntExecutedAgain], timeout: 0.0)
        wait(for: [executedAgain], timeout: 0.2)
    }
}
