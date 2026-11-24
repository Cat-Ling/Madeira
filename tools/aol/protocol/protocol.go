// SPDX-FileCopyrightText: 2026 Cat-Ling
// SPDX-License-Identifier: GPL-3.0-or-later

package protocol

import (
	"crypto/sha256"
	"encoding/binary"
	"errors"
	"fmt"
)

const (
	// DefaultPort is the standard UDP port used for AoL discovery and streaming.
	DefaultPort = 37419

	// Version is the supported MAOL wire protocol version.
	Version uint8 = 1

	// HeaderSize is the fixed 8-byte MAOL v1 packet header size.
	HeaderSize = 8

	// MaxHeldKeys is the maximum number of held HID usages carried in KeyEvent.
	MaxHeldKeys = 8

	magic0 = 'M'
	magic1 = 'A'
)

// DeviceMask capability bits carried in Hello packets.
const (
	DeviceKeyboard uint8 = 1 << 0
	DeviceMouse    uint8 = 1 << 1
)

// Mouse button bitmask flags shared by MouseMotion and MouseButton.
const (
	MouseButtonLeft   uint8 = 1 << 0
	MouseButtonRight  uint8 = 1 << 1
	MouseButtonMiddle uint8 = 1 << 2
	MouseButtonX1     uint8 = 1 << 3
	MouseButtonX2     uint8 = 1 << 4
)

// HelloAck status codes.
const (
	StatusOK       uint8 = 0
	StatusBadPIN   uint8 = 1
	StatusDisabled uint8 = 2
	StatusUnpaired uint8 = 3
)

// Hello capability/pairing flags.
const (
	HelloFlagWantPair    uint8 = 1 << 0
	HelloFlagPairedKey   uint8 = 1 << 1
	HelloFlagHasClientID uint8 = 1 << 2
)

// Announce flags.
const (
	AnnounceFlagRequirePIN  uint8 = 1 << 0
	AnnounceFlagSession     uint8 = 1 << 1
	AnnounceFlagHasDeviceID uint8 = 1 << 2
)

// Disconnect reason codes.
const (
	ReasonNormal      uint8 = 0
	ReasonUser        uint8 = 1
	ReasonDisabled    uint8 = 2
	ReasonRestart     uint8 = 3
	ReasonSuperseded  uint8 = 4
	ReasonTimeout     uint8 = 5
	ReasonRehandshake uint8 = 6
)

// PacketType identifies a MAOL v1 packet payload.
type PacketType uint8

const (
	TypeDiscover     PacketType = 0x00
	TypeHello        PacketType = 0x01
	TypePing         PacketType = 0x02
	TypeKeyEvent     PacketType = 0x03
	TypeMouseMotion  PacketType = 0x04
	TypeMouseButton  PacketType = 0x05
	TypeGamepadState PacketType = 0x06
	TypeReleaseAll   PacketType = 0x07
	TypeStateSync    PacketType = 0x08

	TypeAnnounce   PacketType = 0x80
	TypeHelloAck   PacketType = 0x81
	TypePong       PacketType = 0x82
	TypeRumble     PacketType = 0x83
	TypeDisconnect PacketType = 0x84
	TypePairGrant  PacketType = 0x85
)

// Sentinel errors returned when decoding malformed packets.
var (
	ErrShortPacket        = errors.New("packet shorter than header")
	ErrBadMagic           = errors.New("invalid packet magic")
	ErrUnsupportedVersion = errors.New("unsupported protocol version")
	ErrUnknownType        = errors.New("unknown packet type")
	ErrTruncated          = errors.New("truncated packet payload")
)

// Header holds the common 8-byte MAOL header.
type Header struct {
	Version uint8
	Type    PacketType
	Seq     uint32
}

// Packet is implemented by all concrete MAOL v1 message types.
type Packet interface {
	PacketType() PacketType
	appendBody(dst []byte) []byte
}

// Discover probes the LAN for listening Madeira instances.
type Discover struct{}

func (Discover) PacketType() PacketType       { return TypeDiscover }
func (Discover) appendBody(dst []byte) []byte { return dst }

// Announce advertises a listening Madeira instance in response to Discover.
type Announce struct {
	Port       uint16
	Flags      uint8
	DeviceName string
	DeviceID   [8]byte
}

