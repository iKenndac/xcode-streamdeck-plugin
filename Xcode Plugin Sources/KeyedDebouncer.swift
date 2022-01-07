//
//  KeyedDebouncer.swift
//  Stream Deck Plugin Binary
//
//  Created by Daniel Kennett on 2022-01-07.
//

import Foundation

actor KeyedDebouncer {

    typealias Key = String
    typealias Action = () -> Void

    /// Create a new keyed debouncer with the given delay.
    ///
    /// - Parameter delay: The time to wait before allowing actions to be executed.
    init(delay: TimeInterval) {
        delayNs = UInt64(delay * TimeInterval(NSEC_PER_SEC))
    }

    deinit {
        timeoutStorage.values.forEach({ $0.cancel() })
        timeoutStorage.removeAll()
        actionStorage.removeAll()
    }

    /// Debounce against the given key.
    ///
    /// - Note: If there is no "pending" action for the given key, the action will be executed without delay, and
    ///         subsequent actions with the same key will be delayed.
    ///
    /// - Parameters:
    ///   - key: The key to debounce against.
    ///   - action: The action to perform.
    func debounce(on key: Key, action: @escaping Action) {
        // We want our "first" call to go through immediately, so if there isn't an existing action waiting
        // for execution we execute the given action immediately. A dummy action is stored so subsequent
        // invocations on the same key get delayed.
        if actionStorage[key] == nil {
            actionStorage[key] = {}
            action()
        } else {
            actionStorage[key] = action
        }

        resetTimeout(for: key)
    }

    /// Asynchronously add a debounce against the given key.
    ///
    /// This is an asynchronous, non-isolated version of `debounce(on:action:)`.
    ///
    /// - Note: If there is no "pending" action for the given key, the action will be executed without delay, and
    ///         subsequent actions with the same key will be delayed.
    ///
    /// - Parameters:
    ///   - key: The key to debounce against.
    ///   - action: The action to perform.
    nonisolated func addDebounce(on key: Key, action: @escaping Action) {
        Task { await debounce(on: key, action: action) }
    }

    // MARK: - Internal

    private let delayNs: UInt64
    private var actionStorage: [Key: Action] = [:]
    private var timeoutStorage: [Key: Task<Void, Never>] = [:]

    private func resetTimeout(for key: Key) {
        timeoutStorage[key]?.cancel()
        timeoutStorage[key] = Task { () -> Void in
            do {
                try await Task.sleep(nanoseconds: delayNs)
                try Task.checkCancellation()
                if let action = actionStorage[key] { action() }
                actionStorage.removeValue(forKey: key)
                timeoutStorage.removeValue(forKey: key)
            } catch {}
        }
    }

}
