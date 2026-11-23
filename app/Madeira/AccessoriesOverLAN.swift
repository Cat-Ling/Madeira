import Foundation

// MARK: - Pure MAOL v1 Wire Protocol (host-tested without UIKit)

enum AOLPacketType: UInt8 {
    case discover = 0x00
    case hello = 0x01
    case ping = 0x02
    case keyEvent = 0x03
    case mouseMotion = 0x04
    case mouseButton = 0x05
    case gamepadState = 0x06
    case releaseAll = 0x07

    case announce = 0x80
    case helloAck = 0x81
    case pong = 0x82
    case rumble = 0x83
    case disconnect = 0x84
}

struct AOLHeader: Equatable {
    var version: UInt8
    var type: AOLPacketType
    var seq: UInt32
}

struct AOLAnnounce: Equatable {
    var port: UInt16
    var flags: UInt8
    var deviceName: String
}

struct AOLHello: Equatable {
    var flags: UInt8
    var deviceMask: UInt8
    var authTag: [UInt8]
    var hostName: String

    var hasKeyboard: Bool { (deviceMask & 0x01) != 0 }
    var hasMouse: Bool { (deviceMask & 0x02) != 0 }
    var gamepadCount: Int { Int((deviceMask >> 4) & 0x0F) }
}

struct AOLHelloAck: Equatable {
    var status: UInt8
    var sessionActive: Bool
    var tvActive: Bool
    var deviceName: String
}

struct AOLKeyEvent: Equatable {
    var hidUsage: UInt16
    var pressed: Bool
    var held: [UInt16]
}

struct AOLMouseMotion: Equatable {
    var dx: Int16
    var dy: Int16
    var wheelX: Int16
    var wheelY: Int16
    var buttons: UInt8
}

struct AOLMouseButton: Equatable {
    var buttons: UInt8
    var changedMask: UInt8
}

struct AOLGamepadState: Equatable {
    var slot: UInt8
    var connected: Bool
    var buttons: UInt16
    var leftTrigger: UInt8
    var rightTrigger: UInt8
    var lx: Int16
    var ly: Int16
    var rx: Int16
    var ry: Int16
}

struct AOLRumble: Equatable {
    var slot: UInt8
    var leftMotor: UInt16
    var rightMotor: UInt16
}

enum AOLPacket: Equatable {
    case discover
    case announce(AOLAnnounce)
    case hello(AOLHello)
    case helloAck(AOLHelloAck)
    case ping(UInt64)
    case pong(UInt64)
    case keyEvent(AOLKeyEvent)
    case mouseMotion(AOLMouseMotion)
    case mouseButton(AOLMouseButton)
    case gamepadState(AOLGamepadState)
    case releaseAll(UInt8)
    case rumble(AOLRumble)
    case disconnect(UInt8)

    var packetType: AOLPacketType {
        switch self {
        case .discover: return .discover
        case .announce: return .announce
        case .hello: return .hello
        case .helloAck: return .helloAck
        case .ping: return .ping
        case .pong: return .pong
        case .keyEvent: return .keyEvent
        case .mouseMotion: return .mouseMotion
        case .mouseButton: return .mouseButton
        case .gamepadState: return .gamepadState
        case .releaseAll: return .releaseAll
        case .rumble: return .rumble
        case .disconnect: return .disconnect
        }
    }
}

enum AOLProtocol {
    static let defaultPort: UInt16 = 37419
    static let version: UInt8 = 1
    static let headerSize = 8
    static let maxHeldKeys = 8

    static let statusOK: UInt8 = 0
    static let statusBadPIN: UInt8 = 1
    static let statusDisabled: UInt8 = 2

    static let mouseButtonLeft: UInt8 = 1 << 0
    static let mouseButtonRight: UInt8 = 1 << 1
    static let mouseButtonMiddle: UInt8 = 1 << 2
    static let mouseButtonX1: UInt8 = 1 << 3
    static let mouseButtonX2: UInt8 = 1 << 4

    static func authTag(pin: String) -> [UInt8] {
        guard !pin.isEmpty else { return [UInt8](repeating: 0, count: 8) }
        let digest = sha256(Data(("MAOL-v1:" + pin).utf8))
        return Array(digest.prefix(8))
    }