func (Announce) PacketType() PacketType { return TypeAnnounce }
func (p Announce) appendBody(dst []byte) []byte {
	dst = binary.LittleEndian.AppendUint16(dst, p.Port)
	flags := p.Flags
	if p.DeviceID != ([8]byte{}) {
		flags |= AnnounceFlagHasDeviceID
	}
	dst = append(dst, flags)
	dst = appendShortString(dst, p.DeviceName)
	if (flags & AnnounceFlagHasDeviceID) != 0 {
		dst = append(dst, p.DeviceID[:]...)
	}
	return dst
}

// Hello initiates a session from the PC client to Madeira.
type Hello struct {
	Flags      uint8
	DeviceMask uint8
	AuthTag    [8]byte
	HostName   string
	ClientID   [8]byte
}

func (Hello) PacketType() PacketType { return TypeHello }
func (p Hello) appendBody(dst []byte) []byte {
	flags := p.Flags
	if p.ClientID != ([8]byte{}) {
		flags |= HelloFlagHasClientID
	}
	dst = append(dst, flags, p.DeviceMask)
	dst = append(dst, p.AuthTag[:]...)
	dst = appendShortString(dst, p.HostName)
	if (flags & HelloFlagHasClientID) != 0 {
		dst = append(dst, p.ClientID[:]...)
	}
	return dst
}

// DeviceMaskWithPads encodes keyboard, mouse, and gamepad slot count (0-15) into DeviceMask.
func DeviceMaskWithPads(kb, mouse bool, padCount uint8) uint8 {
	var m uint8
	if kb {
		m |= DeviceKeyboard
	}
	if mouse {
		m |= DeviceMouse
	}
	if padCount > 15 {
		padCount = 15
	}
	return m | (padCount << 4)
}

// HelloAck responds to Hello with session and authorization status.
type HelloAck struct {
	Status        uint8
	SessionActive bool
	TVActive      bool
	DeviceName    string
}

func (HelloAck) PacketType() PacketType { return TypeHelloAck }
func (p HelloAck) appendBody(dst []byte) []byte {
	return appendShortString(append(dst, p.Status, boolByte(p.SessionActive), boolByte(p.TVActive)), p.DeviceName)
}

// Ping measures round-trip latency using a microsecond monotonic timestamp.
type Ping struct {
	TimestampUS uint64
}

func (Ping) PacketType() PacketType { return TypePing }
func (p Ping) appendBody(dst []byte) []byte {
	return binary.LittleEndian.AppendUint64(dst, p.TimestampUS)
}

// Pong echoes a Ping timestamp back to the sender.
type Pong struct {
	TimestampUS uint64
}

func (Pong) PacketType() PacketType { return TypePong }
func (p Pong) appendBody(dst []byte) []byte {
	return binary.LittleEndian.AppendUint64(dst, p.TimestampUS)
}

// KeyEvent reports a HID Usage Page 0x07 key edge plus up to MaxHeldKeys currently held usages.
type KeyEvent struct {
	HIDUsage uint16
	Pressed  bool
	Held     []uint16
}

func (KeyEvent) PacketType() PacketType { return TypeKeyEvent }
func (p KeyEvent) appendBody(dst []byte) []byte {
	held := p.Held
	if len(held) > MaxHeldKeys {
		held = held[:MaxHeldKeys]
	}
	dst = binary.LittleEndian.AppendUint16(dst, p.HIDUsage)
	dst = append(dst, boolByte(p.Pressed), uint8(len(held)))
	for _, u := range held {
		dst = binary.LittleEndian.AppendUint16(dst, u)
	}
	return dst
}

// MouseMotion sends raw relative pointer deltas, scroll deltas, and current button bits.
type MouseMotion struct {
	DX      int16
	DY      int16
	WheelX  int16
	WheelY  int16
	Buttons uint8
}

func (MouseMotion) PacketType() PacketType { return TypeMouseMotion }
func (p MouseMotion) appendBody(dst []byte) []byte {
	dst = binary.LittleEndian.AppendUint16(dst, uint16(p.DX))
	dst = binary.LittleEndian.AppendUint16(dst, uint16(p.DY))
	dst = binary.LittleEndian.AppendUint16(dst, uint16(p.WheelX))
	dst = binary.LittleEndian.AppendUint16(dst, uint16(p.WheelY))
	return append(dst, p.Buttons)
}

// MouseButton sends an immediate mouse button state change.
type MouseButton struct {
	Buttons     uint8
	ChangedMask uint8
}

