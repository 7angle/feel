// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import Foundation

public enum LocalNetwork {
    /// The Mac's LAN IPv4 address. Prefers Wi-Fi/Ethernet (en*). Skips link-local 169.254.x.x.
    public static func ipv4() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }
        var found: [(name: String, ip: String)] = []
        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let i = p {
            defer { p = i.pointee.ifa_next }
            guard let addr = i.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let flags = Int32(i.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: host)
            guard !ip.hasPrefix("169.254.") else { continue }
            found.append((String(cString: i.pointee.ifa_name), ip))
        }
        return found.first { $0.name == "en0" }?.ip ?? found.first { $0.name.hasPrefix("en") }?.ip ?? found.first?.ip
    }
}

/// What the Mac shows as a QR code. Any device with the Feel app (or a camera that opens links) joins from it.
public struct JoinLink: Equatable, Sendable {
    public var host: String
    public var port: UInt16
    public var code: String
    public var name: String

    public init(host: String, port: UInt16, code: String, name: String) {
        self.host = host
        self.port = port
        self.code = code
        self.name = name
    }

    public var url: String {
        var c = URLComponents()
        c.scheme = "feel"
        c.host = "join"
        c.queryItems = [
            URLQueryItem(name: "host", value: host),
            URLQueryItem(name: "port", value: String(port)),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "name", value: name),
        ]
        return c.string ?? ""
    }

    public init?(url: String) {
        guard let c = URLComponents(string: url), c.scheme == "feel", c.host == "join",
              let items = c.queryItems else { return nil }
        func v(_ k: String) -> String? { items.first { $0.name == k }?.value }
        guard let host = v("host"), let port = v("port").flatMap(UInt16.init), let code = v("code"), code.count == 6 else { return nil }
        self.init(host: host, port: port, code: code, name: v("name") ?? host)
    }
}