    static func encode(seq: UInt32, packet: AOLPacket) -> Data {
        var out = Data()
        out.reserveCapacity(headerSize + 32)
        out.append(0x4D) // 'M'
        out.append(0x41) // 'A'
        out.append(version)
        out.append(packet.packetType.rawValue)
        appendUInt32LE(&out, seq)

        switch packet {
        case .discover:
            break
        case .announce(let p):
            appendUInt16LE(&out, p.port)
            out.append(p.flags)
            appendShortString(&out, p.deviceName)
        case .hello(let p):
            out.append(p.flags)
            out.append(p.deviceMask)
            var tag = [UInt8](repeating: 0, count: 8)
            for i in 0..<min(8, p.authTag.count) { tag[i] = p.authTag[i] }
            out.append(contentsOf: tag)
            appendShortString(&out, p.hostName)
        case .helloAck(let p):
            out.append(p.status)
            out.append(p.sessionActive ? 1 : 0)
            out.append(p.tvActive ? 1 : 0)
            appendShortString(&out, p.deviceName)
        case .ping(let ts), .pong(let ts):
            appendUInt64LE(&out, ts)
        case .keyEvent(let p):
            let held = Array(p.held.prefix(maxHeldKeys))
            appendUInt16LE(&out, p.hidUsage)
            out.append(p.pressed ? 1 : 0)
            out.append(UInt8(held.count))
            for u in held { appendUInt16LE(&out, u) }
        case .mouseMotion(let p):
            appendUInt16LE(&out, UInt16(bitPattern: p.dx))
            appendUInt16LE(&out, UInt16(bitPattern: p.dy))
            appendUInt16LE(&out, UInt16(bitPattern: p.wheelX))
            appendUInt16LE(&out, UInt16(bitPattern: p.wheelY))
            out.append(p.buttons)
        case .mouseButton(let p):
            out.append(p.buttons)
            out.append(p.changedMask)
        case .gamepadState(let p):
            out.append(p.slot)
            out.append(p.connected ? 1 : 0)
            appendUInt16LE(&out, p.buttons)
            out.append(p.leftTrigger)
            out.append(p.rightTrigger)
            appendUInt16LE(&out, UInt16(bitPattern: p.lx))
            appendUInt16LE(&out, UInt16(bitPattern: p.ly))
            appendUInt16LE(&out, UInt16(bitPattern: p.rx))
            appendUInt16LE(&out, UInt16(bitPattern: p.ry))
        case .releaseAll(let reason), .disconnect(let reason):
            out.append(reason)
        case .rumble(let p):
            out.append(p.slot)
            appendUInt16LE(&out, p.leftMotor)
            appendUInt16LE(&out, p.rightMotor)
        }
        return out
    }

