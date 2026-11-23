// SPDX-FileCopyrightText: 2026 Cat-Ling
// SPDX-License-Identifier: GPL-3.0-or-later

//go:build windows

package capture

import (
	"context"
	"runtime"
	"slices"
	"sync"
	"syscall"
	"time"
	"unsafe"

	"github.com/Cat-Ling/Madeira/tools/aol/protocol"
)

const (
	wmDestroy = 0x0002
	wmClose   = 0x0010
	wmInput   = 0x00FF

	rimTypeMouse    = 0
	rimTypeKeyboard = 1

	ridevRemove    = 0x00000001
	ridevInputSink = 0x00000100
	ridInput       = 0x10000003

	riKeyBreak = 0x0001
	riKeyE0    = 0x0002

	riMouseLeftDown   = 0x0001
	riMouseLeftUp     = 0x0002
	riMouseRightDown  = 0x0004
	riMouseRightUp    = 0x0008
	riMouseMiddleDown = 0x0010
	riMouseMiddleUp   = 0x0020
	riMouseBtn4Down   = 0x0040
	riMouseBtn4Up     = 0x0080
	riMouseBtn5Down   = 0x0100
	riMouseBtn5Up     = 0x0200
	riMouseWheel      = 0x0400
	riMouseHWheel     = 0x0800
)

var (
	user32   = syscall.NewLazyDLL("user32.dll")
	kernel32 = syscall.NewLazyDLL("kernel32.dll")

	procRegisterClassExW     = user32.NewProc("RegisterClassExW")
	procCreateWindowExW      = user32.NewProc("CreateWindowExW")
	procDestroyWindow        = user32.NewProc("DestroyWindow")
	procDefWindowProcW       = user32.NewProc("DefWindowProcW")
	procGetMessageW          = user32.NewProc("GetMessageW")
	procTranslateMessage     = user32.NewProc("TranslateMessage")
	procDispatchMessageW     = user32.NewProc("DispatchMessageW")
	procPostQuitMessage      = user32.NewProc("PostQuitMessage")
	procPostMessageW         = user32.NewProc("PostMessageW")
	procRegisterRawInput     = user32.NewProc("RegisterRawInputDevices")
	procGetRawInputData      = user32.NewProc("GetRawInputData")
	procGetModuleHandleW     = kernel32.NewProc("GetModuleHandleW")
	xinputDLL                = loadXInputDLL()
	procXInputGetState       = xinputDLL.NewProc("XInputGetState")
	procXInputSetState       = xinputDLL.NewProc("XInputSetState")
	windowsCapturerRegistry  sync.Mutex
	activeWindowsCapturerPtr *windowsCapturer
)

func loadXInputDLL() *syscall.LazyDLL {
	d := syscall.NewLazyDLL("xinput1_4.dll")
	if err := d.Load(); err == nil {
		return d
	}
	return syscall.NewLazyDLL("xinput9_1_0.dll")
}

type rawInputDevice struct {
	UsagePage uint16
	Usage     uint16
	Flags     uint32
	Target    uintptr
}

type rawInputHeader struct {
	Type   uint32
	Size   uint32
	Device uintptr
	WParam uintptr
}

type rawMouse struct {
	Flags            uint16
	ButtonFlags      uint16
	ButtonData       uint16
	RawButtons       uint32
	LastX            int32
	LastY            int32
	ExtraInformation uint32
}

type rawKeyboard struct {
	MakeCode         uint16
	Flags            uint16
	Reserved         uint16
	VKey             uint16
	Message          uint32
	ExtraInformation uint32
}

type rawInputPacket struct {
	Header rawInputHeader
	Mouse  rawMouse
}

type xinputGamepad struct {
	Buttons      uint16
	LeftTrigger  uint8
	RightTrigger uint8
	ThumbLX      int16
	ThumbLY      int16
	ThumbRX      int16
	ThumbRY      int16
}

type xinputState struct {
	PacketNumber uint32
	Gamepad      xinputGamepad
}

type xinputVibration struct {
	LeftMotorSpeed  uint16
	RightMotorSpeed uint16
}