func (MouseButton) PacketType() PacketType { return TypeMouseButton }
func (p MouseButton) appendBody(dst []byte) []byte {
	return append(dst, p.Buttons, p.ChangedMask)
}

// GamepadState carries one XInput-shaped controller snapshot for slots 0-3.
type GamepadState struct {
	Slot         uint8
	Connected    bool
	Buttons      uint16
	LeftTrigger  uint8
	RightTrigger uint8
	LX           int16
	LY           int16
	RX           int16
	RY           int16
}

func (GamepadState) PacketType() PacketType { return TypeGamepadState }
func (p GamepadState) appendBody(dst []byte) []byte {
	dst = append(dst, p.Slot, boolByte(p.Connected))
	dst = binary.LittleEndian.AppendUint16(dst, p.Buttons)
	dst = append(dst, p.LeftTrigger, p.RightTrigger)
	dst = binary.LittleEndian.AppendUint16(dst, uint16(p.LX))
	dst = binary.LittleEndian.AppendUint16(dst, uint16(p.LY))
	dst = binary.LittleEndian.AppendUint16(dst, uint16(p.RX))
	dst = binary.LittleEndian.AppendUint16(dst, uint16(p.RY))
	return dst
}

// ReleaseAll instructs the receiver to release all held remote keys, mouse buttons, and pads.
type ReleaseAll struct {
	Reason uint8
}

func (ReleaseAll) PacketType() PacketType         { return TypeReleaseAll }
func (p ReleaseAll) appendBody(dst []byte) []byte { return append(dst, p.Reason) }

// Rumble carries XInput motor vibration intensities (0-65535) from Madeira back to the PC.
type Rumble struct {
	Slot       uint8
	LeftMotor  uint16
	RightMotor uint16
}

func (Rumble) PacketType() PacketType { return TypeRumble }
func (p Rumble) appendBody(dst []byte) []byte {
	dst = append(dst, p.Slot)
	dst = binary.LittleEndian.AppendUint16(dst, p.LeftMotor)
	return binary.LittleEndian.AppendUint16(dst, p.RightMotor)
}

// Disconnect cleanly closes an active AoL session.
type Disconnect struct {
	Reason uint8
}

func (Disconnect) PacketType() PacketType         { return TypeDisconnect }
func (p Disconnect) appendBody(dst []byte) []byte { return append(dst, p.Reason) }

// StateSync carries an idempotent snapshot of held mouse buttons and HID keys
// so UDP packet loss cannot leave keys or mouse buttons stuck down.
type StateSync struct {
	Buttons uint8
	Held    []uint16
}

func (StateSync) PacketType() PacketType { return TypeStateSync }
func (p StateSync) appendBody(dst []byte) []byte {
	held := p.Held
	if len(held) > MaxHeldKeys {
		held = held[:MaxHeldKeys]
	}
	dst = append(dst, p.Buttons, uint8(len(held)))
	for _, u := range held {
		dst = binary.LittleEndian.AppendUint16(dst, u)
	}
	return dst
}

// PairGrant issues a persistent 32-byte pairing key from Madeira to a PC client,
// masked with the pairing PIN and per-grant nonce.
type PairGrant struct {
	DeviceID  [8]byte
	Nonce     [8]byte
	MaskedKey [32]byte
}

func (PairGrant) PacketType() PacketType { return TypePairGrant }
func (p PairGrant) appendBody(dst []byte) []byte {
	dst = append(dst, p.DeviceID[:]...)
	dst = append(dst, p.Nonce[:]...)
	return append(dst, p.MaskedKey[:]...)
}

// AuthTag derives the 8-byte PIN authentication tag for Hello packets.
// When pin is empty, an all-zero tag is returned.
func AuthTag(pin string) [8]byte {
	var out [8]byte
	if pin == "" {
		return out
	}
	sum := sha256.Sum256([]byte("MAOL-v1:" + pin))
	copy(out[:], sum[:8])
	return out
}

// PairedAuthTag derives an 8-byte HMAC-like authentication tag using a persistent
// 32-byte pairing key, client ID, and the Hello packet sequence number.
func PairedAuthTag(key [32]byte, clientID [8]byte, seq uint32) [8]byte {
	var msg [12 + 32 + 8 + 4]byte
	copy(msg[:12], "MAOL-v1-key:")
	copy(msg[12:44], key[:])
	copy(msg[44:52], clientID[:])
	binary.LittleEndian.PutUint32(msg[52:56], seq)
	sum := sha256.Sum256(msg[:])
	var out [8]byte
	copy(out[:], sum[:8])
	return out
}