    static func decode(_ data: Data) -> (header: AOLHeader, packet: AOLPacket)? {
        let bytes = [UInt8](data)
        guard bytes.count >= headerSize else { return nil }
        guard bytes[0] == 0x4D, bytes[1] == 0x41 else { return nil }
        guard bytes[2] == version else { return nil }
        guard let kind = AOLPacketType(rawValue: bytes[3]) else { return nil }

        let header = AOLHeader(version: bytes[2], type: kind, seq: readUInt32LE(bytes, 4))
        let body = Array(bytes[headerSize...])

        switch kind {
        case .discover:
            return (header, .discover)
        case .announce:
            guard body.count >= 4 else { return nil }
            guard let (name, _) = readShortString(body, offset: 3) else { return nil }
            return (header, .announce(AOLAnnounce(port: readUInt16LE(body, 0), flags: body[2], deviceName: name)))
        case .hello:
            guard body.count >= 11 else { return nil }
            guard let (host, _) = readShortString(body, offset: 10) else { return nil }
            return (header, .hello(AOLHello(
                flags: body[0],
                deviceMask: body[1],
                authTag: Array(body[2..<10]),
                hostName: host
            )))
        case .helloAck:
            guard body.count >= 4 else { return nil }
            guard let (name, _) = readShortString(body, offset: 3) else { return nil }
            return (header, .helloAck(AOLHelloAck(
                status: body[0],
                sessionActive: body[1] != 0,
                tvActive: body[2] != 0,
                deviceName: name
            )))
        case .ping:
            guard body.count >= 8 else { return nil }
            return (header, .ping(readUInt64LE(body, 0)))
        case .pong:
            guard body.count >= 8 else { return nil }
            return (header, .pong(readUInt64LE(body, 0)))
        case .keyEvent:
            guard body.count >= 4 else { return nil }
            let count = Int(body[3])
            guard count <= maxHeldKeys, body.count >= 4 + count * 2 else { return nil }
            var held: [UInt16] = []
            held.reserveCapacity(count)
            for i in 0..<count {
                held.append(readUInt16LE(body, 4 + i * 2))
            }
            return (header, .keyEvent(AOLKeyEvent(
                hidUsage: readUInt16LE(body, 0),
                pressed: body[2] != 0,
                held: held
            )))
        case .mouseMotion:
            guard body.count >= 9 else { return nil }
            return (header, .mouseMotion(AOLMouseMotion(
                dx: Int16(bitPattern: readUInt16LE(body, 0)),
                dy: Int16(bitPattern: readUInt16LE(body, 2)),
                wheelX: Int16(bitPattern: readUInt16LE(body, 4)),
                wheelY: Int16(bitPattern: readUInt16LE(body, 6)),
                buttons: body[8]
            )))
        case .mouseButton:
            guard body.count >= 2 else { return nil }
            return (header, .mouseButton(AOLMouseButton(buttons: body[0], changedMask: body[1])))
        case .gamepadState:
            guard body.count >= 14 else { return nil }
            return (header, .gamepadState(AOLGamepadState(
                slot: body[0],
                connected: body[1] != 0,
                buttons: readUInt16LE(body, 2),
                leftTrigger: body[4],
                rightTrigger: body[5],
                lx: Int16(bitPattern: readUInt16LE(body, 6)),
                ly: Int16(bitPattern: readUInt16LE(body, 8)),
                rx: Int16(bitPattern: readUInt16LE(body, 10)),
                ry: Int16(bitPattern: readUInt16LE(body, 12))
            )))
        case .releaseAll:
            guard body.count >= 1 else { return nil }
            return (header, .releaseAll(body[0]))
        case .rumble:
            guard body.count >= 5 else { return nil }
            return (header, .rumble(AOLRumble(
                slot: body[0],
                leftMotor: readUInt16LE(body, 1),
                rightMotor: readUInt16LE(body, 3)
            )))
        case .disconnect:
            guard body.count >= 1 else { return nil }
            return (header, .disconnect(body[0]))
        }
    }

    private static func appendUInt16LE(_ data: inout Data, _ v: UInt16) {
        data.append(UInt8(v & 0xFF))
        data.append(UInt8((v >> 8) & 0xFF))
    }

    private static func appendUInt32LE(_ data: inout Data, _ v: UInt32) {
        data.append(UInt8(v & 0xFF))
        data.append(UInt8((v >> 8) & 0xFF))
        data.append(UInt8((v >> 16) & 0xFF))
        data.append(UInt8((v >> 24) & 0xFF))
    }

    private static func appendUInt64LE(_ data: inout Data, _ v: UInt64) {
        for shift in stride(from: 0, to: 64, by: 8) {
            data.append(UInt8((v >> shift) & 0xFF))
        }
    }

    private static func appendShortString(_ data: inout Data, _ value: String) {
        var utf8 = Array(value.utf8)
        if utf8.count > 255 {
            utf8 = Array(utf8.prefix(255))
        }
        data.append(UInt8(utf8.count))
        data.append(contentsOf: utf8)
    }

    private static func readUInt16LE(_ b: [UInt8], _ o: Int) -> UInt16 {
        UInt16(b[o]) | (UInt16(b[o + 1]) << 8)
    }

    private static func readUInt32LE(_ b: [UInt8], _ o: Int) -> UInt32 {
        UInt32(b[o])
            | (UInt32(b[o + 1]) << 8)
            | (UInt32(b[o + 2]) << 16)
            | (UInt32(b[o + 3]) << 24)
    }

    private static func readUInt64LE(_ b: [UInt8], _ o: Int) -> UInt64 {
        var v: UInt64 = 0
        for i in 0..<8 {
            v |= UInt64(b[o + i]) << (i * 8)
        }
        return v
    }

    private static func readShortString(_ b: [UInt8], offset: Int) -> (String, Int)? {
        guard offset < b.count else { return nil }
        let n = Int(b[offset])
        let end = offset + 1 + n
        guard end <= b.count else { return nil }
        return (String(decoding: b[(offset + 1)..<end], as: UTF8.self), end)
    }