type wndClassExW struct {
	Size       uint32
	Style      uint32
	WndProc    uintptr
	ClsExtra   int32
	WndExtra   int32
	Instance   uintptr
	Icon       uintptr
	Cursor     uintptr
	Background uintptr
	MenuName   *uint16
	ClassName  *uint16
	IconSm     uintptr
}

type winMsg struct {
	Hwnd    uintptr
	Message uint32
	WParam  uintptr
	LParam  uintptr
	Time    uint32
	PtX     int32
	PtY     int32
}

type windowsCapturer struct {
	opts      Options
	mu        sync.Mutex
	hwnd      uintptr
	grabbed   bool
	held      []uint16
	mouseBtns uint8
	lastPads  [4]protocol.GamepadState
	xinputOk  bool
}

// New creates a pure-Go Raw Input + XInput Capturer for Windows.
func New(opts Options) (Capturer, error) {
	c := &windowsCapturer{
		opts:     opts,
		grabbed:  true,
		xinputOk: xinputDLL.Load() == nil,
	}
	return c, nil
}

func (c *windowsCapturer) Summary() Summary {
	c.mu.Lock()
	defer c.mu.Unlock()
	pads := 0
	for _, p := range c.lastPads {
		if p.Connected {
			pads++
		}
	}
	kb := 0
	if c.opts.Keyboard {
		kb = 1
	}
	ms := 0
	if c.opts.Mouse {
		ms = 1
	}
	return Summary{
		Keyboards: kb,
		Mice:      ms,
		Gamepads:  pads,
		Grabbed:   c.grabbed,
	}
}

func (c *windowsCapturer) SetRumble(slot uint8, left, right uint16) error {
	if !c.opts.Rumble || !c.xinputOk || slot >= 4 {
		return nil
	}
	vib := xinputVibration{LeftMotorSpeed: left, RightMotorSpeed: right}
	_, _, _ = procXInputSetState.Call(uintptr(slot), uintptr(unsafe.Pointer(&vib)))
	return nil
}

func (c *windowsCapturer) Run(ctx context.Context) error {
	var wg sync.WaitGroup
	errCh := make(chan error, 1)

	if c.opts.Gamepad && c.xinputOk {
		wg.Add(1)
		go func() {
			defer wg.Done()
			c.pollXInput(ctx)
		}()
	}

	if c.opts.Keyboard || c.opts.Mouse {
		wg.Add(1)
		go func() {
			defer wg.Done()
			errCh <- c.runRawInputLoop(ctx)
		}()
	} else {
		<-ctx.Done()
	}

	<-ctx.Done()
	c.mu.Lock()
	hwnd := c.hwnd
	c.mu.Unlock()
	if hwnd != 0 {
		_, _, _ = procPostMessageW.Call(hwnd, wmClose, 0, 0)
	}
	wg.Wait()

	select {
	case err := <-errCh:
		return err
	default:
		return nil
	}
}

func (c *windowsCapturer) runRawInputLoop(ctx context.Context) error {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()

	windowsCapturerRegistry.Lock()
	activeWindowsCapturerPtr = c
	windowsCapturerRegistry.Unlock()
	defer func() {
		windowsCapturerRegistry.Lock()
		if activeWindowsCapturerPtr == c {
			activeWindowsCapturerPtr = nil
		}
		windowsCapturerRegistry.Unlock()
	}()

	hInst, _, _ := procGetModuleHandleW.Call(0)
	clsName, _ := syscall.UTF16PtrFromString("MadeiraAoLRawInputWindow")
	wndProc := syscall.NewCallback(rawInputWndProc)

	wc := wndClassExW{
		Size:      uint32(unsafe.Sizeof(wndClassExW{})),
		WndProc:   wndProc,
		Instance:  hInst,
		ClassName: clsName,
	}
	_, _, _ = procRegisterClassExW.Call(uintptr(unsafe.Pointer(&wc)))

	hwndMessage := ^uintptr(2) // HWND_MESSAGE = (HWND)-3
	hwnd, _, err := procCreateWindowExW.Call(0, uintptr(unsafe.Pointer(clsName)), 0, 0, 0, 0, 0, 0, hwndMessage, 0, hInst, 0)
	if hwnd == 0 {
		return err
	}
	c.mu.Lock()
	c.hwnd = hwnd
	c.mu.Unlock()
	defer func() {
		_, _, _ = procDestroyWindow.Call(hwnd)
	}()

	var devs []rawInputDevice
	if c.opts.Mouse {
		devs = append(devs, rawInputDevice{UsagePage: 0x01, Usage: 0x02, Flags: ridevInputSink, Target: hwnd})
	}
	if c.opts.Keyboard {
		devs = append(devs, rawInputDevice{UsagePage: 0x01, Usage: 0x06, Flags: ridevInputSink, Target: hwnd})
	}
	if len(devs) > 0 {
		_, _, _ = procRegisterRawInput.Call(uintptr(unsafe.Pointer(&devs[0])), uintptr(len(devs)), unsafe.Sizeof(rawInputDevice{}))
	}

	var msg winMsg
	for ctx.Err() == nil {
		r, _, _ := procGetMessageW.Call(uintptr(unsafe.Pointer(&msg)), 0, 0, 0)
		if int32(r) <= 0 {
			break
		}
		_, _, _ = procTranslateMessage.Call(uintptr(unsafe.Pointer(&msg)))
		_, _, _ = procDispatchMessageW.Call(uintptr(unsafe.Pointer(&msg)))
	}
	return nil
}

