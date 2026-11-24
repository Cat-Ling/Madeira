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
    case stateSync = 0x08

    case announce = 0x80
    case helloAck = 0x81
    case pong = 0x82
    case rumble = 0x83
    case disconnect = 0x84
    case pairGrant = 0x85
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
    var deviceID: [UInt8] = []
}

struct AOLHello: Equatable {
    var flags: UInt8
    var deviceMask: UInt8
    var authTag: [UInt8]
    var hostName: String
    var clientID: [UInt8] = []

    var hasKeyboard: Bool { (deviceMask & 0x01) != 0 }
    var hasMouse: Bool { (deviceMask & 0x02) != 0 }
    var gamepadCount: Int { Int((deviceMask >> 4) & 0x0F) }
    var wantsPair: Bool { (flags & AOLProtocol.helloFlagWantPair) != 0 }
    var isPairedKey: Bool { (flags & AOLProtocol.helloFlagPairedKey) != 0 }
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

struct AOLStateSync: Equatable {
    var buttons: UInt8
    var held: [UInt16]
}

struct AOLPairGrant: Equatable {
    var deviceID: [UInt8]
    var nonce: [UInt8]
    var maskedKey: [UInt8]
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
    case stateSync(AOLStateSync)
    case pairGrant(AOLPairGrant)

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
        case .stateSync: return .stateSync
        case .pairGrant: return .pairGrant
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
    static let statusUnpaired: UInt8 = 3

    static let helloFlagWantPair: UInt8 = 1 << 0
    static let helloFlagPairedKey: UInt8 = 1 << 1
    static let helloFlagHasClientID: UInt8 = 1 << 2

    static let announceFlagRequirePIN: UInt8 = 1 << 0
    static let announceFlagSession: UInt8 = 1 << 1
    static let announceFlagHasDeviceID: UInt8 = 1 << 2

    static let reasonNormal: UInt8 = 0
    static let reasonUser: UInt8 = 1
    static let reasonDisabled: UInt8 = 2
    static let reasonRestart: UInt8 = 3
    static let reasonSuperseded: UInt8 = 4
    static let reasonTimeout: UInt8 = 5
    static let reasonRehandshake: UInt8 = 6

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

    static func pairedAuthTag(key: [UInt8], clientID: [UInt8], seq: UInt32) -> [UInt8] {
        var msg = Data("MAOL-v1-key:".utf8)
        msg.append(contentsOf: fixedBytes(key, count: 32))
        msg.append(contentsOf: fixedBytes(clientID, count: 8))
        appendUInt32LE(&msg, seq)
        return Array(sha256(msg).prefix(8))
    }

    static func maskPairKey(pin: String, nonce: [UInt8], key: [UInt8]) -> [UInt8] {
        var msg = Data("MAOL-v1-mask:".utf8)
        msg.append(contentsOf: pin.utf8)
        msg.append(contentsOf: fixedBytes(nonce, count: 8))
        let mask = sha256(msg)
        let k = fixedBytes(key, count: 32)
        var out = [UInt8](repeating: 0, count: 32)
        for i in 0..<32 {
            out[i] = k[i] ^ mask[i]
        }
        return out
    }