    /// Minimal self-contained RFC 6234 SHA-256 so protocol tests run cleanly
    /// on Linux without CryptoKit.
    static func sha256(_ message: Data) -> [UInt8] {
        var bytes = [UInt8](message)
        let bitLen = UInt64(bytes.count) * 8
        bytes.append(0x80)
        while (bytes.count % 64) != 56 {
            bytes.append(0)
        }
        for shift in stride(from: 56, through: 0, by: -8) {
            bytes.append(UInt8((bitLen >> shift) & 0xFF))
        }

        let k: [UInt32] = [
            0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
            0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
            0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
            0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
            0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
            0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
            0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
            0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
        ]
        var h: [UInt32] = [
            0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
            0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
        ]
        func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }

        for chunkStart in stride(from: 0, to: bytes.count, by: 64) {
            var w = [UInt32](repeating: 0, count: 64)
            for i in 0..<16 {
                let j = chunkStart + i * 4
                w[i] = (UInt32(bytes[j]) << 24) | (UInt32(bytes[j + 1]) << 16)
                    | (UInt32(bytes[j + 2]) << 8) | UInt32(bytes[j + 3])
            }
            for i in 16..<64 {
                let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
                let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }

            var a = h[0], b = h[1], c = h[2], d = h[3]
            var e = h[4], f = h[5], g = h[6], hv = h[7]
            for i in 0..<64 {
                let S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                let ch = (e & f) ^ ((~e) & g)
                let temp1 = hv &+ S1 &+ ch &+ k[i] &+ w[i]
                let S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let temp2 = S0 &+ maj

                hv = g; g = f; f = e; e = d &+ temp1
                d = c; c = b; b = a; a = temp1 &+ temp2
            }
            h[0] = h[0] &+ a; h[1] = h[1] &+ b; h[2] = h[2] &+ c; h[3] = h[3] &+ d
            h[4] = h[4] &+ e; h[5] = h[5] &+ f; h[6] = h[6] &+ g; h[7] = h[7] &+ hv
        }

        var out = [UInt8]()
        out.reserveCapacity(32)
        for v in h {
            out.append(UInt8((v >> 24) & 0xFF))
            out.append(UInt8((v >> 16) & 0xFF))
            out.append(UInt8((v >> 8) & 0xFF))
            out.append(UInt8(v & 0xFF))
        }
        return out
    }
}

/// Self-healing key state tracker for UDP KEY_EVENT packets.
/// Every KEY_EVENT carries up to `AOLProtocol.maxHeldKeys` currently held HID
/// usages alongside the edge transition so lost release packets converge.
struct AOLHeldKeyReconciler {
    private(set) var heldUsages: Set<UInt16> = []

    @discardableResult
    mutating func apply(_ event: AOLKeyEvent) -> Set<UInt16> {
        if event.held.count < AOLProtocol.maxHeldKeys {
            var next = Set(event.held)
            if event.pressed {
                next.insert(event.hidUsage)
            } else {
                next.remove(event.hidUsage)
            }
            heldUsages = next
        } else {
            if event.pressed {
                heldUsages.insert(event.hidUsage)
            } else {
                heldUsages.remove(event.hidUsage)
            }
        }
        return heldUsages
    }

    mutating func reset() {
        heldUsages.removeAll()
    }
}

#if canImport(UIKit)
import UIKit
import SwiftUI
import Network
import Combine
import Darwin

private extension AOLMouseMotion {
    static let allMouseButtons: [(mask: UInt8, button: MouseButton)] = [
        (AOLProtocol.mouseButtonLeft, .left),
        (AOLProtocol.mouseButtonRight, .right),
        (AOLProtocol.mouseButtonMiddle, .middle),
        (AOLProtocol.mouseButtonX1, .x1),
        (AOLProtocol.mouseButtonX2, .x2),
    ]
}

enum AOLMouseButtonMask {
    static func buttons(from mask: UInt8) -> Set<MouseButton> {
        var out: Set<MouseButton> = []
        for entry in AOLMouseMotion.allMouseButtons where (mask & entry.mask) != 0 {
            out.insert(entry.button)
        }
        return out
    }
}

@MainActor
final class AccessoriesOverLAN: ObservableObject {
    static let shared = AccessoriesOverLAN()