func rawInputWndProc(hwnd uintptr, msg uint32, wParam, lParam uintptr) uintptr {
	switch msg {
	case wmInput:
		windowsCapturerRegistry.Lock()
		c := activeWindowsCapturerPtr
		windowsCapturerRegistry.Unlock()
		if c != nil {
			c.handleRawInput(lParam)
		}
		return 0
	case wmClose:
		_, _, _ = procDestroyWindow.Call(hwnd)
		return 0
	case wmDestroy:
		_, _, _ = procPostQuitMessage.Call(0)
		return 0
	}
	r, _, _ := procDefWindowProcW.Call(hwnd, uintptr(msg), wParam, lParam)
	return r
}

func (c *windowsCapturer) handleRawInput(lParam uintptr) {
	var size uint32
	hdrSize := unsafe.Sizeof(rawInputHeader{})
	r, _, _ := procGetRawInputData.Call(lParam, ridInput, 0, uintptr(unsafe.Pointer(&size)), hdrSize)
	if int32(r) == -1 || size == 0 || size > 1024 {
		return
	}
	buf := make([]byte, size)
	r, _, _ = procGetRawInputData.Call(lParam, ridInput, uintptr(unsafe.Pointer(&buf[0])), uintptr(unsafe.Pointer(&size)), hdrSize)
	if r == 0 || int32(r) == -1 {
		return
	}

	hdr := (*rawInputHeader)(unsafe.Pointer(&buf[0]))
	switch hdr.Type {
	case rimTypeMouse:
		if len(buf) < int(hdrSize+unsafe.Sizeof(rawMouse{})) {
			return
		}
		rm := (*rawMouse)(unsafe.Pointer(&buf[hdrSize]))
		c.processWindowsMouse(rm)
	case rimTypeKeyboard:
		if len(buf) < int(hdrSize+unsafe.Sizeof(rawKeyboard{})) {
			return
		}
		rk := (*rawKeyboard)(unsafe.Pointer(&buf[hdrSize]))
		c.processWindowsKeyboard(rk)
	}
}