    static func encode(seq: UInt32, packet: AOLPacket) -> Data {
        var out = Data()
        out.reserveCapacity(headerSize + 48)
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
            let hasDevID = p.deviceID.count == 8 && p.deviceID.contains { $0 != 0 }
            let flags = hasDevID ? (p.flags | announceFlagHasDeviceID) : p.flags
            out.append(flags)
            appendShortString(&out, p.deviceName)
            if (flags & announceFlagHasDeviceID) != 0 {
                out.append(contentsOf: fixedBytes(p.deviceID, count: 8))
            }
        case .hello(let p):
            let hasClientID = p.clientID.count == 8 && p.clientID.contains { $0 != 0 }
            let flags = hasClientID ? (p.flags | helloFlagHasClientID) : p.flags
            out.append(flags)
            out.append(p.deviceMask)
            out.append(contentsOf: fixedBytes(p.authTag, count: 8))
            appendShortString(&out, p.hostName)
            if (flags & helloFlagHasClientID) != 0 {
                out.append(contentsOf: fixedBytes(p.clientID, count: 8))
            }
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
        case .stateSync(let p):
            let held = Array(p.held.prefix(maxHeldKeys))
            out.append(p.buttons)
            out.append(UInt8(held.count))
            for u in held { appendUInt16LE(&out, u) }
        case .pairGrant(let p):
            out.append(contentsOf: fixedBytes(p.deviceID, count: 8))
            out.append(contentsOf: fixedBytes(p.nonce, count: 8))
            out.append(contentsOf: fixedBytes(p.maskedKey, count: 32))
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
            let flags = body[2]
            guard let (name, nextOffset) = readShortString(body, offset: 3) else { return nil }
            var devID: [UInt8] = []
            if (flags & announceFlagHasDeviceID) != 0 {
                guard body.count >= nextOffset + 8 else { return nil }
                devID = Array(body[nextOffset..<(nextOffset + 8)])
            }
            return (header, .announce(AOLAnnounce(
                port: readUInt16LE(body, 0),
                flags: flags,
                deviceName: name,
                deviceID: devID
            )))
        case .hello:
            guard body.count >= 11 else { return nil }
            let flags = body[0]
            guard let (host, nextOffset) = readShortString(body, offset: 10) else { return nil }
            var cid: [UInt8] = []
            if (flags & helloFlagHasClientID) != 0 {
                guard body.count >= nextOffset + 8 else { return nil }
                cid = Array(body[nextOffset..<(nextOffset + 8)])
            }
            return (header, .hello(AOLHello(
                flags: flags,
                deviceMask: body[1],
                authTag: Array(body[2..<10]),
                hostName: host,
                clientID: cid
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
        case .stateSync:
            guard body.count >= 2 else { return nil }
            let count = min(Int(body[1]), maxHeldKeys)
            guard body.count >= 2 + count * 2 else { return nil }
            var held: [UInt16] = []
            held.reserveCapacity(count)
            for i in 0..<count {
                held.append(readUInt16LE(body, 2 + i * 2))
            }
            return (header, .stateSync(AOLStateSync(buttons: body[0], held: held)))
        case .pairGrant:
            guard body.count >= 48 else { return nil }
            return (header, .pairGrant(AOLPairGrant(
                deviceID: Array(body[0..<8]),
                nonce: Array(body[8..<16]),
                maskedKey: Array(body[16..<48])
            )))
        }
    }

    private static func fixedBytes(_ src: [UInt8], count: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: count)
        for i in 0..<min(count, src.count) { out[i] = src[i] }
        return out
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

/// Self-healing key state tracker for UDP KEY_EVENT and STATE_SYNC packets.
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

    @discardableResult
    mutating func reconcile(held: [UInt16]) -> Set<UInt16> {
        heldUsages = Set(held)
        return heldUsages
    }

    mutating func reset() {
        heldUsages.removeAll()
    }
}

/// Wrap-safe 32-bit sequence ordering check to drop stale reordered UDP packets.
enum AOLSeqTracker {
    static func isNewer(_ seq: UInt32, than last: UInt32) -> Bool {
        Int32(bitPattern: seq &- last) > 0
    }
}

#if canImport(UIKit)
import UIKit
import SwiftUI
import Network
import Combine
import Darwin
import Security

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

struct PairedAOLPC: Codable, Identifiable, Equatable {
    var id: String // ClientID hex
    var hostName: String
    var keyBase64: String
    var pairedAt: Date
}

/// Lock-protected hot-path session core executing directly on `ioQueue` without
/// MainActor hops for zero-jitter input processing, 350ms stuck-key recovery, and rumble polling.
private final class AOLSessionCore: @unchecked Sendable {
    let ioQueue = DispatchQueue(label: "madeira.aol.udp", qos: .userInteractive)
    private let lock = NSLock()

    private weak var owner: AccessoriesOverLAN?
    private var activeConnection: NWConnection?
    private var lastPacketAt: TimeInterval = 0
    private var lastPingSentAt: TimeInterval = 0
    private var lastStateSeq: UInt32 = 0
    private var lastPadSeq = [UInt32](repeating: 0, count: 4)
    private var keyReconciler = AOLHeldKeyReconciler()
    private var heldMouseMask: UInt8 = 0
    private var padConnectedMask: UInt8 = 0
    private var stalledReleased = false
    private var txSeq: UInt32 = 1
    private var latestLatencyMs: Int?
    private var publishedLatencyMs: Int?
    private var lastRehandshakeHintAt: TimeInterval = 0
    private var lastVibrationSerial = [UInt32](repeating: 0, count: 4)
    private var watchdogTimer: DispatchSourceTimer?
    private var rumbleTimer: DispatchSourceTimer?

    init(owner: AccessoriesOverLAN) {
        self.owner = owner
    }

    func activate(connection: NWConnection) {
        lock.lock()
        let prev = activeConnection
        activeConnection = connection
        let now = ProcessInfo.processInfo.systemUptime
        lastPacketAt = now
        lastPingSentAt = now
        lastStateSeq = 0
        lastPadSeq = [0, 0, 0, 0]
        keyReconciler.reset()
        heldMouseMask = 0
        padConnectedMask = 0
        stalledReleased = false
        latestLatencyMs = nil
        publishedLatencyMs = nil
        lastVibrationSerial = [0, 0, 0, 0]
        lock.unlock()

        if let prev, prev !== connection {
            send(.disconnect(AOLProtocol.reasonSuperseded), on: prev)
            prev.cancel()
        }
        startTimersLocked()
    }

    func deactivate(connection: NWConnection? = nil, sendReason: UInt8? = nil) -> NWConnection? {
        lock.lock()
        if let connection, activeConnection !== connection {
            lock.unlock()
            return nil
        }
        let old = activeConnection
        activeConnection = nil
        lastStateSeq = 0
        lastPadSeq = [0, 0, 0, 0]
        keyReconciler.reset()
        heldMouseMask = 0
        padConnectedMask = 0
        stalledReleased = false
        latestLatencyMs = nil
        publishedLatencyMs = nil
        let rt = rumbleTimer
        rumbleTimer = nil
        let wt = watchdogTimer
        watchdogTimer = nil
        lock.unlock()

        rt?.cancel()
        wt?.cancel()
        if let old {
            if let sendReason {
                send(.disconnect(sendReason), on: old)
            }
            old.cancel()
        }
        return old
    }

    func resetGameSessionState(hasGamepads: Bool) {
        lock.lock()
        keyReconciler.reset()
        heldMouseMask = 0
        lastVibrationSerial = [0, 0, 0, 0]
        lock.unlock()
        HardwareInput.shared.releaseAllRemoteInputFast()
        if hasGamepads && winios_gamepad_rumble_caps() == 0 {
            winios_gamepad_set_rumble_caps(1)
        }
    }

    func handleDatagram(_ data: Data, on connection: NWConnection) {
        guard let decoded = AOLProtocol.decode(data) else { return }
        let header = decoded.header
        let packet = decoded.packet

        switch packet {
        case .discover, .hello:
            Task { @MainActor [weak owner] in
                owner?.handleControlPacket(header: header, packet: packet, on: connection)
            }
            return
        default:
            break
        }

        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        guard activeConnection === connection else {
            let shouldHint = (now - lastRehandshakeHintAt) >= 0.2
            if shouldHint { lastRehandshakeHintAt = now }
            lock.unlock()
            if shouldHint {
                send(.disconnect(AOLProtocol.reasonRehandshake), on: connection)
            }
            return
        }
        lastPacketAt = now
        stalledReleased = false

        switch packet {
        case .ping(let ts):
            lock.unlock()
            send(.pong(ts), on: connection)

        case .pong(let sentUS):
            let nowUS = UInt64(now * 1_000_000)
            if nowUS >= sentUS {
                latestLatencyMs = max(0, Int((nowUS - sentUS) / 1000))
            }
            lock.unlock()

        case .keyEvent(let ev):
            if lastStateSeq != 0 && !AOLSeqTracker.isNewer(header.seq, than: lastStateSeq) {
                lock.unlock()
                return
            }
            lastStateSeq = header.seq
            let held = keyReconciler.apply(ev)
            lock.unlock()
            HardwareInput.shared.injectRemoteKeyFast(hidUsage: ev.hidUsage, pressed: ev.pressed, heldUsages: held)

        case .mouseMotion(let m):
            let allowButtons = lastStateSeq == 0 || AOLSeqTracker.isNewer(header.seq, than: lastStateSeq)
            if allowButtons {
                lastStateSeq = header.seq
                heldMouseMask = m.buttons
            }
            lock.unlock()
            HardwareInput.shared.injectRemoteMouseFast(
                dx: Int32(m.dx),
                dy: Int32(m.dy),
                wheelX: Int32(m.wheelX),
                wheelY: Int32(m.wheelY),
                buttonMask: m.buttons,
                updateButtons: allowButtons
            )

        case .mouseButton(let b):
            if lastStateSeq != 0 && !AOLSeqTracker.isNewer(header.seq, than: lastStateSeq) {
                lock.unlock()
                return
            }
            lastStateSeq = header.seq
            heldMouseMask = b.buttons
            lock.unlock()
            HardwareInput.shared.injectRemoteMouseFast(
                dx: 0, dy: 0, wheelX: 0, wheelY: 0,
                buttonMask: b.buttons, updateButtons: true
            )

        case .stateSync(let s):
            if lastStateSeq != 0 && !AOLSeqTracker.isNewer(header.seq, than: lastStateSeq) {
                lock.unlock()
                return
            }
            lastStateSeq = header.seq
            let held = keyReconciler.reconcile(held: s.held)
            heldMouseMask = s.buttons
            lock.unlock()
            HardwareInput.shared.injectRemoteStateSyncFast(buttonMask: s.buttons, heldUsages: held)

        case .gamepadState(let pad):
            guard pad.slot < 4 else {
                lock.unlock()
                return
            }
            let slot = Int(pad.slot)
            if lastPadSeq[slot] != 0 && !AOLSeqTracker.isNewer(header.seq, than: lastPadSeq[slot]) {
                lock.unlock()
                return
            }
            lastPadSeq[slot] = header.seq
            if pad.connected {
                padConnectedMask |= UInt8(1 << slot)
            } else {
                padConnectedMask &= ~UInt8(1 << slot)
            }
            lock.unlock()
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
                GamepadInput.shared.setRemotePad(slot: slot, sample: sample)
            } else {
                GamepadInput.shared.setRemotePad(slot: slot, sample: nil)
            }

        case .releaseAll:
            keyReconciler.reset()
            heldMouseMask = 0
            lock.unlock()
            HardwareInput.shared.releaseAllRemoteInputFast()

        case .disconnect:
            lock.unlock()
            Task { @MainActor [weak owner] in
                owner?.handleRemoteDisconnect(connection: connection)
            }

        case .discover, .announce, .hello, .helloAck, .rumble, .pairGrant:
            lock.unlock()
        }
    }

    func send(_ packet: AOLPacket, on connection: NWConnection) {
        lock.lock()
        let seq = txSeq
        txSeq &+= 1
        lock.unlock()
        let data = AOLProtocol.encode(seq: seq, packet: packet)
        ioQueue.async {
            connection.send(content: data, completion: .contentProcessed { _ in })
        }
    }

    private func startTimersLocked() {
        lock.lock()
        let oldRumble = rumbleTimer
        let oldDog = watchdogTimer

        let rumble = DispatchSource.makeTimerSource(queue: ioQueue)
        rumble.schedule(deadline: .now() + .milliseconds(16), repeating: .milliseconds(16), leeway: .milliseconds(4))
        rumble.setEventHandler { [weak self] in
            self?.pollRumble()
        }
        rumbleTimer = rumble

        let dog = DispatchSource.makeTimerSource(queue: ioQueue)
        dog.schedule(deadline: .now() + .milliseconds(100), repeating: .milliseconds(100), leeway: .milliseconds(20))
        dog.setEventHandler { [weak self] in
            self?.tickWatchdog()
        }
        watchdogTimer = dog
        lock.unlock()

        oldRumble?.cancel()
        oldDog?.cancel()
        rumble.resume()
        dog.resume()
    }

    private func tickWatchdog() {
        let now = ProcessInfo.processInfo.systemUptime
        var timedOutConn: NWConnection?
        var releaseStalled = false
        var pingConn: NWConnection?
        var pingTimestampUS: UInt64 = 0
        var publishRTT: Int?
        var shouldPublishRTT = false

        lock.lock()
        if let conn = activeConnection {
            let idle = now - lastPacketAt
            if idle > 3.5 {
                timedOutConn = conn
            } else {
                let held = !keyReconciler.heldUsages.isEmpty || heldMouseMask != 0 || padConnectedMask != 0
                if held && !stalledReleased && idle > 0.35 {
                    stalledReleased = true
                    keyReconciler.reset()
                    heldMouseMask = 0
                    padConnectedMask = 0
                    releaseStalled = true
                }
                if now - lastPingSentAt >= 1.0 {
                    lastPingSentAt = now
                    pingConn = conn
                    pingTimestampUS = UInt64(now * 1_000_000)
                    if latestLatencyMs != publishedLatencyMs {
                        publishedLatencyMs = latestLatencyMs
                        publishRTT = latestLatencyMs
                        shouldPublishRTT = true
                    }
                }
            }
        }
        lock.unlock()

        if let timedOutConn {
            Task { @MainActor [weak owner] in
                owner?.handleWatchdogTimeout(connection: timedOutConn)
            }
            return
        }
        if releaseStalled {
            HardwareInput.shared.releaseAllRemoteInputFast()
            GamepadInput.shared.clearRemotePads()
        }
        if let pingConn {
            send(.ping(pingTimestampUS), on: pingConn)
        }
        if shouldPublishRTT {
            Task { @MainActor [weak owner] in
                owner?.updateLatencyUI(publishRTT)
            }
        }
    }

    private func pollRumble() {
        lock.lock()
        guard let conn = activeConnection else {
            lock.unlock()
            return
        }
        var changed: [AOLRumble] = []
        for slot in 0..<4 {
            var vib = winios_gamepad_vibration()
            let serial = winios_gamepad_get_vibration(Int32(slot), &vib)
            if serial != lastVibrationSerial[slot] {
                lastVibrationSerial[slot] = serial
                changed.append(AOLRumble(slot: UInt8(slot), leftMotor: vib.left, rightMotor: vib.right))
            }
        }
        lock.unlock()

        for r in changed {
            send(.rumble(r), on: conn)
        }
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
        static let deviceID = "aol.deviceID"
        static let pairedPCs = "aol.pairedPCs"
    }

    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Keys.enabled)
            if enabled { startListener() } else { stopListener(reason: AOLProtocol.reasonDisabled) }
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
    @Published private(set) var pairedPCs: [PairedAOLPC] = []