    private enum Keys {
        static let enabled = "aol.enabled"
        static let port = "aol.port"
        static let requirePIN = "aol.requirePIN"
        static let pin = "aol.pin"
        static let bonjour = "aol.bonjour"
    }

    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Keys.enabled)
            if enabled { startListener() } else { stopListener(reason: 2) }
        }
    }

    @Published var port: Int {
        didSet {
            let clamped = min(max(port, 1024), 65535)
            if clamped != port { port = clamped; return }
            UserDefaults.standard.set(clamped, forKey: Keys.port)
            if enabled { restartListener() }
        }
    }

    @Published var requirePIN: Bool {
        didSet {
            UserDefaults.standard.set(requirePIN, forKey: Keys.requirePIN)
            syncDisplaySnapshot()
        }
    }

    @Published var pin: String {
        didSet {
            let filtered = String(pin.filter { $0.isNumber }.prefix(8))
            if filtered != pin { pin = filtered; return }
            UserDefaults.standard.set(filtered, forKey: Keys.pin)
        }
    }

    @Published var bonjourEnabled: Bool {
        didSet {
            UserDefaults.standard.set(bonjourEnabled, forKey: Keys.bonjour)
            if enabled { restartListener() }
        }
    }

    @Published private(set) var listening = false
    @Published private(set) var listenerError: String?
    @Published private(set) var clientConnected = false
    @Published private(set) var clientHost = ""
    @Published private(set) var clientCapabilities = (keyboard: false, mouse: false, gamepads: 0)
    @Published private(set) var latencyMs: Int?
    @Published private(set) var localAddresses: [String] = []
    @Published private(set) var packetsReceived: UInt64 = 0

    private let ioQueue = DispatchQueue(label: "madeira.aol.udp", qos: .userInteractive)
    private var listener: NWListener?
    private var activeConnection: NWConnection?
    private var txSeq: UInt32 = 1
    private var keyReconciler = AOLHeldKeyReconciler()
    private var rumbleTimer: DispatchSourceTimer?
    private var watchdogTimer: DispatchSourceTimer?
    private var lastPacketAt: TimeInterval = 0
    private var lastVibrationSerial = [UInt32](repeating: 0, count: 4)
    private var rumbleEnabled = false

    private init() {
        let d = UserDefaults.standard
        let defaultPIN: String
        if let saved = d.string(forKey: Keys.pin), !saved.isEmpty {
            defaultPIN = saved
        } else {
            defaultPIN = String(format: "%04d", Int.random(in: 1000...9999))
            d.set(defaultPIN, forKey: Keys.pin)
        }
        let savedPort = d.integer(forKey: Keys.port)
        self.enabled = d.object(forKey: Keys.enabled) == nil ? false : d.bool(forKey: Keys.enabled)
        self.port = savedPort >= 1024 && savedPort <= 65535 ? savedPort : Int(AOLProtocol.defaultPort)
        self.requirePIN = d.object(forKey: Keys.requirePIN) == nil ? true : d.bool(forKey: Keys.requirePIN)
        self.pin = defaultPIN
        self.bonjourEnabled = d.object(forKey: Keys.bonjour) == nil ? true : d.bool(forKey: Keys.bonjour)
        refreshLocalAddresses()
    }

    func startIfEnabled() {
        refreshLocalAddresses()
        if enabled { startListener() }
    }

    func regeneratePIN() {
        pin = String(format: "%04d", Int.random(in: 1000...9999))
    }

    func disconnectClient() {
        disconnectActiveClient(reason: 1)
    }

    func refreshLocalAddresses() {
        var addrs: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddr) == 0, let first = ifaddr {
            defer { freeifaddrs(first) }
            var cur: UnsafeMutablePointer<ifaddrs>? = first
            while let ptr = cur {
                let flags = Int32(ptr.pointee.ifa_flags)
                let up = (flags & (IFF_UP | IFF_RUNNING)) == (IFF_UP | IFF_RUNNING)
                let loopback = (flags & IFF_LOOPBACK) != 0
                if up, !loopback, let addr = ptr.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
                    var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                                   &hostBuffer, socklen_t(hostBuffer.count),
                                   nil, 0, NI_NUMERICHOST) == 0 {
                        let ip = String(cString: hostBuffer)
                        if !addrs.contains(ip) { addrs.append(ip) }
                    }
                }
                cur = ptr.pointee.ifa_next
            }
        }
        localAddresses = addrs
    }

    private func restartListener() {
        stopListener(reason: 3)
        startListener()
    }

    private func startListener() {
        guard listener == nil else { return }
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            listenerError = "Invalid UDP port \(port)"
            return
        }
        refreshLocalAddresses()
        do {
            let params = NWParameters.udp
            params.allowLocalEndpointReuse = true
            let newListener = try NWListener(using: params, on: nwPort)
            if bonjourEnabled {
                newListener.service = NWListener.Service(name: UIDevice.current.name, type: "_madeira-aol._udp")
            }
            newListener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    self?.handleListenerState(state)
                }
            }
            newListener.newConnectionHandler = { [weak self] connection in
                self?.acceptConnection(connection)
            }
            newListener.start(queue: ioQueue)
            listener = newListener
            listenerError = nil
            LogStore.shared.log("[aol] listening UDP :\(port) bonjour=\(bonjourEnabled ? 1 : 0)")
        } catch {
            listenerError = error.localizedDescription
            listening = false
            LogStore.shared.log("[aol] failed to listen on :\(port): \(error.localizedDescription)")
        }
    }

    private func stopListener(reason: UInt8) {
        disconnectActiveClient(reason: reason)
        listener?.cancel()
        listener = nil
        listening = false
        syncDisplaySnapshot()
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            listening = true
            listenerError = nil
            refreshLocalAddresses()
        case .failed(let error):
            listening = false
            listenerError = error.localizedDescription
            listener?.cancel()
            listener = nil
        case .cancelled:
            listening = false
        default:
            break
        }
    }

    private nonisolated func acceptConnection(_ connection: NWConnection) {
        connection.start(queue: ioQueue)
        receiveLoop(on: connection)
    }

    private nonisolated func receiveLoop(on connection: NWConnection) {
        connection.receiveMessage { [weak self] content, _, _, error in
            if let data = content, !data.isEmpty {
                self?.handleRawDatagram(data, on: connection)
            }
            if error == nil && connection.state != .cancelled {
                self?.receiveLoop(on: connection)
            }
        }
    }

    private nonisolated func handleRawDatagram(_ data: Data, on connection: NWConnection) {
        guard let decoded = AOLProtocol.decode(data) else { return }
        Task { @MainActor [weak self] in
            self?.handleDecodedPacket(decoded.header, decoded.packet, on: connection)
        }
    }

    private func handleDecodedPacket(_ header: AOLHeader, _ packet: AOLPacket, on connection: NWConnection) {
        switch packet {
        case .discover:
            var flags: UInt8 = requirePIN ? 0x01 : 0x00
            if LibraryModel.shared.current != nil { flags |= 0x02 }
            let reply = AOLPacket.announce(AOLAnnounce(
                port: UInt16(port),
                flags: flags,
                deviceName: UIDevice.current.name
            ))
            send(reply, on: connection)
            return

        case .hello(let hello):
            guard enabled else {
                send(.helloAck(AOLHelloAck(
                    status: AOLProtocol.statusDisabled,
                    sessionActive: LibraryModel.shared.current != nil,
                    tvActive: ExternalDisplay.shared.isActive,
                    deviceName: UIDevice.current.name
                )), on: connection)
                return
            }
            if requirePIN {
                let expected = AOLProtocol.authTag(pin: pin)
                guard hello.authTag == expected else {
                    send(.helloAck(AOLHelloAck(
                        status: AOLProtocol.statusBadPIN,
                        sessionActive: LibraryModel.shared.current != nil,
                        tvActive: ExternalDisplay.shared.isActive,
                        deviceName: UIDevice.current.name
                    )), on: connection)
                    LogStore.shared.log("[aol] rejected HELLO from \(hello.hostName): invalid PIN")
                    return
                }
            }
            activateClient(connection, hello: hello)
            return

        default:
            break
        }

        guard activeConnection === connection else { return }
        lastPacketAt = ProcessInfo.processInfo.systemUptime
        packetsReceived &+= 1

        switch packet {
        case .ping(let ts):
            send(.pong(ts), on: connection)
        case .pong(let sentUS):
            let nowUS = UInt64(ProcessInfo.processInfo.systemUptime * 1_000_000)
            if nowUS >= sentUS {
                latencyMs = max(0, Int((nowUS - sentUS) / 1000))
                syncDisplaySnapshot()
            }
        case .keyEvent(let ev):
            let held = keyReconciler.apply(ev)
            HardwareInput.shared.injectRemoteKey(hidUsage: ev.hidUsage, pressed: ev.pressed, heldUsages: held)
        case .mouseMotion(let m):
            HardwareInput.shared.injectRemoteMouse(
                dx: Int32(m.dx),
                dy: Int32(m.dy),
                wheelX: Int32(m.wheelX),
                wheelY: Int32(m.wheelY),
                buttonMask: m.buttons,
                updateButtons: true
            )
        case .mouseButton(let b):
            HardwareInput.shared.injectRemoteMouse(
                dx: 0,
                dy: 0,
                wheelX: 0,
                wheelY: 0,
                buttonMask: b.buttons,
                updateButtons: true
            )
        case .gamepadState(let pad):
            guard pad.slot < 4 else { return }
            if pad.connected {
                let sample = GamepadSample(
                    buttons: pad.buttons,
                    lt: pad.leftTrigger,
                    rt: pad.rightTrigger,
                    lx: pad.lx,
                    ly: pad.ly,
                    rx: pad.rx,
                    ry: pad.ry
                )
                GamepadInput.shared.setRemotePad(slot: Int(pad.slot), sample: sample)
            } else {
                GamepadInput.shared.setRemotePad(slot: Int(pad.slot), sample: nil)
            }
        case .releaseAll:
            releaseAllInputs()
        case .disconnect:
            disconnectActiveClient(reason: 0, sendPacket: false)
        case .discover, .announce, .hello, .helloAck, .rumble:
            break
        }
    }

    private func activateClient(_ connection: NWConnection, hello: AOLHello) {
        if let prev = activeConnection, prev !== connection {
            send(.disconnect(4), on: prev)
            prev.cancel()
        }
        releaseAllInputs()
        activeConnection = connection
        clientConnected = true
        clientHost = hello.hostName.isEmpty ? "PC Host" : hello.hostName
        clientCapabilities = (hello.hasKeyboard, hello.hasMouse, min(4, hello.gamepadCount))
        latencyMs = nil
        lastPacketAt = ProcessInfo.processInfo.systemUptime
        packetsReceived = 0
        for i in 0..<4 { lastVibrationSerial[i] = 0 }

        if clientCapabilities.gamepads > 0 && winios_gamepad_rumble_caps() == 0 {
            winios_gamepad_set_rumble_caps(1)
            rumbleEnabled = true
        }

        send(.helloAck(AOLHelloAck(
            status: AOLProtocol.statusOK,
            sessionActive: LibraryModel.shared.current != nil,
            tvActive: ExternalDisplay.shared.isActive,
            deviceName: UIDevice.current.name
        )), on: connection)

        startClientTimers()
        syncDisplaySnapshot()
        LogStore.shared.log("[aol] connected host='\(clientHost)' kb=\(clientCapabilities.keyboard) mouse=\(clientCapabilities.mouse) pads=\(clientCapabilities.gamepads)")
    }

    private func disconnectActiveClient(reason: UInt8, sendPacket: Bool = true) {
        let wasConnected = clientConnected || activeConnection != nil
        if let conn = activeConnection {
            if sendPacket { send(.disconnect(reason), on: conn) }
            conn.cancel()
        }
        activeConnection = nil
        clientConnected = false
        clientHost = ""
        clientCapabilities = (false, false, 0)
        latencyMs = nil
        rumbleTimer?.cancel()
        rumbleTimer = nil
        watchdogTimer?.cancel()
        watchdogTimer = nil
        if rumbleEnabled {
            rumbleEnabled = false
        }
        releaseAllInputs()
        syncDisplaySnapshot()
        if wasConnected {
            LogStore.shared.log("[aol] disconnected reason=\(reason)")
        }
    }

    private func releaseAllInputs() {
        keyReconciler.reset()
        HardwareInput.shared.releaseAllRemoteInput()
        GamepadInput.shared.clearRemotePads()
    }

    private func startClientTimers() {
        rumbleTimer?.cancel()
        let rumble = DispatchSource.makeTimerSource(queue: .main)
        rumble.schedule(deadline: .now() + .milliseconds(16), repeating: .milliseconds(16), leeway: .milliseconds(4))
        rumble.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.pollRumble()
            }
        }
        rumble.resume()
        rumbleTimer = rumble

        watchdogTimer?.cancel()
        let dog = DispatchSource.makeTimerSource(queue: .main)
        dog.schedule(deadline: .now() + 1, repeating: 1)
        dog.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.clientConnected else { return }
                let now = ProcessInfo.processInfo.systemUptime
                if now - self.lastPacketAt > 4.0 {
                    LogStore.shared.log("[aol] client '\(self.clientHost)' timed out")
                    self.disconnectActiveClient(reason: 5, sendPacket: false)
                } else if let conn = self.activeConnection {
                    let nowUS = UInt64(now * 1_000_000)
                    self.send(.ping(nowUS), on: conn)
                }
            }
        }
        dog.resume()
        watchdogTimer = dog
    }

    private func pollRumble() {
        guard clientConnected, let conn = activeConnection else { return }
        for slot in 0..<4 {
            var vib = winios_gamepad_vibration()
            let serial = winios_gamepad_get_vibration(Int32(slot), &vib)
            if serial != lastVibrationSerial[slot] {
                lastVibrationSerial[slot] = serial
                send(.rumble(AOLRumble(
                    slot: UInt8(slot),
                    leftMotor: vib.left,
                    rightMotor: vib.right
                )), on: conn)
            }
        }
    }

    private func send(_ packet: AOLPacket, on connection: NWConnection) {
        let seq = txSeq
        txSeq &+= 1
        let data = AOLProtocol.encode(seq: seq, packet: packet)
        ioQueue.async {
            connection.send(content: data, completion: .contentProcessed { _ in })
        }
    }

    private func syncDisplaySnapshot() {
        ExternalDisplay.shared.updateRemoteAccessories(RemoteAccessorySnapshot(
            connected: clientConnected,
            hostName: clientHost,
            latencyMs: latencyMs,
            gamepads: clientCapabilities.gamepads,
            keyboard: clientCapabilities.keyboard,
            mouse: clientCapabilities.mouse
        ))
    }
}