// MaskPairKey XOR-masks (or unmasks) a 32-byte pairing key using SHA256("MAOL-v1-mask:" || pin || nonce).
func MaskPairKey(pin string, nonce [8]byte, key [32]byte) [32]byte {
	msg := make([]byte, 0, 13+len(pin)+8)
	msg = append(msg, "MAOL-v1-mask:"...)
	msg = append(msg, pin...)
	msg = append(msg, nonce[:]...)
	mask := sha256.Sum256(msg)
	var out [32]byte
	for i := range out {
		out[i] = key[i] ^ mask[i]
	}
	return out
}

// AppendMarshal encodes a packet with seq appended to dst and returns the extended slice.
func AppendMarshal(dst []byte, seq uint32, pkt Packet) []byte {
	dst = append(dst, magic0, magic1, Version, uint8(pkt.PacketType()))
	dst = binary.LittleEndian.AppendUint32(dst, seq)
	return pkt.appendBody(dst)
}

// Marshal encodes a packet into a newly allocated byte slice.
func Marshal(seq uint32, pkt Packet) []byte {
	return AppendMarshal(make([]byte, 0, 32), seq, pkt)
}

// Unmarshal decodes a single MAOL v1 datagram into its header and concrete Packet.
func Unmarshal(data []byte) (Header, Packet, error) {
	if len(data) < HeaderSize {
		return Header{}, nil, ErrShortPacket
	}
	if data[0] != magic0 || data[1] != magic1 {
		return Header{}, nil, ErrBadMagic
	}
	ver := data[2]
	if ver != Version {
		return Header{}, nil, fmt.Errorf("%w: %d", ErrUnsupportedVersion, ver)
	}
	hdr := Header{
		Version: ver,
		Type:    PacketType(data[3]),
		Seq:     binary.LittleEndian.Uint32(data[4:8]),
	}
	body := data[HeaderSize:]

	switch hdr.Type {
	case TypeDiscover:
		return hdr, Discover{}, nil
	case TypeAnnounce:
		if len(body) < 4 {
			return hdr, nil, ErrTruncated
		}
		flags := body[2]
		name, consumed, err := readShortStringRest(body[3:])
		if err != nil {
			return hdr, nil, err
		}
		var devID [8]byte
		if (flags & AnnounceFlagHasDeviceID) != 0 {
			rest := body[3+consumed:]
			if len(rest) < 8 {
				return hdr, nil, ErrTruncated
			}
			copy(devID[:], rest[:8])
		}
		return hdr, Announce{
			Port:       binary.LittleEndian.Uint16(body[0:2]),
			Flags:      flags,
			DeviceName: name,
			DeviceID:   devID,
		}, nil
	case TypeHello:
		if len(body) < 11 {
			return hdr, nil, ErrTruncated
		}
		flags := body[0]
		var tag [8]byte
		copy(tag[:], body[2:10])
		name, consumed, err := readShortStringRest(body[10:])
		if err != nil {
			return hdr, nil, err
		}
		var cid [8]byte
		if (flags & HelloFlagHasClientID) != 0 {
			rest := body[10+consumed:]
			if len(rest) < 8 {
				return hdr, nil, ErrTruncated
			}
			copy(cid[:], rest[:8])
		}
		return hdr, Hello{
			Flags:      flags,
			DeviceMask: body[1],
			AuthTag:    tag,
			HostName:   name,
			ClientID:   cid,
		}, nil
	case TypeHelloAck:
		if len(body) < 4 {
			return hdr, nil, ErrTruncated
		}
		name, err := readShortString(body[3:])
		if err != nil {
			return hdr, nil, err
		}
		return hdr, HelloAck{
			Status:        body[0],
			SessionActive: body[1] != 0,
			TVActive:      body[2] != 0,
			DeviceName:    name,
		}, nil
	case TypePing:
		if len(body) < 8 {
			return hdr, nil, ErrTruncated
		}
		return hdr, Ping{TimestampUS: binary.LittleEndian.Uint64(body[0:8])}, nil
	case TypePong:
		if len(body) < 8 {
			return hdr, nil, ErrTruncated
		}
		return hdr, Pong{TimestampUS: binary.LittleEndian.Uint64(body[0:8])}, nil
	case TypeKeyEvent:
		if len(body) < 4 {
			return hdr, nil, ErrTruncated
		}
		usage := binary.LittleEndian.Uint16(body[0:2])
		pressed := body[2] != 0
		count := int(body[3])
		if count > MaxHeldKeys {
			count = MaxHeldKeys
		}
		if len(body) < 4+count*2 {
			return hdr, nil, ErrTruncated
		}
		held := make([]uint16, count)
		for i := range count {
			off := 4 + i*2
			held[i] = binary.LittleEndian.Uint16(body[off : off+2])
		}
		return hdr, KeyEvent{HIDUsage: usage, Pressed: pressed, Held: held}, nil
	case TypeMouseMotion:
		if len(body) < 9 {
			return hdr, nil, ErrTruncated
		}
		return hdr, MouseMotion{
			DX:      int16(binary.LittleEndian.Uint16(body[0:2])),
			DY:      int16(binary.LittleEndian.Uint16(body[2:4])),
			WheelX:  int16(binary.LittleEndian.Uint16(body[4:6])),
			WheelY:  int16(binary.LittleEndian.Uint16(body[6:8])),
			Buttons: body[8],
		}, nil
	case TypeMouseButton:
		if len(body) < 2 {
			return hdr, nil, ErrTruncated
		}
		return hdr, MouseButton{Buttons: body[0], ChangedMask: body[1]}, nil
	case TypeGamepadState:
		if len(body) < 14 {
			return hdr, nil, ErrTruncated
		}
		return hdr, GamepadState{
			Slot:         body[0],
			Connected:    body[1] != 0,
			Buttons:      binary.LittleEndian.Uint16(body[2:4]),
			LeftTrigger:  body[4],
			RightTrigger: body[5],
			LX:           int16(binary.LittleEndian.Uint16(body[6:8])),
			LY:           int16(binary.LittleEndian.Uint16(body[8:10])),
			RX:           int16(binary.LittleEndian.Uint16(body[10:12])),
			RY:           int16(binary.LittleEndian.Uint16(body[12:14])),
		}, nil
	case TypeReleaseAll:
		if len(body) < 1 {
			return hdr, nil, ErrTruncated
		}
		return hdr, ReleaseAll{Reason: body[0]}, nil
	case TypeRumble:
		if len(body) < 5 {
			return hdr, nil, ErrTruncated
		}
		return hdr, Rumble{
			Slot:       body[0],
			LeftMotor:  binary.LittleEndian.Uint16(body[1:3]),
			RightMotor: binary.LittleEndian.Uint16(body[3:5]),
		}, nil
	case TypeDisconnect:
		if len(body) < 1 {
			return hdr, nil, ErrTruncated
		}
		return hdr, Disconnect{Reason: body[0]}, nil
	case TypeStateSync:
		if len(body) < 2 {
			return hdr, nil, ErrTruncated
		}
		buttons := body[0]
		count := int(body[1])
		if count > MaxHeldKeys {
			count = MaxHeldKeys
		}
		if len(body) < 2+count*2 {
			return hdr, nil, ErrTruncated
		}
		held := make([]uint16, count)
		for i := range count {
			off := 2 + i*2
			held[i] = binary.LittleEndian.Uint16(body[off : off+2])
		}
		return hdr, StateSync{Buttons: buttons, Held: held}, nil
	case TypePairGrant:
		if len(body) < 48 {
			return hdr, nil, ErrTruncated
		}
		var p PairGrant
		copy(p.DeviceID[:], body[0:8])
		copy(p.Nonce[:], body[8:16])
		copy(p.MaskedKey[:], body[16:48])
		return hdr, p, nil
	default:
		return hdr, nil, fmt.Errorf("%w: 0x%02x", ErrUnknownType, uint8(hdr.Type))
	}
}

func appendShortString(dst []byte, s string) []byte {
	b := []byte(s)
	if len(b) > 255 {
		b = b[:255]
	}
	dst = append(dst, uint8(len(b)))
	return append(dst, b...)
}

func readShortStringRest(b []byte) (string, int, error) {
	if len(b) < 1 {
		return "", 0, ErrTruncated
	}
	n := int(b[0])
	if len(b) < 1+n {
		return "", 0, ErrTruncated
	}
	return string(b[1 : 1+n]), 1 + n, nil
}

func readShortString(b []byte) (string, error) {
	s, _, err := readShortStringRest(b)
	return s, err
}

func boolByte(v bool) uint8 {
	if v {
		return 1
	}
	return 0
}