    private let deviceIDBytes: [UInt8]
    private var listener: NWListener?
    private var activeConnection: NWConnection?
    private var core: AOLSessionCore?
    private var observers: [NSObjectProtocol] = []
    private var sessionCancellable: AnyCancellable?
    private var started = false

    private init() {
        let d = UserDefaults.standard
        let defaultPIN: String
        if let saved = d.string(forKey: Keys.pin), !saved.isEmpty {
            defaultPIN = saved
        } else {
            defaultPIN = String(format: "%04d", Int.random(in: 1000...9999))
            d.set(defaultPIN, forKey: Keys.pin)
        }

        if let devData = d.data(forKey: Keys.deviceID), devData.count == 8 {
            self.deviceIDBytes = [UInt8](devData)
        } else {
            let fresh = Self.randomBytes(8)
            d.set(Data(fresh), forKey: Keys.deviceID)
            self.deviceIDBytes = fresh
        }

        if let pairedData = d.data(forKey: Keys.pairedPCs),
           let decoded = try? JSONDecoder().decode([PairedAOLPC].self, from: pairedData) {
            self.pairedPCs = decoded
        }

        let savedPort = d.integer(forKey: Keys.port)
        self.enabled = d.object(forKey: Keys.enabled) == nil ? false : d.bool(forKey: Keys.enabled)
        self.port = savedPort >= 1024 && savedPort <= 65535 ? savedPort : Int(AOLProtocol.defaultPort)
        self.requirePIN = d.object(forKey: Keys.requirePIN) == nil ? true : d.bool(forKey: Keys.requirePIN)
        self.pin = defaultPIN
        self.bonjourEnabled = d.object(forKey: Keys.bonjour) == nil ? true : d.bool(forKey: Keys.bonjour)
        self.core = AOLSessionCore(owner: self)
        refreshLocalAddresses()
    }