struct AccessoriesOverLANSettingsSection: View {
    @ObservedObject private var aol = AccessoriesOverLAN.shared

    var body: some View {
        Group {
            Section {
                Toggle("Enable Accessories Over LAN", isOn: $aol.enabled)
                Toggle("Advertise on local network (Bonjour)", isOn: $aol.bonjourEnabled)
                    .disabled(!aol.enabled)
            } footer: {
                Text("Receives raw keyboard, mouse, and up to 4 XInput controllers over UDP from Madeira's PC companion tool (madeira-aol), bypassing iOS USB/HID restrictions and forwarding rumble back to the PC.")
            }

            Section("Status & Connection") {
                LabeledContent("Listener") {
                    Text(aol.listening ? "UDP :\(aol.port)" : (aol.enabled ? "Starting…" : "Off"))
                        .foregroundStyle(aol.listening ? .green : .secondary)
                }
                if let err = aol.listenerError, !err.isEmpty {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
                if let primaryIP = aol.localAddresses.first {
                    LabeledContent("Target address") {
                        Text("\(primaryIP):\(aol.port)")
                            .font(.system(.body, design: .monospaced))
                    }
                    if aol.localAddresses.count > 1 {
                        ForEach(aol.localAddresses.dropFirst(), id: \.self) { ip in
                            LabeledContent("Alternate IP") {
                                Text("\(ip):\(aol.port)")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    LabeledContent("Local IP", value: "Unavailable (connect to Wi-Fi)")
                }
                HStack {
                    Text("UDP Port")
                    Spacer()
                    TextField("37419", value: $aol.port, format: .number.grouping(.never))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                }
            }

            Section {
                Toggle("Require PIN", isOn: $aol.requirePIN)
                if aol.requirePIN {
                    HStack {
                        Text("Pairing PIN")
                        Spacer()
                        TextField("PIN", text: $aol.pin)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 90)
                        Button("New") { aol.regeneratePIN() }
                            .buttonStyle(.bordered)
                    }
                }
            } header: { Text("Pairing") } footer: {
                if let ip = aol.localAddresses.first {
                    let pinArg = aol.requirePIN ? " --pin \(aol.pin)" : ""
                    Text("Run on PC: madeira-aol --target \(ip):\(aol.port)\(pinArg)")
                        .font(.system(.caption, design: .monospaced))
                }
            }

            Section("Connected PC") {
                if aol.clientConnected {
                    LabeledContent("Host", value: aol.clientHost)
                    if let rtt = aol.latencyMs {
                        LabeledContent("Round-trip latency", value: "\(rtt) ms")
                    }
                    LabeledContent("Devices", value: deviceSummary)
                    Button("Disconnect PC", role: .destructive) {
                        aol.disconnectClient()
                    }
                } else {
                    Text(aol.enabled ? "Waiting for madeira-aol on this LAN…" : "Enable AoL above to accept connections.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { aol.refreshLocalAddresses() }
    }

    private var deviceSummary: String {
        var parts: [String] = []
        if aol.clientCapabilities.keyboard { parts.append("Keyboard") }
        if aol.clientCapabilities.mouse { parts.append("Mouse") }
        if aol.clientCapabilities.gamepads > 0 {
            parts.append("\(aol.clientCapabilities.gamepads) Gamepad(s)")
        }
        return parts.isEmpty ? "None" : parts.joined(separator: " • ")
    }
}
#endif
