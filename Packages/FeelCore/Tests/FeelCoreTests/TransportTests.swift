// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import XCTest
@testable import FeelCore

final class TransportTests: XCTestCase {
    func testLoopbackExchange() throws {
        let code = "123456"
        let listener = FeelListener(name: "test", code: code)
        let serverGot = expectation(description: "server got ping")
        let clientGot = expectation(description: "client got pong")
        var serverConn: FeelConnection?

        listener.onConnection = { conn in
            serverConn = conn
            conn.onMessage = { msg, _ in
                if case .ping(let id, let t0) = msg { conn.send(.pong(id: id, t0: t0, t1: 1, t2: 2)); serverGot.fulfill() }
            }
            conn.start()
        }
        let ready = expectation(description: "listening")
        listener.onState = { if case .ready = $0 { ready.fulfill() } }
        try listener.start(advertise: false)
        wait(for: [ready], timeout: 5)
        let port = try XCTUnwrap(listener.port)

        let client = FeelConnection.connect(host: "127.0.0.1", port: port, code: code)
        client.onState = { if $0 == .ready { client.send(.ping(id: 7, t0: 0.5)) } }
        client.onMessage = { msg, _ in
            if case .pong(let id, _, _, _) = msg, id == 7 { clientGot.fulfill() }
        }
        client.start()
        wait(for: [serverGot, clientGot], timeout: 10)
        client.cancel()
        serverConn?.cancel()
        listener.stop()
    }

    func testWrongCodeFailsHandshake() throws {
        let listener = FeelListener(name: "test2", code: "111111")
        listener.onConnection = { $0.start() }
        let ready = expectation(description: "listening")
        listener.onState = { if case .ready = $0 { ready.fulfill() } }
        try listener.start(advertise: false)
        wait(for: [ready], timeout: 5)

        let client = FeelConnection.connect(host: "127.0.0.1", port: try XCTUnwrap(listener.port), code: "222222")
        let failed = expectation(description: "failed")
        client.onState = { s in
            switch s {
            case .failed, .waiting, .closed: failed.fulfill()
            case .ready: XCTFail("must not connect")
            default: break
            }
        }
        client.start()
        wait(for: [failed], timeout: 10)
        client.cancel()
        listener.stop()
    }
}
