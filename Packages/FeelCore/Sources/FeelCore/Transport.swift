// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import CryptoKit
import Foundation
import Network

public enum PairingCode {
    /// 6 digits.
    public static func generate() -> String {
        String(format: "%06d", Int.random(in: 0...999_999))
    }
}

enum FeelTransport {
    /// TLS 1.2 PSK. Key derived from pairing code. Wrong code fails handshake.
    static func parameters(code: String) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let key = SHA256.hash(data: Data("feel-haptics-v1:\(code)".utf8))
        let keyData = key.withUnsafeBytes { DispatchData(bytes: $0) }
        let identity = Data("feel".utf8).withUnsafeBytes { DispatchData(bytes: $0) }
        sec_protocol_options_add_pre_shared_key(
            tls.securityProtocolOptions,
            keyData as __DispatchData,
            identity as __DispatchData
        )
        sec_protocol_options_append_tls_ciphersuite(
            tls.securityProtocolOptions,
            tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256))!
        )
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.enableKeepalive = true
        return NWParameters(tls: tls, tcp: tcp)
    }
}

/// Newline-delimited JSON messages over a TLS-PSK TCP connection.
public final class FeelConnection: @unchecked Sendable {
    public enum State: Equatable, Sendable {
        case connecting, ready, waiting(String), failed(String), closed
    }

    /// Message plus local clock time at receipt. Timestamp is taken before any queue hop.
    public var onMessage: (@Sendable (Message, TimeInterval) -> Void)?
    public var onState: (@Sendable (State) -> Void)?

    private let nw: NWConnection
    private let queue: DispatchQueue
    private var buffer = Data()

    init(_ nw: NWConnection, queue: DispatchQueue = DispatchQueue(label: "feel.connection")) {
        self.nw = nw
        self.queue = queue
    }

    public static func connect(to endpoint: NWEndpoint, code: String) -> FeelConnection {
        FeelConnection(NWConnection(to: endpoint, using: FeelTransport.parameters(code: code)))
    }

    public static func connect(host: String, port: UInt16, code: String) -> FeelConnection {
        let ep = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!)
        return connect(to: ep, code: code)
    }

    public var remoteDescription: String { "\(nw.endpoint)" }

    public func start() {
        nw.stateUpdateHandler = { [weak self] s in
            guard let self else { return }
            switch s {
            case .setup, .preparing: self.onState?(.connecting)
            case .ready:
                self.onState?(.ready)
                self.receiveLoop()
            case .waiting(let e): self.onState?(.waiting(e.localizedDescription))
            case .failed(let e): self.onState?(.failed(e.localizedDescription))
            case .cancelled: self.onState?(.closed)
            @unknown default: break
            }
        }
        nw.start(queue: queue)
    }

    public func send(_ message: Message) {
        guard let data = try? message.encoded() else { return }
        nw.send(content: data, completion: .contentProcessed { [weak self] err in
            if let err { self?.onState?(.failed(err.localizedDescription)) }
        })
    }

    /// Returns when the data left the socket. Use for bulk data, so memory stays flat.
    public func sendAndWait(_ message: Message) async {
        guard let data = try? message.encoded() else { return }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            nw.send(content: data, completion: .contentProcessed { _ in c.resume() })
        }
    }

    public func cancel() { nw.cancel() }

    private func receiveLoop() {
        nw.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            let stamp = SharedClock.now()
            if let data, !data.isEmpty {
                self.buffer.append(data)
                while let nl = self.buffer.firstIndex(of: 0x0A) {
                    let line = self.buffer[self.buffer.startIndex..<nl]
                    self.buffer = Data(self.buffer[self.buffer.index(after: nl)...])
                    if let msg = try? Message.decode(Data(line)) { self.onMessage?(msg, stamp) }
                }
                if self.buffer.count > 16 << 20 { self.nw.cancel(); return }
            }
            if error != nil || isComplete {
                self.nw.cancel()
                return
            }
            self.receiveLoop()
        }
    }
}

/// Companion side. Advertises over Bonjour, accepts editor connections.
public final class FeelListener: @unchecked Sendable {
    public var onConnection: (@Sendable (FeelConnection) -> Void)?
    public var onState: (@Sendable (NWListener.State) -> Void)?
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "feel.listener")
    private let name: String
    private let code: String

    public init(name: String, code: String) {
        self.name = name
        self.code = code
    }

    public var port: UInt16? { listener?.port?.rawValue }

    public func start(advertise: Bool = true, port: UInt16? = nil) throws {
        let params = FeelTransport.parameters(code: code)
        let l = try port.flatMap { NWEndpoint.Port(rawValue: $0) }.map { try NWListener(using: params, on: $0) } ?? NWListener(using: params)
        if advertise {
            l.service = NWListener.Service(name: name, type: FeelProtocol.bonjourType, txtRecord: NWTXTRecord([FeelProtocol.roleKey: FeelProtocol.editorRole]))
        }
        l.stateUpdateHandler = { [weak self] s in self?.onState?(s) }
        l.newConnectionHandler = { [weak self] nw in
            self?.onConnection?(FeelConnection(nw))
        }
        l.start(queue: queue)
        listener = l
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }
}

/// Editor side. Finds companions on the local network.
public final class FeelBrowser: @unchecked Sendable {
    public struct Device: Identifiable, Hashable, Sendable {
        public var id: String { name }
        public let name: String
        public let endpoint: NWEndpoint
    }

    public var onUpdate: (@Sendable ([Device]) -> Void)?
    public var onState: (@Sendable (NWBrowser.State) -> Void)?
    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "feel.browser")

    public init() {}

    public func start() {
        stop()
        let b = NWBrowser(for: .bonjourWithTXTRecord(type: FeelProtocol.bonjourType, domain: nil), using: .tcp)
        b.stateUpdateHandler = { [weak self] s in self?.onState?(s) }
        b.browseResultsChangedHandler = { [weak self] results, _ in
            let devices = results.compactMap { r -> Device? in
                // Only editors. Older builds of the phone app also advertise, and must not be listed.
                guard case let .bonjour(txt) = r.metadata, txt[FeelProtocol.roleKey] == FeelProtocol.editorRole,
                      case let .service(name, _, _, _) = r.endpoint else { return nil }
                return Device(name: name, endpoint: r.endpoint)
            }.sorted { $0.name < $1.name }
            self?.onUpdate?(devices)
        }
        b.start(queue: queue)
        browser = b
    }

    public func stop() {
        browser?.cancel()
        browser = nil
    }
}
