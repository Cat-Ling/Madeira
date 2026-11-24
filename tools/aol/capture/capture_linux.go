// SPDX-FileCopyrightText: 2026 Cat-Ling
// SPDX-License-Identifier: GPL-3.0-or-later

//go:build linux

package capture

import (
	"context"
	"encoding/binary"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"sync"
	"syscall"
	"time"
	"unsafe"

	"github.com/Cat-Ling/Madeira/tools/aol/protocol"
)

// Linux input event types and codes.
const (
	evSyn uint16 = 0x00
	evKey uint16 = 0x01
	evRel uint16 = 0x02
	evAbs uint16 = 0x03
	evFF  uint16 = 0x15

	relX      uint16 = 0x00
	relY      uint16 = 0x01
	relHWheel uint16 = 0x06
	relWheel  uint16 = 0x08

	absX     uint16 = 0x00
	absY     uint16 = 0x01
	absZ     uint16 = 0x02
	absRX    uint16 = 0x03
	absRY    uint16 = 0x04
	absRZ    uint16 = 0x05
	absHat0X uint16 = 0x10
	absHat0Y uint16 = 0x11

	btnLeft   uint16 = 0x110
	btnRight  uint16 = 0x111
	btnMiddle uint16 = 0x112
	btnSide   uint16 = 0x113
	btnExtra  uint16 = 0x114

	btnSouth  uint16 = 0x130
	btnEast   uint16 = 0x131
	btnNorth  uint16 = 0x133
	btnWest   uint16 = 0x134
	btnTL     uint16 = 0x136
	btnTR     uint16 = 0x137
	btnSelect uint16 = 0x13A
	btnStart  uint16 = 0x13B
	btnMode   uint16 = 0x13C
	btnThumbL uint16 = 0x13D
	btnThumbR uint16 = 0x13E

	btnDPadUp    uint16 = 0x220
	btnDPadDown  uint16 = 0x221
	btnDPadLeft  uint16 = 0x222
	btnDPadRight uint16 = 0x223

	keyMax = 0x2ff
	absMax = 0x3f

	ffRumble uint16 = 0x50
)

// RawInputEvent mirrors Linux's evdev struct input_event fields.
type RawInputEvent struct {
	Type  uint16
	Code  uint16
	Value int32
}

type absInfo struct {
	Value      int32
	Minimum    int32
	Maximum    int32
	Fuzz       int32
	Flat       int32
	Resolution int32
}

type ffTrigger struct {
	Button   uint16
	Interval uint16
}

type ffReplay struct {
	Length uint16
	Delay  uint16
}

type ffRumbleEffect struct {
	Strong uint16
	Weak   uint16
}

type ffEffect struct {
	Type      uint16
	ID        int16
	Direction uint16
	Trigger   ffTrigger
	Replay    ffReplay
	_         [2]byte
	U         [32]byte
}

type linuxDevice struct {
	path      string
	name      string
	file      *os.File
	isKB      bool
	isMouse   bool
	isGamepad bool
	padSlot   uint8
	grabbed   bool
	rw        bool
	abs       [absMax + 1]absInfo
	absValid  [absMax + 1]bool
	padState  protocol.GamepadState
	ffID      int16
	hasFF     bool
}

type evdevKey struct {
	dev  *linuxDevice
	code uint16
}

type linuxCapturer struct {
	opts          Options
	mu            sync.Mutex
	devices       []*linuxDevice
	grabbed       bool
	pendingGrab   bool
	pendingUngrab bool
	held          []uint16
	heldEv        map[evdevKey]struct{}
	mouseBtns     uint8
	keyboards     int
	mice          int
	gamepads      int
	grabFn        func(on bool)
}

// New creates a platform input Capturer for Linux evdev devices.
func New(opts Options) (Capturer, error) {
	c := &linuxCapturer{
		opts:    opts,
		grabbed: opts.Grab,
		heldEv:  make(map[evdevKey]struct{}),
	}
	if err := c.openDevices(); err != nil {
		return nil, err
	}
	return c, nil
}

func (c *linuxCapturer) Summary() Summary {
	c.mu.Lock()
	defer c.mu.Unlock()
	return Summary{
		Keyboards: c.keyboards,
		Mice:      c.mice,
		Gamepads:  c.gamepads,
		Grabbed:   c.grabbed,
	}
}