func (c *windowsCapturer) processWindowsMouse(rm *rawMouse) {
	c.mu.Lock()
	active := c.grabbed
	var dx, dy, wx, wy int16
	if (rm.Flags & 0x01) == 0 {
		dx = int16(rm.LastX)
		dy = int16(rm.LastY)
	}
	bf := rm.ButtonFlags
	if bf&riMouseWheel != 0 {
		wy = int16(rm.ButtonData)
	}
	if bf&riMouseHWheel != 0 {
		wx = int16(rm.ButtonData)
	}

	var changed uint8
	applyBtn := func(downMask, upMask uint16, bit uint8) {
		if bf&downMask != 0 {
			if c.mouseBtns&bit == 0 {
				changed |= bit
			}
			c.mouseBtns |= bit
		}
		if bf&upMask != 0 {
			if c.mouseBtns&bit != 0 {
				changed |= bit
			}
			c.mouseBtns &^= bit
		}
	}
	applyBtn(riMouseLeftDown, riMouseLeftUp, protocol.MouseButtonLeft)
	applyBtn(riMouseRightDown, riMouseRightUp, protocol.MouseButtonRight)
	applyBtn(riMouseMiddleDown, riMouseMiddleUp, protocol.MouseButtonMiddle)
	applyBtn(riMouseBtn4Down, riMouseBtn4Up, protocol.MouseButtonX1)
	applyBtn(riMouseBtn5Down, riMouseBtn5Up, protocol.MouseButtonX2)
	btns := c.mouseBtns
	c.mu.Unlock()

	if !active || c.opts.OnEvent == nil {
		return
	}
	if changed != 0 {
		c.opts.OnEvent(Event{
			Kind:    EventMouseButton,
			Buttons: protocol.MouseButton{Buttons: btns, ChangedMask: changed},
		})
	}
	if dx != 0 || dy != 0 || wx != 0 || wy != 0 {
		c.opts.OnEvent(Event{
			Kind:  EventMouseMotion,
			Mouse: protocol.MouseMotion{DX: dx, DY: dy, WheelX: wx, WheelY: wy, Buttons: btns},
		})
	}
}

func (c *windowsCapturer) processWindowsKeyboard(rk *rawKeyboard) {
	hid := protocol.WindowsScancodeToHID(rk.MakeCode, (rk.Flags&riKeyE0) != 0)
	if hid == 0 {
		return
	}
	pressed := (rk.Flags & riKeyBreak) == 0
	var toggle bool

	c.mu.Lock()
	if pressed {
		if !slices.Contains(c.held, hid) {
			c.held = append(c.held, hid)
		}
		if hid == protocol.HIDKeyG &&
			(slices.Contains(c.held, protocol.HIDLeftCtrl) || slices.Contains(c.held, protocol.HIDRightCtrl)) &&
			(slices.Contains(c.held, protocol.HIDLeftAlt) || slices.Contains(c.held, protocol.HIDRightAlt)) {
			toggle = true
		}
	} else {
		c.held = slices.DeleteFunc(c.held, func(u uint16) bool { return u == hid })
	}
	active := c.grabbed
	heldCopy := slices.Clone(c.held)
	c.mu.Unlock()

	if toggle && pressed {
		c.mu.Lock()
		c.grabbed = !c.grabbed
		next := c.grabbed
		if !next {
			c.held = nil
			c.mouseBtns = 0
		}
		c.mu.Unlock()
		if c.opts.OnEvent != nil {
			c.opts.OnEvent(Event{Kind: EventCaptureToggled, Grabbed: next})
		}
		return
	}

	if active && c.opts.OnEvent != nil {
		c.opts.OnEvent(Event{
			Kind: EventKey,
			Key:  protocol.KeyEvent{HIDUsage: hid, Pressed: pressed, Held: heldCopy},
		})
	}
}

func (c *windowsCapturer) pollXInput(ctx context.Context) {
	ticker := time.NewTicker(4 * time.Millisecond)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			for slot := uint32(0); slot < 4; slot++ {
				var st xinputState
				res, _, _ := procXInputGetState.Call(uintptr(slot), uintptr(unsafe.Pointer(&st)))
				var next protocol.GamepadState
				next.Slot = uint8(slot)
				if res == 0 {
					next.Connected = true
					next.Buttons = st.Gamepad.Buttons
					next.LeftTrigger = st.Gamepad.LeftTrigger
					next.RightTrigger = st.Gamepad.RightTrigger
					next.LX = st.Gamepad.ThumbLX
					next.LY = st.Gamepad.ThumbLY
					next.RX = st.Gamepad.ThumbRX
					next.RY = st.Gamepad.ThumbRY
				}
				c.mu.Lock()
				prev := c.lastPads[slot]
				changed := next != prev
				if changed {
					c.lastPads[slot] = next
				}
				c.mu.Unlock()
				if changed && c.opts.OnEvent != nil {
					c.opts.OnEvent(Event{Kind: EventGamepad, Gamepad: next})
				}
			}
		}
	}
}