    func startIfEnabled() {
        refreshLocalAddresses()
        installLifecycleObservers()
        if enabled { startListener() }
    }

    func regeneratePIN() {
        pin = String(format: "%04d", Int.random(in: 1000...9999))
    }

    func disconnectClient() {
        disconnectActiveClient(reason: AOLProtocol.reasonUser)
    }

    func forgetPairedPC(id: String) {
        pairedPCs.removeAll { $0.id == id }
        savePairedPCs()
    }

    func forgetAllPairedPCs() {
        pairedPCs.removeAll()
        savePairedPCs()
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

    private func installLifecycleObservers() {
        guard !started else { return }
        started = true
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.releaseAllInputs()
            }
        })
        observers.append(nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.refreshLocalAddresses()
                if self.enabled && self.listener == nil {
                    self.startListener()
                }
            }
        })
        sessionCancellable = LibraryModel.shared.$current.sink { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.core?.resetGameSessionState(hasGamepads: self.clientCapabilities.gamepads > 0)
            }
        }
    }

    private func restartListener() {
        stopListener(reason: AOLProtocol.reasonRestart)
        startListener()
    }

    private func startListener() {
        guard listener == nil, let core else { return }
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            listenerError = "Invalid UDP port \(port)"
            return
        }
        refreshLocalAddresses()
        do {
            let params = NWParameters.udp
            params.allowLocalEndpointReuse = true
            params.serviceClass = .interactiveVoice
            let newListener = try NWListener(using: params, on: nwPort)
            if bonjourEnabled {
                newListener.service = NWListener.Service(name: UIDevice.current.name, type: "_madeira-aol._udp")
            }
            newListener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    self?.handleListenerState(state)
                }
            }
            newListener.newConnectionHandler = { [weak core] connection in
                guard let core else { return }
                Self.acceptConnection(connection, core: core)
            }
            newListener.start(queue: core.ioQueue)
            listener = newListener
            listenerError = nil
            LogStore.shared.log("[aol] listening UDP :\(port) serviceClass=interactiveVoice bonjour=\(bonjourEnabled ? 1 : 0)")
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

    private nonisolated static func acceptConnection(_ connection: NWConnection, core: AOLSessionCore) {
        connection.start(queue: core.ioQueue)
        receiveLoop(on: connection, core: core)
    }

    private nonisolated static func receiveLoop(on connection: NWConnection, core: AOLSessionCore) {
        connection.receiveMessage { content, _, _, error in
            if let data = content, !data.isEmpty {
                core.handleDatagram(data, on: connection)
            }
            if error == nil && connection.state != .cancelled {
                receiveLoop(on: connection, core: core)
            }
        }
    }

    fileprivate func handleControlPacket(header: AOLHeader, packet: AOLPacket, on connection: NWConnection) {
        guard let core else { return }
        switch packet {
        case .discover:
            var flags: UInt8 = requirePIN ? AOLProtocol.announceFlagRequirePIN : 0
            if LibraryModel.shared.current != nil { flags |= AOLProtocol.announceFlagSession }
            flags |= AOLProtocol.announceFlagHasDeviceID
            let reply = AOLPacket.announce(AOLAnnounce(
                port: UInt16(port),
                flags: flags,
                deviceName: UIDevice.current.name,
                deviceID: deviceIDBytes
            ))
            core.send(reply, on: connection)

        case .hello(let hello):
            guard enabled else {
                core.send(.helloAck(AOLHelloAck(
                    status: AOLProtocol.statusDisabled,
                    sessionActive: LibraryModel.shared.current != nil,
                    tvActive: ExternalDisplay.shared.isActive,
                    deviceName: UIDevice.current.name
                )), on: connection)
                return
            }

            if hello.isPairedKey {
                let cidHex = Self.hexString(hello.clientID)
                guard hello.clientID.count == 8,
                      let paired = pairedPCs.first(where: { $0.id == cidHex }),
                      let keyData = Data(base64Encoded: paired.keyBase64),
                      keyData.count == 32 else {
                    core.send(.helloAck(AOLHelloAck(
                        status: AOLProtocol.statusUnpaired,
                        sessionActive: LibraryModel.shared.current != nil,
                        tvActive: ExternalDisplay.shared.isActive,
                        deviceName: UIDevice.current.name
                    )), on: connection)
                    LogStore.shared.log("[aol] rejected paired-key HELLO from \(hello.hostName): unknown clientID")
                    return
                }
                let expected = AOLProtocol.pairedAuthTag(key: [UInt8](keyData), clientID: hello.clientID, seq: header.seq)
                guard hello.authTag == expected else {
                    core.send(.helloAck(AOLHelloAck(
                        status: AOLProtocol.statusUnpaired,
                        sessionActive: LibraryModel.shared.current != nil,
                        tvActive: ExternalDisplay.shared.isActive,
                        deviceName: UIDevice.current.name
                    )), on: connection)
                    LogStore.shared.log("[aol] rejected paired-key HELLO from \(hello.hostName): bad authTag")
                    return
                }
                activateClient(connection, hello: hello, issuePairGrant: false)
                return
            }

            if requirePIN {
                let expected = AOLProtocol.authTag(pin: pin)
                guard hello.authTag == expected else {
                    core.send(.helloAck(AOLHelloAck(
                        status: AOLProtocol.statusBadPIN,
                        sessionActive: LibraryModel.shared.current != nil,
                        tvActive: ExternalDisplay.shared.isActive,
                        deviceName: UIDevice.current.name
                    )), on: connection)
                    LogStore.shared.log("[aol] rejected HELLO from \(hello.hostName): invalid PIN")
                    return
                }
            }
            activateClient(connection, hello: hello, issuePairGrant: hello.wantsPair && hello.clientID.count == 8)

        default:
            break
        }
    }

    private func activateClient(_ connection: NWConnection, hello: AOLHello, issuePairGrant: Bool) {
        guard let core else { return }
        releaseAllInputs()
        activeConnection = connection
        core.activate(connection: connection)

        clientConnected = true
        clientHost = hello.hostName.isEmpty ? "PC Host" : hello.hostName
        clientCapabilities = (hello.hasKeyboard, hello.hasMouse, min(4, hello.gamepadCount))
        latencyMs = nil
        HardwareInput.shared.setRemoteClientConnected(true)

        if clientCapabilities.gamepads > 0 && winios_gamepad_rumble_caps() == 0 {
            winios_gamepad_set_rumble_caps(1)
        }

        core.send(.helloAck(AOLHelloAck(
            status: AOLProtocol.statusOK,
            sessionActive: LibraryModel.shared.current != nil,
            tvActive: ExternalDisplay.shared.isActive,
            deviceName: UIDevice.current.name
        )), on: connection)

        if issuePairGrant {
            let cidHex = Self.hexString(hello.clientID)
            let rawKey = Self.randomBytes(32)
            let nonce = Self.randomBytes(8)
            let maskPin = requirePIN ? pin : ""
            let masked = AOLProtocol.maskPairKey(pin: maskPin, nonce: nonce, key: rawKey)
            upsertPairedPC(PairedAOLPC(
                id: cidHex,
                hostName: clientHost,
                keyBase64: Data(rawKey).base64EncodedString(),
                pairedAt: Date()
            ))
            core.send(.pairGrant(AOLPairGrant(
                deviceID: deviceIDBytes,
                nonce: nonce,
                maskedKey: masked
            )), on: connection)
            LogStore.shared.log("[aol] paired PC '\(clientHost)' id=\(cidHex)")
        }

        syncDisplaySnapshot()
        LogStore.shared.log("[aol] connected host='\(clientHost)' auth=\(hello.isPairedKey ? "key" : "pin") kb=\(clientCapabilities.keyboard) mouse=\(clientCapabilities.mouse) pads=\(clientCapabilities.gamepads)")
    }

    fileprivate func handleRemoteDisconnect(connection: NWConnection) {
        guard activeConnection === connection else { return }
        disconnectActiveClient(reason: AOLProtocol.reasonNormal, sendPacket: false)
    }

    fileprivate func handleWatchdogTimeout(connection: NWConnection) {
        guard activeConnection === connection else { return }
        LogStore.shared.log("[aol] client '\(clientHost)' timed out")
        disconnectActiveClient(reason: AOLProtocol.reasonTimeout, sendPacket: false)
    }

    fileprivate func updateLatencyUI(_ ms: Int?) {
        guard clientConnected else { return }
        latencyMs = ms
        syncDisplaySnapshot()
    }

    private func disconnectActiveClient(reason: UInt8, sendPacket: Bool = true) {
        let wasConnected = clientConnected || activeConnection != nil
        _ = core?.deactivate(sendReason: sendPacket ? reason : nil)
        activeConnection = nil
        clientConnected = false
        clientHost = ""
        clientCapabilities = (false, false, 0)
        latencyMs = nil
        HardwareInput.shared.setRemoteClientConnected(false)
        releaseAllInputs()
        syncDisplaySnapshot()
        if wasConnected {
            LogStore.shared.log("[aol] disconnected reason=\(reason)")
        }
    }

    private func releaseAllInputs() {
        HardwareInput.shared.releaseAllRemoteInputFast()
        GamepadInput.shared.clearRemotePads()
    }

    private func upsertPairedPC(_ entry: PairedAOLPC) {
        if let idx = pairedPCs.firstIndex(where: { $0.id == entry.id }) {
            pairedPCs[idx] = entry
        } else {
            pairedPCs.append(entry)
        }
        savePairedPCs()
    }

    private func savePairedPCs() {
        if let data = try? JSONEncoder().encode(pairedPCs) {
            UserDefaults.standard.set(data, forKey: Keys.pairedPCs)
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

    private static func randomBytes(_ count: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        if SecRandomCopyBytes(kSecRandomDefault, count, &bytes) != errSecSuccess {
            for i in 0..<count { bytes[i] = UInt8.random(in: 0...255) }
        }
        return bytes
    }

    private static func hexString(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}

struct AccessoriesOverLANSettingsSection: View {
    @ObservedObject private var aol = AccessoriesOverLAN.shared

    private var portText: String { String(aol.port) }

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
                    Text(aol.listening ? "UDP :\(portText)" : (aol.enabled ? "Starting…" : "Off"))
                        .foregroundStyle(aol.listening ? .green : .secondary)
                }
                if let err = aol.listenerError, !err.isEmpty {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
                if let primaryIP = aol.localAddresses.first {
                    LabeledContent("Target address") {
                        Text("\(primaryIP):\(portText)")
                            .font(.system(.body, design: .monospaced))
                    }
                    if aol.localAddresses.count > 1 {
                        ForEach(aol.localAddresses.dropFirst(), id: \.self) { ip in
                            LabeledContent("Alternate IP") {
                                Text("\(ip):\(portText)")
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
                    Text("Run on PC: madeira-aol --target \(ip):\(portText)\(pinArg)")
                        .font(.system(.caption, design: .monospaced))
                }
            }

            if !aol.pairedPCs.isEmpty {
                Section {
                    ForEach(aol.pairedPCs) { pc in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pc.hostName)
                                Text("Key ID \(pc.id.prefix(8))")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Forget", role: .destructive) {
                                aol.forgetPairedPC(id: pc.id)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    if aol.pairedPCs.count > 1 {
                        Button("Forget All Paired PCs", role: .destructive) {
                            aol.forgetAllPairedPCs()
                        }
                    }
                } header: { Text("Paired PCs") } footer: {
                    Text("Paired PCs reconnect automatically even if you regenerate the PIN.")
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
