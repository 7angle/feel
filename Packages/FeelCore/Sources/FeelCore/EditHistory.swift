// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import Foundation

/// Snapshot undo/redo. Caller records state BEFORE a change.
public struct EditHistory<State: Equatable & Sendable>: Sendable {
    private var undoStack: [State] = []
    private var redoStack: [State] = []
    public let limit: Int

    public init(limit: Int = 200) { self.limit = limit }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    public mutating func record(_ before: State) {
        if undoStack.last == before { return }
        undoStack.append(before)
        if undoStack.count > limit { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    public mutating func undo(current: State) -> State? {
        guard let prev = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return prev
    }

    public mutating func redo(current: State) -> State? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return next
    }

    public mutating func reset() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
}