func (c *linuxCapturer) Run(ctx context.Context) error {
	defer c.closeAll()
	if c.grabbed {
		// Wait briefly for startup keys (e.g. Enter) to be released so the host
		// compositor/TTY receives the key-up before EVIOCGRAB takes ownership.
		c.waitKeysReleased(ctx, 500*time.Millisecond)
		c.applyGrab(true)
	}

	evSize := linuxEventSize()
	var wg sync.WaitGroup
	for _, dev := range c.devices {
		wg.Add(1)
		go func(d *linuxDevice) {
			defer wg.Done()
			c.readDevice(ctx, d, evSize)
		}(dev)
	}

	<-ctx.Done()
	c.applyGrab(false)
	c.closeAll()
	wg.Wait()
	return nil
}

func (c *linuxCapturer) SetRumble(slot uint8, left, right uint16) error {
	if !c.opts.Rumble {
		return nil
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	for _, d := range c.devices {
		if !d.isGamepad || d.padSlot != slot || !d.rw || d.file == nil {
			continue
		}
		var eff ffEffect
		eff.Type = ffRumble
		if d.hasFF {
			eff.ID = d.ffID
		} else {
			eff.ID = -1
		}
		eff.Replay.Length = 2500
		rumble := (*ffRumbleEffect)(unsafe.Pointer(&eff.U[0]))
		rumble.Strong = left
		rumble.Weak = right
		req := ioc(1|2, 'E', 0x80, unsafe.Sizeof(eff))
		_, _, errno := syscall.Syscall(syscall.SYS_IOCTL, d.file.Fd(), req, uintptr(unsafe.Pointer(&eff)))
		if errno != 0 {
			continue
		}
		d.ffID = eff.ID
		d.hasFF = true

		ev := make([]byte, linuxEventSize())
		off := len(ev) - 8
		binary.LittleEndian.PutUint16(ev[off:], evFF)
		binary.LittleEndian.PutUint16(ev[off+2:], uint16(d.ffID))
		binary.LittleEndian.PutUint32(ev[off+4:], 1)
		_, _ = d.file.Write(ev)
	}
	return nil
}

func (c *linuxCapturer) openDevices() error {
	paths, err := filepath.Glob("/dev/input/event*")
	if err != nil {
		return fmt.Errorf("enumerate evdev nodes: %w", err)
	}
	slices.Sort(paths)

	var padSlot uint8
	for _, p := range paths {
		flags := syscall.O_RDONLY | syscall.O_NONBLOCK
		rw := false
		if c.opts.Rumble {
			if fTry, err := os.OpenFile(p, syscall.O_RDWR|syscall.O_NONBLOCK, 0); err == nil {
				fTry.Close()
				flags = syscall.O_RDWR | syscall.O_NONBLOCK
				rw = true
			}
		}
		f, err := os.OpenFile(p, flags, 0)
		if err != nil {
			continue
		}
		dev, keep := inspectLinuxDevice(f, p, rw, c.opts, &padSlot)
		if !keep {
			_ = f.Close()
			continue
		}
		if dev.isKB {
			c.keyboards++
		}
		if dev.isMouse {
			c.mice++
		}
		if dev.isGamepad {
			c.gamepads++
		}
		c.devices = append(c.devices, dev)
	}

	if len(c.devices) == 0 {
		return fmt.Errorf("no readable evdev input devices under /dev/input/event* (ensure input group or udev permissions)")
	}
	return nil
}

func inspectLinuxDevice(f *os.File, path string, rw bool, opts Options, padSlot *uint8) (*linuxDevice, bool) {
	fd := f.Fd()
	var evBits [1]uint32
	if ioctlBytes(fd, ioc(2, 'E', 0x20, uintptr(unsafe.Sizeof(evBits))), unsafe.Pointer(&evBits[0])) != nil {
		return nil, false
	}

	var keyBits [(keyMax/8 + 7) / 8]uint64
	if (evBits[0] & (1 << evKey)) != 0 {
		_ = ioctlBytes(fd, ioc(2, 'E', uintptr(0x20+evKey), uintptr(unsafe.Sizeof(keyBits))), unsafe.Pointer(&keyBits[0]))
	}
	var relBits [1]uint32
	if (evBits[0] & (1 << evRel)) != 0 {
		_ = ioctlBytes(fd, ioc(2, 'E', uintptr(0x20+evRel), uintptr(unsafe.Sizeof(relBits))), unsafe.Pointer(&relBits[0]))
	}
	var absBits [(absMax/8 + 7) / 8]uint64
	if (evBits[0] & (1 << evAbs)) != 0 {
		_ = ioctlBytes(fd, ioc(2, 'E', uintptr(0x20+evAbs), uintptr(unsafe.Sizeof(absBits))), unsafe.Pointer(&absBits[0]))
	}

	hasKey := func(k uint16) bool {
		idx := k / 64
		bit := k % 64
		return int(idx) < len(keyBits) && (keyBits[idx]&(1<<bit)) != 0
	}
	hasAbs := func(a uint16) bool {
		idx := a / 64
		bit := a % 64
		return int(idx) < len(absBits) && (absBits[idx]&(1<<bit)) != 0
	}

	isKB := opts.Keyboard && hasKey(30) && hasKey(48) // KEY_A and KEY_B
	isMouse := opts.Mouse && (relBits[0]&(1<<relX|1<<relY)) != 0 && hasKey(btnLeft)
	isGamepad := opts.Gamepad && (hasKey(btnSouth) || hasKey(btnEast)) && (hasAbs(absX) || hasAbs(absY))

	if !isKB && !isMouse && !isGamepad {
		return nil, false
	}

	var nameBuf [128]byte
	name := path
	if ioctlBytes(fd, ioc(2, 'E', 0x06, uintptr(len(nameBuf))), unsafe.Pointer(&nameBuf[0])) == nil {
		for i, b := range nameBuf {
			if b == 0 {
				if i > 0 {
					name = string(nameBuf[:i])
				}
				break
			}
		}
	}

	d := &linuxDevice{
		path:      path,
		name:      name,
		file:      f,
		isKB:      isKB,
		isMouse:   isMouse,
		isGamepad: isGamepad,
		rw:        rw,
	}
	if isGamepad {
		if *padSlot >= 4 {
			d.isGamepad = false
		} else {
			d.padSlot = *padSlot
			d.padState = protocol.GamepadState{Slot: d.padSlot, Connected: true}
			*padSlot++
			for ax := uint16(0); ax <= absMax; ax++ {
				if !hasAbs(ax) {
					continue
				}
				var info absInfo
				if ioctlBytes(fd, ioc(2, 'E', 0x40+uintptr(ax), unsafe.Sizeof(info)), unsafe.Pointer(&info)) == nil {
					d.abs[ax] = info
					d.absValid[ax] = true
				}
			}
		}
	}
	if !d.isKB && !d.isMouse && !d.isGamepad {
		return nil, false
	}
	return d, true
}

func (c *linuxCapturer) readDevice(ctx context.Context, d *linuxDevice, evSize int) {
	defer c.clearDeviceKeys(d)
	buf := make([]byte, evSize*64)
	for ctx.Err() == nil {
		n, err := d.file.Read(buf)
		if n > 0 {
			events := ParseLinuxEvents(buf[:n], evSize)
			c.processDeviceBatch(d, events)
		}
		if err != nil {
			if ctx.Err() != nil {
				return
			}
			return
		}
	}
}

func (c *linuxCapturer) clearDeviceKeys(d *linuxDevice) {
	var (
		applyGrabOn  bool
		applyGrabOff bool
		emitGrabbed  bool
	)
	c.mu.Lock()
	for k := range c.heldEv {
		if k.dev == d {
			delete(c.heldEv, k)
			if hid := protocol.LinuxEvdevToHID(k.code); hid != 0 {
				c.held = slices.DeleteFunc(c.held, func(u uint16) bool { return u == hid })
			}
		}
	}
	if len(c.heldEv) == 0 {
		if c.pendingGrab {
			c.pendingGrab = false
			c.grabbed = true
			applyGrabOn = c.opts.Grab
			emitGrabbed = true
		} else if c.pendingUngrab {
			c.pendingUngrab = false
			applyGrabOff = true
		}
	}
	c.mu.Unlock()
	if applyGrabOn {
		c.applyGrab(true)
	} else if applyGrabOff {
		c.applyGrab(false)
	}
	if emitGrabbed && c.opts.OnEvent != nil {
		c.opts.OnEvent(Event{Kind: EventCaptureToggled, Grabbed: true})
	}
}

func (c *linuxCapturer) processDeviceBatch(d *linuxDevice, events []RawInputEvent) {
	var (
		dx, dy, wx, wy int32
		mouseDirty     bool
		padDirty       bool
		applyGrabOn    bool
		applyGrabOff   bool
		emitToggle     bool
		emitGrabState  bool
	)

	c.mu.Lock()
	if c.heldEv == nil {
		c.heldEv = make(map[evdevKey]struct{})
	}
	for _, ev := range events {
		switch ev.Type {
		case evKey:
			if d.isKB && ev.Value != 2 {
				ek := evdevKey{dev: d, code: ev.Code}
				pressed := ev.Value != 0
				_, wasDown := c.heldEv[ek]
				if pressed {
					c.heldEv[ek] = struct{}{}
				} else {
					delete(c.heldEv, ek)
				}

				if hid := protocol.LinuxEvdevToHID(ev.Code); hid != 0 {
					var chordTriggered bool
					if pressed {
						if !slices.Contains(c.held, hid) {
							c.held = append(c.held, hid)
						}
						if !wasDown && hid == protocol.HIDKeyG &&
							(slices.Contains(c.held, protocol.HIDLeftCtrl) || slices.Contains(c.held, protocol.HIDRightCtrl)) &&
							(slices.Contains(c.held, protocol.HIDLeftAlt) || slices.Contains(c.held, protocol.HIDRightAlt)) {
							chordTriggered = true
							if c.grabbed {
								// Stop forwarding to Madeira immediately and notify iOS
								// to release held keys, but keep EVIOCGRAB until all
								// chord keys are released so repeats/releases do not leak
								// to the host terminal.
								c.grabbed = false
								c.mouseBtns = 0
								if c.opts.Grab {
									c.pendingUngrab = true
								}
								c.pendingGrab = false
								emitToggle = true
								emitGrabState = false
							} else if !c.pendingGrab && !c.pendingUngrab {
								// Defer EVIOCGRAB until the user releases all chord keys
								// so the host OS receives every key-up and never gets
								// stuck repeating Ctrl+Alt+G.
								c.pendingGrab = true
							}
						}
					} else {
						c.held = slices.DeleteFunc(c.held, func(u uint16) bool { return u == hid })
					}

					if c.grabbed && !chordTriggered && c.opts.OnEvent != nil {
						heldCopy := slices.Clone(c.held)
						c.emitLocked(Event{
							Kind: EventKey,
							Key:  protocol.KeyEvent{HIDUsage: hid, Pressed: pressed, Held: heldCopy},
						})
					}
				}

				if !pressed && len(c.heldEv) == 0 {
					if c.pendingGrab {
						c.pendingGrab = false
						c.grabbed = true
						applyGrabOn = c.opts.Grab
						emitToggle = true
						emitGrabState = true
					} else if c.pendingUngrab {
						c.pendingUngrab = false
						applyGrabOff = true
					}
				}
			}
			if d.isMouse && ev.Value != 2 {
				if bit := mouseButtonBit(ev.Code); bit != 0 {
					if ev.Value != 0 {
						c.mouseBtns |= bit
					} else {
						c.mouseBtns &^= bit
					}
					if c.grabbed && c.opts.OnEvent != nil {
						c.emitLocked(Event{
							Kind:    EventMouseButton,
							Buttons: protocol.MouseButton{Buttons: c.mouseBtns, ChangedMask: bit},
						})
					}
				}
			}
			if d.isGamepad && ev.Value != 2 {
				if mask := gamepadButtonMask(ev.Code); mask != 0 {
					if ev.Value != 0 {
						d.padState.Buttons |= mask
					} else {
						d.padState.Buttons &^= mask
					}
					padDirty = true
				}
			}

		case evRel:
			if d.isMouse {
				switch ev.Code {
				case relX:
					dx += ev.Value
					mouseDirty = true
				case relY:
					dy += ev.Value
					mouseDirty = true
				case relWheel:
					wy += ev.Value
					mouseDirty = true
				case relHWheel:
					wx += ev.Value
					mouseDirty = true
				}
			}

		case evAbs:
			if d.isGamepad {
				applyGamepadAbs(d, ev.Code, ev.Value)
				padDirty = true
			}

		case evSyn:
			if mouseDirty && c.grabbed {
				c.emitLocked(Event{
					Kind: EventMouseMotion,
					Mouse: protocol.MouseMotion{
						DX:      clampInt16(dx),
						DY:      clampInt16(dy),
						WheelX:  clampInt16(wx),
						WheelY:  clampInt16(wy),
						Buttons: c.mouseBtns,
					},
				})
				dx, dy, wx, wy = 0, 0, 0, 0
				mouseDirty = false
			}
			if padDirty {
				c.emitLocked(Event{Kind: EventGamepad, Gamepad: d.padState})
				padDirty = false
			}
		}
	}

	if mouseDirty && c.grabbed {
		c.emitLocked(Event{
			Kind: EventMouseMotion,
			Mouse: protocol.MouseMotion{
				DX:      clampInt16(dx),
				DY:      clampInt16(dy),
				WheelX:  clampInt16(wx),
				WheelY:  clampInt16(wy),
				Buttons: c.mouseBtns,
			},
		})
	}
	if padDirty {
		c.emitLocked(Event{Kind: EventGamepad, Gamepad: d.padState})
	}
	c.mu.Unlock()

	if applyGrabOn {
		c.applyGrab(true)
	} else if applyGrabOff {
		c.applyGrab(false)
	}
	if emitToggle && c.opts.OnEvent != nil {
		c.opts.OnEvent(Event{Kind: EventCaptureToggled, Grabbed: emitGrabState})
	}
}

func (c *linuxCapturer) emitLocked(ev Event) {
	if c.opts.OnEvent != nil {
		c.opts.OnEvent(ev)
	}
}

func (c *linuxCapturer) waitKeysReleased(ctx context.Context, maxWait time.Duration) {
	deadline := time.Now().Add(maxWait)
	for time.Now().Before(deadline) && ctx.Err() == nil {
		if !c.anyKeyboardKeyDown() {
			return
		}
		select {
		case <-ctx.Done():
			return
		case <-time.After(10 * time.Millisecond):
		}
	}
}

func (c *linuxCapturer) anyKeyboardKeyDown() bool {
	c.mu.Lock()
	devs := slices.Clone(c.devices)
	c.mu.Unlock()

	var keyState [(keyMax/8 + 7) / 8]uint64
	req := ioc(2, 'E', 0x18, uintptr(unsafe.Sizeof(keyState))) // EVIOCGKEY
	for _, d := range devs {
		if !d.isKB || d.file == nil {
			continue
		}
		clear(keyState[:])
		if ioctlBytes(d.file.Fd(), req, unsafe.Pointer(&keyState[0])) == nil {
			for _, word := range keyState {
				if word != 0 {
					return true
				}
			}
		}
	}
	return false
}

func (c *linuxCapturer) applyGrab(on bool) {
	if c.grabFn != nil {
		c.grabFn(on)
		return
	}
	c.mu.Lock()
	devs := slices.Clone(c.devices)
	c.mu.Unlock()
	val := uintptr(0)
	if on {
		val = 1
	}
	req := ioc(1, 'E', 0x90, 4)
	for _, d := range devs {
		if (!d.isKB && !d.isMouse) || d.file == nil {
			continue
		}
		_, _, errno := syscall.Syscall(syscall.SYS_IOCTL, d.file.Fd(), req, val)
		if errno == 0 {
			d.grabbed = on
		}
	}
}

func (c *linuxCapturer) closeAll() {
	c.mu.Lock()
	devs := c.devices
	c.devices = nil
	c.mu.Unlock()
	for _, d := range devs {
		if d.grabbed && d.file != nil {
			_, _, _ = syscall.Syscall(syscall.SYS_IOCTL, d.file.Fd(), ioc(1, 'E', 0x90, 4), 0)
		}
		if d.file != nil {
			_ = d.file.Close()
		}
	}
}

// ParseLinuxEvents decodes raw Linux evdev input_event byte slices of eventSize
// (24 on 64-bit kernels, 16 on 32-bit kernels) into RawInputEvent records.
func ParseLinuxEvents(buf []byte, eventSize int) []RawInputEvent {
	if eventSize < 16 {
		return nil
	}
	count := len(buf) / eventSize
	out := make([]RawInputEvent, 0, count)
	for i := range count {
		off := i*eventSize + (eventSize - 8)
		out = append(out, RawInputEvent{
			Type:  binary.LittleEndian.Uint16(buf[off : off+2]),
			Code:  binary.LittleEndian.Uint16(buf[off+2 : off+4]),
			Value: int32(binary.LittleEndian.Uint32(buf[off+4 : off+8])),
		})
	}
	return out
}

func linuxEventSize() int {
	var tv syscall.Timeval
	return int(unsafe.Sizeof(tv)) + 8
}

func ioc(dir, typ, nr, size uintptr) uintptr {
	return (dir << 30) | (size << 16) | (typ << 8) | nr
}

func ioctlBytes(fd, req uintptr, ptr unsafe.Pointer) error {
	_, _, errno := syscall.Syscall(syscall.SYS_IOCTL, fd, req, uintptr(ptr))
	if errno != 0 {
		return errno
	}
	return nil
}

func mouseButtonBit(code uint16) uint8 {
	switch code {
	case btnLeft:
		return protocol.MouseButtonLeft
	case btnRight:
		return protocol.MouseButtonRight
	case btnMiddle:
		return protocol.MouseButtonMiddle
	case btnSide:
		return protocol.MouseButtonX1
	case btnExtra:
		return protocol.MouseButtonX2
	default:
		return 0
	}
}

func gamepadButtonMask(code uint16) uint16 {
	switch code {
	case btnSouth:
		return protocol.GamepadA
	case btnEast:
		return protocol.GamepadB
	case btnWest:
		return protocol.GamepadX
	case btnNorth:
		return protocol.GamepadY
	case btnTL:
		return protocol.GamepadLShoulder
	case btnTR:
		return protocol.GamepadRShoulder
	case btnSelect:
		return protocol.GamepadBack
	case btnStart:
		return protocol.GamepadStart
	case btnMode:
		return protocol.GamepadGuide
	case btnThumbL:
		return protocol.GamepadLThumb
	case btnThumbR:
		return protocol.GamepadRThumb
	case btnDPadUp:
		return protocol.GamepadDPadUp
	case btnDPadDown:
		return protocol.GamepadDPadDown
	case btnDPadLeft:
		return protocol.GamepadDPadLeft
	case btnDPadRight:
		return protocol.GamepadDPadRight
	default:
		return 0
	}
}

func applyGamepadAbs(d *linuxDevice, code uint16, value int32) {
	axisRange := func(ax uint16) (int32, int32) {
		if int(ax) < len(d.absValid) && d.absValid[ax] {
			return d.abs[ax].Minimum, d.abs[ax].Maximum
		}
		return -32768, 32767
	}
	trigRange := func(ax uint16) (int32, int32) {
		if int(ax) < len(d.absValid) && d.absValid[ax] {
			return d.abs[ax].Minimum, d.abs[ax].Maximum
		}
		return 0, 255
	}
	switch code {
	case absX:
		minV, maxV := axisRange(absX)
		d.padState.LX = NormalizeAxis(value, minV, maxV, false)
	case absY:
		minV, maxV := axisRange(absY)
		d.padState.LY = NormalizeAxis(value, minV, maxV, true)
	case absRX:
		minV, maxV := axisRange(absRX)
		d.padState.RX = NormalizeAxis(value, minV, maxV, false)
	case absRY:
		minV, maxV := axisRange(absRY)
		d.padState.RY = NormalizeAxis(value, minV, maxV, true)
	case absZ:
		minV, maxV := trigRange(absZ)
		d.padState.LeftTrigger = NormalizeTrigger(value, minV, maxV)
	case absRZ:
		minV, maxV := trigRange(absRZ)
		d.padState.RightTrigger = NormalizeTrigger(value, minV, maxV)
	case absHat0X:
		d.padState.Buttons &^= protocol.GamepadDPadLeft | protocol.GamepadDPadRight
		if value < 0 {
			d.padState.Buttons |= protocol.GamepadDPadLeft
		} else if value > 0 {
			d.padState.Buttons |= protocol.GamepadDPadRight
		}
	case absHat0Y:
		d.padState.Buttons &^= protocol.GamepadDPadUp | protocol.GamepadDPadDown
		if value < 0 {
			d.padState.Buttons |= protocol.GamepadDPadUp
		} else if value > 0 {
			d.padState.Buttons |= protocol.GamepadDPadDown
		}
	}
}

func clampInt16(v int32) int16 {
	if v > 32767 {
		return 32767
	}
	if v < -32768 {
		return -32768
	}
	return int16(v)
}
