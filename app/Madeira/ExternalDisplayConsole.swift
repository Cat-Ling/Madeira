import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// MARK: - Pure external display rules (Foundation only; compiled by tests/host/check-external-display.py)

enum ExternalAspectRatio: String, CaseIterable, Identifiable {
    case auto
    case ratio16x9 = "16:9"
    case ratio16x10 = "16:10"
    case ratio4x3 = "4:3"
    case ratio21x9 = "21:9"
    case ratio32x9 = "32:9"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto:       return "Auto"
        case .ratio16x9:  return "16:9"
        case .ratio16x10: return "16:10"
        case .ratio4x3:   return "4:3"
        case .ratio21x9:  return "21:9"
        case .ratio32x9:  return "32:9"
        }
    }

    var ratio: CGFloat? {
        switch self {
        case .auto:       return nil
        case .ratio16x9:  return 16.0 / 9.0
        case .ratio16x10: return 16.0 / 10.0
        case .ratio4x3:   return 4.0 / 3.0
        case .ratio21x9:  return 21.0 / 9.0
        case .ratio32x9:  return 32.0 / 9.0
        }
    }
}

enum ExternalResolutionPreset: String, CaseIterable, Identifiable {
    case auto
    case gameDefault
    case hd720
    case hd900
    case fhd1080
    case qhd1440
    case ultrawide1080
    case classic4x3

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto:          return "Auto (match TV)"
        case .gameDefault:   return "Game's resolution"
        case .hd720:         return "720p · 1280×720"
        case .hd900:         return "900p · 1600×900"
        case .fhd1080:       return "1080p · 1920×1080"
        case .qhd1440:       return "1440p · 2560×1440"
        case .ultrawide1080: return "21:9 · 2560×1080"
        case .classic4x3:    return "4:3 · 1024×768"
        }
    }

    var shortLabel: String {
        switch self {
        case .auto:          return "Auto"
        case .gameDefault:   return "Game"
        case .hd720:         return "720p"
        case .hd900:         return "900p"
        case .fhd1080:       return "1080p"
        case .qhd1440:       return "1440p"
        case .ultrawide1080: return "21:9"
        case .classic4x3:    return "4:3"
        }
    }

    func resolve(externalPixels: CGSize, gameResolution: String) -> String {
        switch self {
        case .gameDefault:   return gameResolution
        case .hd720:         return "1280x720"
        case .hd900:         return "1600x900"
        case .fhd1080:       return "1920x1080"
        case .qhd1440:       return "2560x1440"
        case .ultrawide1080: return "2560x1080"
        case .classic4x3:    return "1024x768"
        case .auto:
            let w = max(externalPixels.width, externalPixels.height)
            let h = min(externalPixels.width, externalPixels.height)
            guard w > 0, h > 0 else { return "1920x1080" }
            let aspect = w / h
            if aspect >= 2.15 {
                return w >= 2560 ? "2560x1080" : "1680x720"
            }
            if aspect <= 1.45 {
                return h >= 1080 ? "1440x1080" : "1024x768"
            }
            if abs(aspect - 1.6) <= 0.08 {
                return h >= 1200 ? "1920x1200" : "1280x800"
            }
            return h >= 1080 ? "1920x1080" : "1280x720"
        }
    }
}

enum ExternalDisplayLayout {
    static func safeBounds(for bounds: CGRect, overscanPercent: Double) -> CGRect {
        let clamped = min(max(overscanPercent, 0), 10)
        guard clamped > 0, bounds.width > 1, bounds.height > 1 else { return bounds }
        let dx = min(bounds.width * CGFloat(clamped) / 100.0, (bounds.width - 1) / 2.0)
        let dy = min(bounds.height * CGFloat(clamped) / 100.0, (bounds.height - 1) / 2.0)
        return bounds.insetBy(dx: dx, dy: dy)
    }

    static func rect(guest: CGSize, aspect: CGSize = .zero, bounds: CGRect, mode: DisplayMode,
                     aspectOverride: ExternalAspectRatio = .auto, overscanPercent: Double = 0) -> CGRect {
        let safe = safeBounds(for: bounds, overscanPercent: overscanPercent)
        guard safe.width > 0, safe.height > 0 else { return safe }
        if mode == .stretch { return safe }
        if let forced = aspectOverride.ratio {
            let sx = safe.width / forced
            let sy = safe.height / 1.0
            let scale = mode == .fill ? max(sx, sy) : min(sx, sy)
            let w = forced * scale
            let h = 1.0 * scale
            return CGRect(x: safe.minX + (safe.width - w) / 2.0,
                          y: safe.minY + (safe.height - h) / 2.0,
                          width: w, height: h)
        }
        return GameSurfaceLayout.rect(guest: guest, aspect: aspect, bounds: safe, mode: mode)
    }
}

enum ExternalConsoleTab: String, CaseIterable, Identifiable {
    case games
    case display
    case input
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .games:    return "Games"
        case .display:  return "Display & TV"
        case .input:    return "Controls"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .games:    return "square.grid.2x2.fill"
        case .display:  return "tv"
        case .input:    return "gamecontroller.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

enum ExternalPhoneMode: String, CaseIterable, Identifiable {
    case companion
    case touchpad
    case touchControls

    var id: String { rawValue }

    var label: String {
        switch self {
        case .companion:     return "Companion Deck"
        case .touchpad:      return "Phone Touchpad"
        case .touchControls: return "Touch Controls"
        }
    }

    var symbol: String {
        switch self {
        case .companion:     return "rectangle.grid.2x2"
        case .touchpad:      return "hand.point.up.left"
        case .touchControls: return "gamecontroller"
        }
    }
}

struct RemoteAccessorySnapshot: Equatable {
    var connected: Bool = false
    var hostName: String = ""
    var latencyMs: Int?
    var gamepads: Int = 0
    var keyboard: Bool = false
    var mouse: Bool = false
}

enum ExternalConsoleNavigation {
    static func stepIndex(_ current: Int, delta: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let mod = (current + delta) % count
        return mod >= 0 ? mod : mod + count
    }

    static func hitTest(point: CGPoint, targets: [(id: String, frame: CGRect)]) -> String? {
        for item in targets.reversed() {
            if item.frame.contains(point) { return item.id }
        }
        return nil
    }
}

#if canImport(UIKit)
import SwiftUI
import UIKit
import GameController
import Combine

// MARK: - External display manager

/// Manages the dedicated external display window (AirPlay or wired HDMI/USB-C),
/// switching between the 10-foot Gaming Console home and pure game presentation
/// while keeping performance telemetry and quick settings on the iPhone/iPad.
@MainActor
final class ExternalDisplay: ObservableObject {
    static let shared = ExternalDisplay()
    static let enabled = MadeiraConfig.flag("MADEIRA_EXTERNAL_DISPLAY")

    static var displayShared: Bool {
        UIScreen.screens.count > 1
            || UIScreen.main.isCaptured
            || UIScreen.screens.contains { $0.mirrored != nil }
    }

    private struct ThreadSafeState {
        var active: Bool = false
        var matchRefreshRate: Bool = true
        var screenMaxFPS: Int = 60
        var sessionRunning: Bool = false
        var preset: ExternalResolutionPreset = .auto
        var nativeSize: CGSize = .zero
    }
    private nonisolated static let stateLock = NSLock()
    private nonisolated(unsafe) static var sharedState = ThreadSafeState()

    nonisolated static var currentActiveMaxFPS: Int? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard sharedState.active, sharedState.matchRefreshRate, sharedState.sessionRunning else { return nil }
        return max(sharedState.screenMaxFPS, 1)
    }

    nonisolated static func resolveExternalLaunchResolution(gameResolution: String?) -> String? {
        stateLock.lock()
        let snap = sharedState
        stateLock.unlock()
        guard snap.active else { return nil }
        let isDesktop = getenv("MADEIRA_DESKTOP").map { String(cString: $0) == "1" } ?? false
        guard !isDesktop else { return nil }
        return snap.preset.resolve(externalPixels: snap.nativeSize, gameResolution: gameResolution ?? "1280x720")
    }

    private enum Keys {
        static let enabled = "madeiraExternalDisplayEnabled"
        static let resPreset = "madeiraExtResPreset"
        static let aspect = "madeiraExtAspect"
        static let displayMode = "madeiraExtDisplayMode"
        static let overscan = "madeiraExtOverscan"
        static let matchRefresh = "madeiraExtMatchRefresh"
        static let tvCornerFPS = "madeiraExtShowTVFPS"
    }

    @Published private(set) var isConnected = false
    @Published private(set) var isActive = false
    @Published private(set) var screenBounds: CGRect = .zero
    @Published private(set) var screenNativeSize: CGSize = .zero
    @Published private(set) var screenMaxFPS: Int = 60
    @Published private(set) var remoteAccessories = RemoteAccessorySnapshot()
    @Published var showOverscanGuides = false
    @Published var phoneMode: ExternalPhoneMode = .companion {
        didSet {
            if oldValue != phoneMode { syncPhoneControlMode() }
        }
    }

    @Published var userEnabled: Bool {
        didSet {
            UserDefaults.standard.set(userEnabled, forKey: Keys.enabled)
            if oldValue != userEnabled { update() }
        }
    }
    @Published var resolutionPreset: ExternalResolutionPreset {
        didSet {
            UserDefaults.standard.set(resolutionPreset.rawValue, forKey: Keys.resPreset)
            publishThreadSafeState()
        }
    }
    @Published var aspectOverride: ExternalAspectRatio {
        didSet {
            UserDefaults.standard.set(aspectOverride.rawValue, forKey: Keys.aspect)
            MetalBackedView.refreshDisplayMode(reason: "ext-aspect")
        }
    }
    @Published var displayMode: DisplayMode {
        didSet {
            UserDefaults.standard.set(displayMode.rawValue, forKey: Keys.displayMode)
            MetalBackedView.refreshDisplayMode(reason: "ext-mode")
        }
    }
    @Published var overscanPercent: Double {
        didSet {
            let clamped = min(max(overscanPercent, 0), 10)
            if clamped != overscanPercent { overscanPercent = clamped; return }
            UserDefaults.standard.set(clamped, forKey: Keys.overscan)
            MetalBackedView.refreshDisplayMode(reason: "ext-overscan")
        }
    }
    @Published var matchRefreshRate: Bool {
        didSet {
            UserDefaults.standard.set(matchRefreshRate, forKey: Keys.matchRefresh)
            publishThreadSafeState()
            if LibraryModel.shared.current != nil {
                let mode = ProMotionIntent.supportedMode(LibraryModel.shared.fpsMode)
                ProMotionIntent.apply(mode: mode)
            }
        }
    }
    @Published var showTVCornerFPS: Bool {
        didSet { UserDefaults.standard.set(showTVCornerFPS, forKey: Keys.tvCornerFPS) }
    }

    var onPlay: ((LibraryEntry) -> Void)?
    var onEnableJIT: (() -> Void)?

    private(set) var window: UIWindow?
    private var gameHostContainer: UIView?
    private var hostingController: UIHostingController<ExternalDisplayRootView>?
    private var started = false
    private var retryWork: DispatchWorkItem?
    private var overscanGuideHideWork: DispatchWorkItem?
    private var sessionCancellable: AnyCancellable?

    private init() {
        let d = UserDefaults.standard
        userEnabled = d.object(forKey: Keys.enabled) == nil ? true : d.bool(forKey: Keys.enabled)
        resolutionPreset = d.string(forKey: Keys.resPreset).flatMap(ExternalResolutionPreset.init(rawValue:)) ?? .auto
        aspectOverride = d.string(forKey: Keys.aspect).flatMap(ExternalAspectRatio.init(rawValue:)) ?? .auto
        displayMode = d.string(forKey: Keys.displayMode).flatMap(DisplayMode.init(rawValue:)) ?? .fit
        overscanPercent = min(max(d.object(forKey: Keys.overscan) == nil ? 0 : d.double(forKey: Keys.overscan), 0), 10)
        matchRefreshRate = d.object(forKey: Keys.matchRefresh) == nil ? true : d.bool(forKey: Keys.matchRefresh)
        showTVCornerFPS = d.bool(forKey: Keys.tvCornerFPS)
    }

    var activeDisplayMaxFPS: Int? {
        guard isActive, matchRefreshRate, LibraryModel.shared.current != nil else { return nil }
        return max(screenMaxFPS, 1)
    }

    /// True while a gamepad/KBM user owns the external TV Console (library home or in-game TV pause menu).
    var consoleOwnsInput: Bool {
        guard isActive else { return false }
        let library = LibraryModel.shared
        return library.current == nil || library.menu
    }

    /// True while gameplay is actively displayed on the TV (not paused).
    var isGameplayOnExternal: Bool {
        isActive && LibraryModel.shared.current != nil && !LibraryModel.shared.menu && !LibraryModel.shared.startingScreen
    }

    /// True when phone touches belong to ExternalPhoneCompanionView rather than TouchControls or MetalBackedView.
    var companionOwnsPhoneTouches: Bool {
        isActive && LibraryModel.shared.current != nil && !HardwareInput.desktopMode && phoneMode == .companion
    }

    private func publishThreadSafeState() {
        let sessionRunning = LibraryModel.shared.current != nil
        Self.stateLock.lock()
        Self.sharedState = ThreadSafeState(
            active: isActive,
            matchRefreshRate: matchRefreshRate,
            screenMaxFPS: screenMaxFPS,
            sessionRunning: sessionRunning,
            preset: resolutionPreset,
            nativeSize: screenNativeSize
        )
        Self.stateLock.unlock()
    }

    func start() {
        guard !started else { return }
        started = true
        let nc = NotificationCenter.default
        for name in [UIScreen.didConnectNotification,
                     UIScreen.didDisconnectNotification,
                     UIScreen.modeDidChangeNotification,
                     UIScene.willConnectNotification,
                     UIScene.didActivateNotification,
                     UIScene.didDisconnectNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.update() }
            }
        }
        GuestDisplay.externalResolutionOverride = { gameResolution in
            ExternalDisplay.resolveExternalLaunchResolution(gameResolution: gameResolution)
        }
        sessionCancellable = LibraryModel.shared.$current.sink { [weak self] newValue in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if newValue == nil { self.phoneMode = .companion }
                self.publishThreadSafeState()
                self.syncPhoneControlMode()
                self.syncControllerOwnership()
                MetalBackedView.refreshDisplayMode(reason: "ext-session-change")
            }
        }
        ExternalConsoleController.shared.bind()
        update()
    }

    func updateRemoteAccessories(_ snapshot: RemoteAccessorySnapshot) {
        if remoteAccessories != snapshot {
            remoteAccessories = snapshot
        }
    }

    func effectiveLaunchResolution(gameResolution: String) -> String {
        resolutionPreset.resolve(externalPixels: screenNativeSize, gameResolution: gameResolution)
    }

    func previewOverscanGuides() {
        showOverscanGuides = true
        overscanGuideHideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.showOverscanGuides = false
            }
        }
        overscanGuideHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }

    private func syncPhoneControlMode() {
        let controls = TouchControlsModel.shared
        guard isActive, LibraryModel.shared.current != nil else { return }
        if phoneMode == .touchControls {
            if !controls.visible { controls.visible = true }
        } else if controls.visible {
            controls.visible = false
        }
    }

    private func syncControllerOwnership() {
        let library = LibraryModel.shared
        let owns = library.enabled && (library.current == nil || library.menu)
        LibraryController.shared.configure(enabled: library.enabled, ownsInput: owns)
        HardwareInput.shared.syncConsoleRouting(isActive: isActive, consoleOwnsInput: consoleOwnsInput)
    }

    private func externalScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.session.role == .windowExternalDisplayNonInteractive || $0.screen !== UIScreen.main }
    }

    func update(retryCount: Int = 0) {
        retryWork?.cancel()
        let hasExtraScreen = UIScreen.screens.count > 1 || externalScene() != nil
        if isConnected != hasExtraScreen { isConnected = hasExtraScreen }

        let scene = Self.enabled && userEnabled ? externalScene() : nil
        if let scene {
            let screen = scene.screen
            let bounds = scene.coordinateSpace.bounds
            let native = screen.nativeBounds.size
            let fps = max(1, screen.maximumFramesPerSecond)
            if bounds != screenBounds { screenBounds = bounds }
            if native != screenNativeSize { screenNativeSize = native }
            if fps != screenMaxFPS { screenMaxFPS = fps }

            if window?.windowScene !== scene {
                teardownWindow(reason: "rebind")
                let w = UIWindow(windowScene: scene)
                w.backgroundColor = .black
                w.overrideUserInterfaceStyle = .dark

                let rootVC = UIViewController()
                rootVC.view.backgroundColor = .black

                let gameContainer = UIView(frame: rootVC.view.bounds)
                gameContainer.backgroundColor = .black
                gameContainer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                rootVC.view.addSubview(gameContainer)

                let hostVC = UIHostingController(rootView: ExternalDisplayRootView())
                hostVC.view.backgroundColor = .clear
                hostVC.view.frame = rootVC.view.bounds
                hostVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                rootVC.addChild(hostVC)
                rootVC.view.addSubview(hostVC.view)
                hostVC.didMove(toParent: rootVC)

                w.rootViewController = rootVC
                w.isHidden = false

                self.window = w
                self.gameHostContainer = gameContainer
                self.hostingController = hostVC
                self.isActive = true
                ExternalConsoleController.shared.resetCursor(in: bounds.size)
                fputs("[display] external console on: \(Int(bounds.width))x\(Int(bounds.height)) native=\(Int(native.width))x\(Int(native.height)) @\(fps)Hz\n", stderr)
                LogStore.shared.log("[display] external console on: \(Int(bounds.width))x\(Int(bounds.height)) (native \(Int(native.width))x\(Int(native.height))) @\(fps)Hz")
            } else if !isActive {
                isActive = true
            }
            publishThreadSafeState()
            if LibraryModel.shared.current != nil && matchRefreshRate {
                ProMotionIntent.apply(mode: ProMotionIntent.supportedMode(LibraryModel.shared.fpsMode))
            }
            syncControllerOwnership()
            MetalBackedView.refreshDisplayMode(reason: "external-display")
        } else {
            teardownWindow(reason: hasExtraScreen ? "disabled" : "disconnected")
            // AirPlay/wired UIScreen notifications sometimes arrive a moment before UIWindowScene connects (MeloNX pattern).
            if Self.enabled && userEnabled && hasExtraScreen && retryCount < 4 {
                let work = DispatchWorkItem { [weak self] in
                    MainActor.assumeIsolated {
                        self?.update(retryCount: retryCount + 1)
                    }
                }
                retryWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
            }
        }
    }

    private func teardownWindow(reason: String) {
        guard let old = window else {
            if isActive { isActive = false }
            publishThreadSafeState()
            syncControllerOwnership()
            return
        }
        isActive = false
        window = nil
        gameHostContainer = nil
        hostingController = nil
        publishThreadSafeState()
        MetalBackedView.refreshDisplayMode(reason: "external-\(reason)")
        if MetalHostView.shared.superview === old || MetalHostView.shared.window === old {
            MetalHostView.shared.removeFromSuperview()
        }
        old.isHidden = true
        if LibraryModel.shared.current != nil {
            ProMotionIntent.apply(mode: ProMotionIntent.supportedMode(LibraryModel.shared.fpsMode))
        }
        syncControllerOwnership()
        fputs("[display] external console off (\(reason))\n", stderr)
    }

    func mountGameLayer(_ host: MetalHostView, rect: CGRect) {
        guard let targetView = gameHostContainer ?? window else { return }
        if host.superview !== targetView {
            host.removeFromSuperview()
            targetView.addSubview(host)
            let fpsSel = NSSelectorFromString("setNominalFramesPerSecond:")
            if host.metalLayer.responds(to: fpsSel) {
                host.metalLayer.perform(fpsSel, with: screenMaxFPS as NSNumber)
            }
        }
        host.frame = rect
    }
}

// MARK: - Unified TV Console Controller (Gamepad + Keyboard + Mouse)

private struct ConsoleHitTargetsKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private extension View {
    func consoleHitTarget(_ id: String) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: ConsoleHitTargetsKey.self, value: [id: proxy.frame(in: .named("tvConsole"))])
            }
        )
    }
}

@MainActor
final class ExternalConsoleController: ObservableObject {
    static let shared = ExternalConsoleController()

    enum InputKind { case gamepad, kbm, remoteLAN }

    @Published var tab: ExternalConsoleTab = .games
    @Published var filter: String = "all"
    @Published var focusedGameIndex: Int = 0
    @Published var focusedRowIndex: Int = 0
    @Published var gameOptionsOpen: Bool = false
    @Published var gameOptionsRow: Int = 0
    @Published var pauseMenuIndex: Int = 0
    @Published var ecoEnabled: Bool = false

    @Published var cursorPosition: CGPoint = CGPoint(x: 640, y: 360)
    @Published var cursorVisible: Bool = false
    @Published var hoveredTargetID: String?
    @Published var lastInputKind: InputKind = .gamepad

    private var hitTargets: [String: CGRect] = [:]
    private var orderedTargets: [(id: String, frame: CGRect)] = []
    private var cursorHideWork: DispatchWorkItem?
    private var commandCancellable: AnyCancellable?

    static let filters: [(id: String, title: String)] = [
        ("all", "All"),
        ("installed", "Games"),
        ("steam", "Steam"),
        ("desktop", "Desktop"),
    ]

    private init() {}

    func bind() {
        ecoEnabled = madeira_get_eco() != 0
        guard commandCancellable == nil else { return }
        commandCancellable = LibraryController.shared.commands
            .receive(on: DispatchQueue.main)
            .sink { [weak self] command in
                guard let self, ExternalDisplay.shared.consoleOwnsInput else { return }
                self.handleGamepad(command)
            }
    }

    func resetCursor(in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        cursorPosition = CGPoint(x: size.width / 2, y: size.height / 2)
        hoveredTargetID = nil
        cursorVisible = false
    }

    func updateHitTargets(_ targets: [String: CGRect]) {
        hitTargets = targets
        orderedTargets = targets.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        if cursorVisible {
            hoveredTargetID = ExternalConsoleNavigation.hitTest(point: cursorPosition, targets: orderedTargets)
        }
    }

    func visibleGames() -> [LibraryEntry] {
        let model = LibraryModel.shared
        let local = model.entries.filter { $0.desktop != true && $0.listedInLibrary }
        let existingSteamIDs = Set(local.compactMap(\.steamAppID))
        var steamDockEntries: [LibraryEntry] = []
        if MadeiraDock.enabled {
            for game in MadeiraDock.games(drive: MadeiraDock.drive) where game.installed && !existingSteamIDs.contains(game.id) {
                steamDockEntries.append(model.steamEntry(game, title: game.name))
            }
        }
        let sortedGames = (local + steamDockEntries).sorted { a, b in
            if a.lastPlayed != b.lastPlayed {
                return (a.lastPlayed ?? .distantPast) > (b.lastPlayed ?? .distantPast)
            }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
        let desktop = model.entries.first(where: { $0.desktop == true }) ?? .desktopEntry
        switch filter {
        case "installed":
            return sortedGames.filter { $0.steamAppID == nil }
        case "steam":
            return sortedGames.filter { $0.steamAppID != nil }
        case "desktop":
            return [desktop]
        default:
            return sortedGames + [desktop]
        }
    }

    func focusedGame(in games: [LibraryEntry]) -> LibraryEntry? {
        guard !games.isEmpty else { return nil }
        let idx = min(max(focusedGameIndex, 0), games.count - 1)
        return games[idx]
    }

    private func showCursorBriefly() {
        cursorVisible = true
        cursorHideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.cursorVisible = false
            }
        }
        cursorHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: work)
    }

    func moveCursor(dx: Double, dy: Double) {
        guard ExternalDisplay.shared.consoleOwnsInput else { return }
        lastInputKind = .kbm
        let bounds = ExternalDisplay.shared.screenBounds.size
        guard bounds.width > 0, bounds.height > 0 else { return }
        let speed = max(0.5, min(2.5, InputSettings.shared.sensMouse))
        let nx = min(max(cursorPosition.x + CGFloat(dx * speed), 0), bounds.width)
        let ny = min(max(cursorPosition.y + CGFloat(dy * speed), 0), bounds.height)
        cursorPosition = CGPoint(x: nx, y: ny)
        hoveredTargetID = ExternalConsoleNavigation.hitTest(point: cursorPosition, targets: orderedTargets)
        showCursorBriefly()
    }

    func handleMouseButton(_ button: MouseButton, pressed: Bool) {
        guard ExternalDisplay.shared.consoleOwnsInput, pressed else { return }
        lastInputKind = .kbm
        showCursorBriefly()
        if button == .right {
            handleAction("back")
            return
        }
        guard button == .left else { return }
        guard let target = hoveredTargetID ?? ExternalConsoleNavigation.hitTest(point: cursorPosition, targets: orderedTargets) else {
            return
        }
        activate(targetID: target)
    }

    func handleMouseScroll(dx: Double, dy: Double) {
        guard ExternalDisplay.shared.consoleOwnsInput else { return }
        lastInputKind = .kbm
        if abs(dx) > abs(dy) && abs(dx) > 0.25 {
            handleAction(dx > 0 ? "right" : "left")
        } else if abs(dy) > 0.25 {
            handleAction(dy < 0 ? "down" : "up")
        }
    }

    @discardableResult
    func handleKey(vk: Int32) -> Bool {
        if ExternalDisplay.shared.isGameplayOnExternal && vk == 0x79 { // F10 toggles TV Pause Menu
            LibraryModel.shared.showMenu()
            return true
        }
        guard ExternalDisplay.shared.consoleOwnsInput else { return false }
        lastInputKind = .kbm
        switch vk {
        case 0x26, 0x57: handleAction("up"); return true       // Up / W
        case 0x28, 0x53: handleAction("down"); return true     // Down / S
        case 0x25, 0x41: handleAction("left"); return true     // Left / A
        case 0x27, 0x44: handleAction("right"); return true    // Right / D
        case 0x0D, 0x20: handleAction("accept"); return true   // Return / Space
        case 0x1B, 0x08: handleAction("back"); return true     // Esc / Backspace
        case 0x09, 0x45: handleAction("tab"); return true      // Tab / E
        case 0x51:       handleAction("prevTab"); return true  // Q
        case 0x58, 0x4F:                                       // X / O -> Per-game setup
            if LibraryModel.shared.current == nil && tab == .games {
                gameOptionsOpen.toggle()
                gameOptionsRow = 0
                return true
            }
            return false
        case 0x46: handleAction("add"); return true            // F -> Cycle filter
        default: return false
        }
    }

    func handleGamepad(_ command: String) {
        lastInputKind = .gamepad
        cursorVisible = false
        handleAction(command)
    }

    func handleAction(_ command: String) {
        let model = LibraryModel.shared
        // 1. In-game TV Pause Menu
        if model.current != nil {
            if model.menu {
                switch command {
                case "up":     pauseMenuIndex = ExternalConsoleNavigation.stepIndex(pauseMenuIndex, delta: -1, count: 9)
                case "down":   pauseMenuIndex = ExternalConsoleNavigation.stepIndex(pauseMenuIndex, delta: 1, count: 9)
                case "left":   adjustPauseRow(pauseMenuIndex, delta: -1)
                case "right":  adjustPauseRow(pauseMenuIndex, delta: 1)
                case "accept": activatePauseRow(pauseMenuIndex)
                case "back", "menu": model.menu = false
                default: break
                }
            }
            return
        }

        // 2. Per-game setup modal inside Console Home
        if gameOptionsOpen {
            switch command {
            case "up":     gameOptionsRow = ExternalConsoleNavigation.stepIndex(gameOptionsRow, delta: -1, count: 6)
            case "down":   gameOptionsRow = ExternalConsoleNavigation.stepIndex(gameOptionsRow, delta: 1, count: 6)
            case "left":   adjustGameOptionRow(gameOptionsRow, delta: -1)
            case "right":  adjustGameOptionRow(gameOptionsRow, delta: 1)
            case "accept": activateGameOptionRow(gameOptionsRow)
            case "back":   gameOptionsOpen = false
            default: break
            }
            return
        }

        // 3. Console Home tabs
        let allTabs = ExternalConsoleTab.allCases
        let currentTabIdx = allTabs.firstIndex(of: tab) ?? 0
        switch command {
        case "tab":
            tab = allTabs[ExternalConsoleNavigation.stepIndex(currentTabIdx, delta: 1, count: allTabs.count)]
            focusedRowIndex = 0
        case "prevTab":
            tab = allTabs[ExternalConsoleNavigation.stepIndex(currentTabIdx, delta: -1, count: allTabs.count)]
            focusedRowIndex = 0
        case "add":
            if tab == .games {
                let ids = Self.filters.map(\.id)
                let idx = ids.firstIndex(of: filter) ?? 0
                filter = ids[ExternalConsoleNavigation.stepIndex(idx, delta: 1, count: ids.count)]
                focusedGameIndex = 0
            }
        case "left":
            if tab == .games {
                let games = visibleGames()
                focusedGameIndex = ExternalConsoleNavigation.stepIndex(focusedGameIndex, delta: -1, count: games.count)
            } else {
                adjustSettingsRow(focusedRowIndex, delta: -1)
            }
        case "right":
            if tab == .games {
                let games = visibleGames()
                focusedGameIndex = ExternalConsoleNavigation.stepIndex(focusedGameIndex, delta: 1, count: games.count)
            } else {
                adjustSettingsRow(focusedRowIndex, delta: 1)
            }
        case "up":
            if tab != .games {
                focusedRowIndex = ExternalConsoleNavigation.stepIndex(focusedRowIndex, delta: -1, count: rowCount(for: tab))
            }
        case "down":
            if tab == .games {
                gameOptionsOpen = true
                gameOptionsRow = 0
            } else {
                focusedRowIndex = ExternalConsoleNavigation.stepIndex(focusedRowIndex, delta: 1, count: rowCount(for: tab))
            }
        case "accept":
            if tab == .games {
                if let entry = focusedGame(in: visibleGames()) {
                    launchEntry(entry)
                }
            } else {
                adjustSettingsRow(focusedRowIndex, delta: 1)
            }
        default:
            break
        }
    }

    func launchEntry(_ entry: LibraryEntry) {
        gameOptionsOpen = false
        ExternalDisplay.shared.onPlay?(entry)
    }

    private func activate(targetID: String) {
        if targetID.hasPrefix("tab:"), let t = ExternalConsoleTab(rawValue: String(targetID.dropFirst(4))) {
            tab = t; focusedRowIndex = 0; gameOptionsOpen = false
        } else if targetID.hasPrefix("filter:") {
            filter = String(targetID.dropFirst(7)); focusedGameIndex = 0
        } else if targetID.hasPrefix("game:"), let idx = Int(targetID.dropFirst(5)) {
            let games = visibleGames()
            if idx == focusedGameIndex, idx < games.count {
                launchEntry(games[idx])
            } else if idx >= 0 && idx < games.count {
                focusedGameIndex = idx
            }
        } else if targetID == "hero:play" {
            if let entry = focusedGame(in: visibleGames()) { launchEntry(entry) }
        } else if targetID == "hero:setup" {
            gameOptionsOpen.toggle(); gameOptionsRow = 0
        } else if targetID.hasPrefix("row:"), let idx = Int(targetID.dropFirst(4)) {
            focusedRowIndex = idx; adjustSettingsRow(idx, delta: 1)
        } else if targetID.hasPrefix("opt:"), let idx = Int(targetID.dropFirst(4)) {
            gameOptionsRow = idx; activateGameOptionRow(idx)
        } else if targetID == "opt:close" {
            gameOptionsOpen = false
        } else if targetID.hasPrefix("pause:"), let idx = Int(targetID.dropFirst(6)) {
            pauseMenuIndex = idx; activatePauseRow(idx)
        }
    }

    private func rowCount(for tab: ExternalConsoleTab) -> Int {
        switch tab {
        case .games:    return 1
        case .display:  return 6
        case .input:    return 3
        case .settings: return 3
        }
    }

    func adjustSettingsRow(_ row: Int, delta: Int) {
        let ext = ExternalDisplay.shared
        switch tab {
        case .games:
            break
        case .display:
            switch row {
            case 0:
                let all = ExternalResolutionPreset.allCases
                let i = all.firstIndex(of: ext.resolutionPreset) ?? 0
                ext.resolutionPreset = all[ExternalConsoleNavigation.stepIndex(i, delta: delta, count: all.count)]
            case 1:
                let all = ExternalAspectRatio.allCases
                let i = all.firstIndex(of: ext.aspectOverride) ?? 0
                ext.aspectOverride = all[ExternalConsoleNavigation.stepIndex(i, delta: delta, count: all.count)]
            case 2:
                let all = DisplayMode.allCases
                let i = all.firstIndex(of: ext.displayMode) ?? 0
                ext.displayMode = all[ExternalConsoleNavigation.stepIndex(i, delta: delta, count: all.count)]
            case 3:
                ext.overscanPercent = min(max((ext.overscanPercent * 2.0).rounded() / 2.0 + Double(delta) * 0.5, 0), 10)
                ext.previewOverscanGuides()
            case 4:
                ext.matchRefreshRate.toggle()
            case 5:
                ext.showTVCornerFPS.toggle()
            default:
                break
            }
        case .input:
            switch row {
            case 0:
                InputSettings.shared.relative.toggle()
            case 1:
                let next = InputSettings.shared.sensMouse + Double(delta) * 0.25
                InputSettings.shared.sensMouse = min(max((next * 4).rounded() / 4, 0.25), 3.0)
            case 2:
                InputSettings.shared.padRightStickMouse.toggle()
            default:
                break
            }
        case .settings:
            switch row {
            case 0:
                let next = madeira_get_eco() == 0
                madeira_set_eco(next ? 1 : 0)
                ecoEnabled = madeira_get_eco() != 0
            case 1:
                if !StikJITHelper.ready { ext.onEnableJIT?() }
            case 2:
                ext.userEnabled = false
            default:
                break
            }
        }
    }

    func activateGameOptionRow(_ row: Int) {
        if row == 5 {
            if let entry = focusedGame(in: visibleGames()) { launchEntry(entry) }
        } else {
            adjustGameOptionRow(row, delta: 1)
        }
    }

    func adjustGameOptionRow(_ row: Int, delta: Int) {
        let games = visibleGames()
        guard var entry = focusedGame(in: games) else { return }
        switch row {
        case 0:
            let modes = availableFPSModes()
            let i = modes.firstIndex(of: entry.fpsMode) ?? 0
            entry.fpsMode = modes[ExternalConsoleNavigation.stepIndex(i, delta: delta, count: modes.count)]
        case 1:
            let choices = ["", "dinput", "keys"]
            let cur = entry.controllerMode ?? ""
            let i = choices.firstIndex(of: cur) ?? 0
            let next = choices[ExternalConsoleNavigation.stepIndex(i, delta: delta, count: choices.count)]
            entry.controllerMode = next.isEmpty ? nil : next
        case 2:
            entry.x87Precision = ExternalConsoleNavigation.stepEnum(entry.x87Precision, delta: delta)
        case 3:
            entry.performance.toggle()
        case 4:
            let all = ExternalAspectRatio.allCases
            let i = all.firstIndex(of: ExternalDisplay.shared.aspectOverride) ?? 0
            ExternalDisplay.shared.aspectOverride = all[ExternalConsoleNavigation.stepIndex(i, delta: delta, count: all.count)]
            return
        case 5:
            launchEntry(entry)
            return
        default:
            return
        }
        LibraryModel.shared.save(entry)
    }

    func activatePauseRow(_ row: Int) {
        let model = LibraryModel.shared
        switch row {
        case 0: model.menu = false
        case 1...6: adjustPauseRow(row, delta: 1)
        case 7: ExternalDisplay.shared.userEnabled = false
        case 8: model.requestQuit()
        default: break
        }
    }

    func adjustPauseRow(_ row: Int, delta: Int) {
        let ext = ExternalDisplay.shared
        let model = LibraryModel.shared
        switch row {
        case 1:
            let all = DisplayMode.allCases
            let i = all.firstIndex(of: ext.displayMode) ?? 0
            ext.displayMode = all[ExternalConsoleNavigation.stepIndex(i, delta: delta, count: all.count)]
        case 2:
            let all = ExternalAspectRatio.allCases
            let i = all.firstIndex(of: ext.aspectOverride) ?? 0
            ext.aspectOverride = all[ExternalConsoleNavigation.stepIndex(i, delta: delta, count: all.count)]
        case 3:
            ext.overscanPercent = min(max((ext.overscanPercent * 2.0).rounded() / 2.0 + Double(delta) * 0.5, 0), 10)
            ext.previewOverscanGuides()
        case 4:
            let modes = availableFPSModes()
            let i = modes.firstIndex(of: model.fpsMode) ?? 0
            model.setFPS(modes[ExternalConsoleNavigation.stepIndex(i, delta: delta, count: modes.count)])
        case 5:
            let next = madeira_get_eco() == 0
            madeira_set_eco(next ? 1 : 0)
            ecoEnabled = madeira_get_eco() != 0
        case 6:
            model.performance.toggle()
            model.saveCurrentProfile()
        default:
            break
        }
    }

    func availableFPSModes() -> [Int] {
        var modes: [Int] = []
        if ProMotionIntent.has30Cap { modes.append(3) }
        if ProMotionIntent.has40Cap { modes.append(4) }
        modes.append(contentsOf: [1, 0, 2])
        return modes
    }

    func fpsLabel(_ mode: Int) -> String {
        switch mode {
        case 3: return "30 FPS"
        case 4: return "40 FPS"
        case 1: return "60 FPS"
        case 0: return "TV Max"
        case 2: return "Uncapped"
        default: return "\(mode)"
        }
    }
}

private extension ExternalConsoleNavigation {
    static func stepEnum<T: CaseIterable & Equatable>(_ value: T, delta: Int) -> T {
        let all = Array(T.allCases)
        let i = all.firstIndex(of: value) ?? 0
        return all[stepIndex(i, delta: delta, count: all.count)]
    }
}

// MARK: - TV Root View

struct ExternalDisplayRootView: View {
    @ObservedObject private var external = ExternalDisplay.shared
    @ObservedObject private var model = LibraryModel.shared
    @ObservedObject private var console = ExternalConsoleController.shared

    var body: some View {
        ZStack {
            if model.startingScreen, let entry = model.startingEntry {
                ExternalLaunchSplashView(entry: entry)
            } else if model.current != nil {
                // Gameplay: MetalHostView sits directly beneath this transparent root!
                ZStack {
                    Color.clear
                    if external.showOverscanGuides {
                        ExternalOverscanGuideOverlay(percent: external.overscanPercent)
                    }
                    if external.showTVCornerFPS && !model.menu {
                        TVCornerFPSBadge()
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(24)
                    }
                    if model.menu {
                        ExternalInGameMenuView()
                    }
                }
            } else {
                ExternalConsoleHomeView()
            }

            if external.consoleOwnsInput && console.cursorVisible {
                TVPointerView()
                    .position(console.cursorPosition)
                    .allowsHitTesting(false)
            }
        }
        .coordinateSpace(name: "tvConsole")
        .onPreferenceChange(ConsoleHitTargetsKey.self) { targets in
            console.updateHitTargets(targets)
        }
        .preferredColorScheme(.dark)
        .ignoresSafeArea()
    }
}

private struct TVPointerView: View {
    var body: some View {
        Circle()
            .fill(.white.opacity(0.92))
            .frame(width: 18, height: 18)
            .overlay(Circle().stroke(.cyan, lineWidth: 2.5))
            .shadow(color: .black.opacity(0.65), radius: 5, y: 2)
    }
}

private struct TVCornerFPSBadge: View {
    @State private var lastCount = madeira_shown_frame_count()
    @State private var lastDate = Date()
    @State private var fps: Double = 0
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Text("\(Int(fps.rounded())) FPS")
            .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(.white.opacity(0.88))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.black.opacity(0.45), in: Capsule())
            .onReceive(timer) { now in
                let c = madeira_shown_frame_count()
                let dt = now.timeIntervalSince(lastDate)
                let frames = c >= lastCount ? c - lastCount : 0
                fps = Double(frames) / max(0.001, dt)
                lastCount = c
                lastDate = now
            }
    }
}

private struct ExternalOverscanGuideOverlay: View {
    let percent: Double

    var body: some View {
        GeometryReader { geo in
            let safe = ExternalDisplayLayout.safeBounds(for: CGRect(origin: .zero, size: geo.size), overscanPercent: percent)
            ZStack {
                Rectangle()
                    .strokeBorder(Color.cyan.opacity(0.85), style: StrokeStyle(lineWidth: 3, dash: [14, 10]))
                    .frame(width: safe.width, height: safe.height)
                    .position(x: safe.midX, y: safe.midY)

                VStack(spacing: 4) {
                    Text("TV Safe Area")
                        .font(.headline)
                    Text(String(format: "Overscan %.1f%% · %.0f×%.0f pt", percent, safe.width, safe.height))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(.cyan.opacity(0.5), lineWidth: 1))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Console Home View (10-foot UI)

private struct ExternalConsoleHomeView: View {
    @ObservedObject private var external = ExternalDisplay.shared
    @ObservedObject private var model = LibraryModel.shared
    @ObservedObject private var console = ExternalConsoleController.shared
    @ObservedObject private var hardware = HardwareInput.shared
    @ObservedObject private var inputSettings = InputSettings.shared
    @ObservedObject private var jitState = LibraryJITState.shared

    private let bg = Color(red: 0.024, green: 0.027, blue: 0.039)

    var body: some View {
        let games = console.visibleGames()
        let focused = console.focusedGame(in: games)

        ZStack {
            bg.ignoresSafeArea()
            if let focused {
                consoleBackdrop(for: focused)
                    .opacity(0.36)
                    .blur(radius: 18)
                    .ignoresSafeArea()
                LinearGradient(colors: [bg.opacity(0.82), bg.opacity(0.45), bg.opacity(0.95)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 44)
                    .padding(.top, 28)
                    .padding(.bottom, 16)

                Group {
                    switch console.tab {
                    case .games:    gamesTab(games: games, focused: focused)
                    case .display:  displayTab
                    case .input:    inputTab
                    case .settings: settingsTab
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                bottomBar
                    .padding(.horizontal, 44)
                    .padding(.bottom, 22)
                    .padding(.top, 10)
            }

            if console.gameOptionsOpen, let focused {
                ExternalGameOptionsModal(entry: focused)
            }
        }
    }

    @ViewBuilder
    private func consoleBackdrop(for entry: LibraryEntry) -> some View {
        if let appID = entry.steamAppID, entry.coverFile == nil {
            SteamLaunchBackdrop(appID: appID)
        } else {
            LibraryArtwork(entry: entry, backdrop: true)
        }
    }

    private var topBar: some View {
        HStack(spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "play.tv.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.cyan)
                Text("MADEIRA")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .tracking(1.5)
            }

            HStack(spacing: 8) {
                ForEach(ExternalConsoleTab.allCases) { item in
                    let selected = console.tab == item
                    Button {
                        console.tab = item
                        console.focusedRowIndex = 0
                    } label: {
                        Label(item.title, systemImage: item.symbol)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .foregroundStyle(selected ? .black : .white.opacity(0.85))
                            .background(
                                Capsule().fill(selected ? Color.white : Color.white.opacity(0.1))
                            )
                    }
                    .buttonStyle(.plain)
                    .consoleHitTarget("tab:\(item.rawValue)")
                }
            }

            Spacer()

            HStack(spacing: 10) {
                statusBadge(
                    icon: "tv",
                    text: "\(Int(external.screenBounds.width))×\(Int(external.screenBounds.height)) @\(external.screenMaxFPS)Hz",
                    tint: .cyan
                )
                statusBadge(
                    icon: jitState.enabled ? "bolt.fill" : "bolt.slash",
                    text: jitState.enabled ? "JIT On" : "No JIT",
                    tint: jitState.enabled ? .green : .orange
                )
                if !GCController.controllers().isEmpty {
                    Image(systemName: "gamecontroller.fill").foregroundStyle(.green)
                }
                if hardware.keyboardConnected {
                    Image(systemName: "keyboard").foregroundStyle(.white.opacity(0.85))
                }
                if hardware.mouseConnected {
                    Image(systemName: "computermouse").foregroundStyle(.white.opacity(0.85))
                }
                if external.remoteAccessories.connected {
                    Image(systemName: "antenna.radiowaves.left.and.right").foregroundStyle(.cyan)
                }
            }
            .font(.subheadline)
        }
    }

    private func statusBadge(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text).font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.white.opacity(0.08), in: Capsule())
    }

    @ViewBuilder
    private func gamesTab(games: [LibraryEntry], focused: LibraryEntry?) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            if let entry = focused {
                HStack(alignment: .bottom, spacing: 28) {
                    consoleArtwork(for: entry)
                        .frame(width: 170, height: 255)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.18), lineWidth: 1))
                        .shadow(color: .black.opacity(0.65), radius: 24, y: 10)

                    VStack(alignment: .leading, spacing: 12) {
                        Text(entry.title)
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .lineLimit(2)

                        HStack(spacing: 10) {
                            let targetRes = entry.desktop == true ? entry.resolution : external.effectiveLaunchResolution(gameResolution: entry.resolution)
                            metaChip(entry.desktop == true ? "Wine Desktop" : (entry.steamAppID != nil ? "Steam" : "Local"))
                            if entry.bits > 0 { metaChip("\(entry.bits)-bit") }
                            metaChip("TV \(targetRes)")
                            metaChip(console.fpsLabel(entry.fpsMode))
                            metaChip(external.displayMode.label)
                        }

                        HStack(spacing: 14) {
                            Button { console.launchEntry(entry) } label: {
                                Label("Play on TV", systemImage: "play.fill")
                                    .font(.title3.weight(.bold))
                                    .padding(.horizontal, 26)
                                    .padding(.vertical, 13)
                                    .foregroundStyle(.black)
                                    .background(Color.white, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .consoleHitTarget("hero:play")

                            Button {
                                console.gameOptionsOpen = true
                                console.gameOptionsRow = 0
                            } label: {
                                Label("Game Setup", systemImage: "slider.horizontal.3")
                                    .font(.headline)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 13)
                                    .foregroundStyle(.white)
                                    .background(.white.opacity(0.14), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .consoleHitTarget("hero:setup")
                        }
                        .padding(.top, 4)
                    }
                    Spacer()
                }
                .padding(.horizontal, 48)
            } else {
                Spacer()
                ContentUnavailableView("No Games Found", systemImage: "gamecontroller",
                                       description: Text("Add games on your iPhone/iPad library to launch them on the TV."))
                Spacer()
            }

            // Filter row
            HStack(spacing: 10) {
                ForEach(ExternalConsoleController.filters, id: \.id) { f in
                    let on = console.filter == f.id
                    Button {
                        console.filter = f.id
                        console.focusedGameIndex = 0
                    } label: {
                        Text(f.title)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .foregroundStyle(on ? .black : .white.opacity(0.75))
                            .background(Capsule().fill(on ? Color.cyan : Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .consoleHitTarget("filter:\(f.id)")
                }
                Spacer()
                Text("\(games.count) title\(games.count == 1 ? "" : "s")")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 48)

            // Horizontal cover shelf
            ScrollViewReader { reader in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 22) {
                        ForEach(Array(games.enumerated()), id: \.element.id) { index, entry in
                            let isFocused = index == min(max(console.focusedGameIndex, 0), max(0, games.count - 1))
                            Button {
                                if isFocused { console.launchEntry(entry) }
                                else { console.focusedGameIndex = index }
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    consoleArtwork(for: entry)
                                        .frame(width: 148, height: 216)
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .strokeBorder(isFocused ? Color.cyan : Color.white.opacity(0.12),
                                                              lineWidth: isFocused ? 4 : 1)
                                        )
                                        .shadow(color: isFocused ? .cyan.opacity(0.45) : .black.opacity(0.5),
                                                radius: isFocused ? 18 : 8, y: 6)
                                        .scaleEffect(isFocused ? 1.07 : 1.0)
                                        .animation(.easeOut(duration: 0.16), value: isFocused)

                                    Text(entry.title)
                                        .font(.system(size: 14, weight: isFocused ? .bold : .medium, design: .rounded))
                                        .foregroundStyle(isFocused ? .white : .white.opacity(0.72))
                                        .lineLimit(1)
                                        .frame(width: 148, alignment: .leading)
                                }
                            }
                            .buttonStyle(.plain)
                            .id(entry.id)
                            .consoleHitTarget("game:\(index)")
                        }
                    }
                    .padding(.horizontal, 48)
                    .padding(.vertical, 14)
                }
                .onChange(of: console.focusedGameIndex) { _, newIdx in
                    if let target = console.focusedGame(in: games) {
                        withAnimation(.easeOut(duration: 0.22)) {
                            reader.scrollTo(target.id, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private func consoleArtwork(for entry: LibraryEntry) -> some View {
        Group {
            if let appID = entry.steamAppID, entry.coverFile == nil {
                SteamGameArtwork(appID: appID)
            } else {
                LibraryArtwork(entry: entry)
            }
        }
    }

    private func metaChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(.white.opacity(0.12), in: Capsule())
    }

    private var displayTab: some View {
        HStack(spacing: 32) {
            VStack(spacing: 12) {
                consoleSettingRow(index: 0, title: "Target Game Resolution", value: external.resolutionPreset.label)
                consoleSettingRow(index: 1, title: "Aspect Ratio Override", value: external.aspectOverride.label)
                consoleSettingRow(index: 2, title: "Scaling Mode", value: external.displayMode.label)
                consoleSettingRow(index: 3, title: "TV Overscan Safe Margin", value: String(format: "%.1f%%", external.overscanPercent))
                consoleSettingRow(index: 4, title: "Match TV Refresh Rate", value: external.matchRefreshRate ? "On (\(external.screenMaxFPS) Hz)" : "Off")
                consoleSettingRow(index: 5, title: "Corner FPS Counter on TV", value: external.showTVCornerFPS ? "On" : "Off (stats on phone)")
                Spacer()
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 18) {
                Text("Live TV Canvas Preview")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                TVAspectPreviewDiagram()
                    .frame(height: 260)
                VStack(spacing: 6) {
                    Text("Physical Screen: \(Int(external.screenBounds.width))×\(Int(external.screenBounds.height)) pt · Native \(Int(external.screenNativeSize.width))×\(Int(external.screenNativeSize.height)) px @ \(external.screenMaxFPS) Hz")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("Stats overlays remain on your iPhone/iPad Companion Deck during play.")
                        .font(.caption)
                        .foregroundStyle(.cyan.opacity(0.9))
                }
            }
            .padding(28)
            .frame(width: 440)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.12)))
        }
        .padding(.horizontal, 48)
        .padding(.top, 12)
    }

    private var inputTab: some View {
        HStack(spacing: 32) {
            VStack(spacing: 12) {
                consoleSettingRow(index: 0, title: "Relative Mouse Look", value: inputSettings.relative ? "On" : "Auto (Game cursor)")
                consoleSettingRow(index: 1, title: "Hardware Mouse Sensitivity", value: String(format: "%.2fx", inputSettings.sensMouse))
                consoleSettingRow(index: 2, title: "Right Stick Acts as Mouse", value: inputSettings.padRightStickMouse ? "On" : "Off")
                Spacer()
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 14) {
                Text("Connected Accessories")
                    .font(.headline)
                let pads = GCController.controllers()
                if pads.isEmpty && !external.remoteAccessories.connected {
                    Label("No physical controller paired", systemImage: "gamecontroller")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(pads.enumerated()), id: \.offset) { idx, pad in
                        Label("Player \(idx + 1): \(pad.vendorName ?? "Controller")", systemImage: "gamecontroller.fill")
                            .foregroundStyle(.green)
                    }
                }
                Divider().background(.white.opacity(0.15))
                Label(hardware.keyboardConnected ? "Keyboard connected (WASD / Arrows / F10 Menu)" : "No hardware keyboard detected",
                      systemImage: "keyboard")
                    .foregroundStyle(hardware.keyboardConnected ? .white : .secondary)
                Label(hardware.mouseConnected ? "Mouse connected (Free cursor in Console)" : "No hardware mouse detected",
                      systemImage: "computermouse")
                    .foregroundStyle(hardware.mouseConnected ? .white : .secondary)
                if external.remoteAccessories.connected {
                    let remote = external.remoteAccessories
                    Label("AoL (\(remote.hostName)) · \(remote.latencyMs.map { "\($0)ms" } ?? "LAN") · \(remote.gamepads) pad(s)",
                          systemImage: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(.cyan)
                } else {
                    Label("AoL (Accessories Over LAN): Ready (disconnected)",
                          systemImage: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(.secondary)
                }
                Divider().background(.white.opacity(0.15))
                Text("Phone touch input stays isolated on the Companion Deck while you play on the TV. Press Back+Start or F10 in game to open the TV Pause Menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(28)
            .frame(width: 440, alignment: .leading)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.12)))
        }
        .padding(.horizontal, 48)
        .padding(.top, 12)
    }

    private var settingsTab: some View {
        VStack(spacing: 12) {
            consoleSettingRow(index: 0, title: "Eco Mode (Efficiency Cores)", value: console.ecoEnabled ? "On" : "Off")
            consoleSettingRow(index: 1, title: "JIT Status", value: jitState.enabled ? "Enabled & Ready" : "Tap / Press A to Enable JIT")
            consoleSettingRow(index: 2, title: "Switch Back to Screen Mirroring", value: "Return output to phone display")
            Spacer()
        }
        .padding(.horizontal, 48)
        .padding(.top, 12)
    }

    private func consoleSettingRow(index: Int, title: String, value: String) -> some View {
        let selected = console.focusedRowIndex == index
        return Button {
            console.focusedRowIndex = index
            console.adjustSettingsRow(index, delta: 1)
        } label: {
            HStack {
                Text(title)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                HStack(spacing: 10) {
                    if selected { Image(systemName: "chevron.left").font(.caption).foregroundStyle(.cyan) }
                    Text(value)
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(selected ? .cyan : .white.opacity(0.75))
                    if selected { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.cyan) }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(selected ? Color.white.opacity(0.16) : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(selected ? Color.cyan : Color.white.opacity(0.08), lineWidth: selected ? 2.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .consoleHitTarget("row:\(index)")
    }

    private var bottomBar: some View {
        HStack(spacing: 20) {
            if console.tab == .games {
                hintPill("D-Pad / Arrows", "Browse")
                hintPill("A / Enter", "Play")
                hintPill("X / O", "Game Setup")
                hintPill("Y / F", "Filter")
            } else {
                hintPill("Up/Down", "Select")
                hintPill("Left/Right", "Change")
            }
            hintPill("LB / RB / Tab", "Switch Tab")
            Spacer()
            Text("In game: Back+Start or F10 for Pause Menu")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func hintPill(_ key: String, _ label: String) -> some View {
        HStack(spacing: 6) {
            Text(key)
                .font(.caption.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
        }
    }
}

private struct TVAspectPreviewDiagram: View {
    @ObservedObject private var external = ExternalDisplay.shared

    var body: some View {
        GeometryReader { geo in
            let full = CGRect(origin: .zero, size: geo.size)
            let tvBounds = ExternalDisplayLayout.rect(guest: CGSize(width: 16, height: 9),
                                                      bounds: full, mode: .fit)
            let guestSize = CGSize(width: 16, height: 9)
            let safe = ExternalDisplayLayout.safeBounds(for: tvBounds, overscanPercent: external.overscanPercent)
            let gameRect = ExternalDisplayLayout.rect(guest: guestSize,
                                                        bounds: tvBounds,
                                                        mode: external.displayMode,
                                                        aspectOverride: external.aspectOverride,
                                                        overscanPercent: external.overscanPercent)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black)
                    .frame(width: tvBounds.width, height: tvBounds.height)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.white.opacity(0.35), lineWidth: 1.5)
                    )
                    .offset(x: tvBounds.minX, y: tvBounds.minY)

                Rectangle()
                    .strokeBorder(Color.white.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .frame(width: safe.width, height: safe.height)
                    .offset(x: safe.minX, y: safe.minY)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.cyan.opacity(0.28))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.cyan, lineWidth: 2))
                    .frame(width: min(gameRect.width, tvBounds.width), height: min(gameRect.height, tvBounds.height))
                    .offset(x: max(tvBounds.minX, gameRect.minX), y: max(tvBounds.minY, gameRect.minY))
            }
        }
    }
}

// MARK: - TV Per-Game Options & Launch Splash & Pause Menu

private struct ExternalGameOptionsModal: View {
    let entry: LibraryEntry
    @ObservedObject private var console = ExternalConsoleController.shared
    @ObservedObject private var external = ExternalDisplay.shared

    var body: some View {
        ZStack {
            Color.black.opacity(0.65)
                .ignoresSafeArea()
                .onTapGesture { console.gameOptionsOpen = false }

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(entry.title).font(.title2.bold())
                    Spacer()
                    Button("Close (B / Esc)") { console.gameOptionsOpen = false }
                        .buttonStyle(.bordered)
                        .consoleHitTarget("opt:close")
                }

                optionRow(0, "FPS Limit", console.fpsLabel(entry.fpsMode))
                optionRow(1, "Controller Mapping", entry.controllerMode == "keys" ? "Keyboard & Mouse" : entry.controllerMode == "dinput" ? "XInput + DirectInput" : "Game's Own Support")
                optionRow(2, "x87 Precision", entry.x87Precision.rawValue.capitalized)
                optionRow(3, "Show Performance Stats (Phone)", entry.performance ? "On" : "Off")
                optionRow(4, "TV Aspect Ratio", external.aspectOverride.label)

                Button { console.launchEntry(entry) } label: {
                    HStack {
                        Spacer()
                        Label("Launch on TV", systemImage: "play.fill").font(.headline)
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .foregroundStyle(.black)
                    .background(console.gameOptionsRow == 5 ? Color.cyan : Color.white, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
                .consoleHitTarget("opt:5")
            }
            .padding(28)
            .frame(width: 560)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(.white.opacity(0.2)))
            .shadow(color: .black.opacity(0.6), radius: 30)
        }
    }

    private func optionRow(_ idx: Int, _ label: String, _ value: String) -> some View {
        let on = console.gameOptionsRow == idx
        return Button {
            console.gameOptionsRow = idx
            console.adjustGameOptionRow(idx, delta: 1)
        } label: {
            HStack {
                Text(label).font(.headline)
                Spacer()
                Text(value).foregroundStyle(on ? .cyan : .secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12).fill(on ? Color.white.opacity(0.16) : Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(on ? Color.cyan : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .consoleHitTarget("opt:\(idx)")
    }
}

private struct ExternalLaunchSplashView: View {
    let entry: LibraryEntry
    @ObservedObject private var model = LibraryModel.shared
    @ObservedObject private var dockStart = DockStartScreen.shared
    @ObservedObject private var external = ExternalDisplay.shared

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let appID = dockStart.appID ?? (entry.coverFile == nil ? entry.steamAppID : nil) {
                SteamLaunchBackdrop(appID: appID).opacity(0.45).blur(radius: 14).ignoresSafeArea()
            } else {
                LibraryArtwork(entry: entry, backdrop: true).opacity(0.45).blur(radius: 14).ignoresSafeArea()
            }
            Color.black.opacity(0.55).ignoresSafeArea()

            HStack(spacing: 36) {
                Group {
                    if let appID = dockStart.appID ?? (entry.coverFile == nil ? entry.steamAppID : nil) {
                        SteamGameArtwork(appID: appID)
                    } else {
                        LibraryArtwork(entry: entry)
                    }
                }
                .frame(width: 210, height: 315)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.75), radius: 28, y: 12)

                VStack(alignment: .leading, spacing: 14) {
                    Text("STARTING ON TV · \(external.effectiveLaunchResolution(gameResolution: entry.resolution))")
                        .font(.caption.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(.cyan)
                    Text(entry.title)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    if let failure = dockStart.failure {
                        Text(failure).font(.callout).foregroundStyle(.orange)
                    } else {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            HStack(spacing: 12) {
                                ProgressView().tint(.white)
                                Text(model.launchSlow ? "Still preparing shaders & runtime…" : "Launching session…")
                                    .foregroundStyle(.white.opacity(0.8))
                                Text("\(Int(context.date.timeIntervalSince(model.startingSince)))s")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Text("Live logs & performance tools stay on your iPhone/iPad screen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(48)
        }
    }
}

private struct ExternalInGameMenuView: View {
    @ObservedObject private var model = LibraryModel.shared
    @ObservedObject private var external = ExternalDisplay.shared
    @ObservedObject private var console = ExternalConsoleController.shared

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { model.menu = false }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(model.activeEntry?.title ?? "Game Session", systemImage: "gamecontroller.fill")
                        .font(.title2.bold())
                    Spacer()
                    Text("TV Pause Menu").font(.subheadline).foregroundStyle(.cyan)
                }
                .padding(.bottom, 4)

                pauseRow(0, "Resume Game", "B / Esc")
                pauseRow(1, "Scaling Mode", external.displayMode.label)
                pauseRow(2, "Aspect Ratio", external.aspectOverride.label)
                pauseRow(3, "TV Overscan Margin", String(format: "%.1f%%", external.overscanPercent))
                pauseRow(4, "FPS Cap", console.fpsLabel(model.fpsMode))
                pauseRow(5, "Eco Mode", console.ecoEnabled ? "On" : "Off")
                pauseRow(6, "Phone Performance Overlay", model.performance ? "Shown" : "Hidden")
                pauseRow(7, "Move Game to Phone Screen", "Mirroring")
                pauseRow(8, "Quit Game", "Alt+F4", destructive: true)
            }
            .padding(28)
            .frame(width: 560)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(.white.opacity(0.18)))
            .shadow(color: .black.opacity(0.65), radius: 32)
        }
    }

    private func pauseRow(_ idx: Int, _ label: String, _ value: String, destructive: Bool = false) -> some View {
        let on = console.pauseMenuIndex == idx
        return Button {
            console.pauseMenuIndex = idx
            console.activatePauseRow(idx)
        } label: {
            HStack {
                Text(label)
                    .font(.headline)
                    .foregroundStyle(destructive ? Color.red : Color.white)
                Spacer()
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(on ? .cyan : .secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12).fill(on ? Color.white.opacity(0.16) : Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(on ? Color.cyan : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .consoleHitTarget("pause:\(idx)")
    }
}

// MARK: - Phone Companion Deck & Library Banner

struct ExternalLibraryBanner: View {
    @ObservedObject private var external = ExternalDisplay.shared

    var body: some View {
        if external.isConnected {
            HStack(spacing: 12) {
                Image(systemName: external.isActive ? "tv.fill" : "tv.slash")
                    .font(.title3)
                    .foregroundStyle(external.isActive ? .cyan : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(external.isActive ? "TV Console Active" : "External Display Detected")
                        .font(.subheadline.weight(.semibold))
                    Text(external.isActive
                         ? "\(Int(external.screenBounds.width))×\(Int(external.screenBounds.height)) @ \(external.screenMaxFPS) Hz · Controller & Keyboard steer the TV"
                         : "Dedicated console view paused — mirroring phone screen")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Toggle("", isOn: $external.userEnabled)
                    .labelsHidden()
                    .accessibilityLabel("Dedicated TV Console")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.12)))
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }
}

struct ExternalPhoneCompanionView: View {
    @ObservedObject private var external = ExternalDisplay.shared
    @ObservedObject private var model = LibraryModel.shared
    @ObservedObject private var hardware = HardwareInput.shared
    @State private var eco = madeira_get_eco() != 0
    @State private var liveLogs = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard
                telemetryCard
                displayControlsCard
                inputIsolationCard
                sessionActionsRow
            }
            .padding(18)
        }
        .background(Color(red: 0.024, green: 0.027, blue: 0.039).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear { eco = madeira_get_eco() != 0 }
    }

    private var headerCard: some View {
        HStack(spacing: 14) {
            if let entry = model.activeEntry {
                Group {
                    if let appID = entry.steamAppID, entry.coverFile == nil {
                        SteamGameArtwork(appID: appID)
                    } else {
                        LibraryArtwork(entry: entry)
                    }
                }
                .frame(width: 48, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(model.activeEntry?.title ?? "Running Session")
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Circle().fill(.green).frame(width: 7, height: 7)
                    Text("TV \(Int(external.screenBounds.width))×\(Int(external.screenBounds.height)) @ \(external.screenMaxFPS) Hz")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Move to Phone") {
                external.userEnabled = false
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
            .tint(.cyan)
        }
        .padding(14)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var telemetryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Live Telemetry (Phone Only)", systemImage: "waveform.path.ecg")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.cyan)
                Spacer()
                Toggle("Logs", isOn: $liveLogs)
                    .labelsHidden()
                    .toggleStyle(.button)
                    .font(.caption)
                Button(model.performance ? "All Stats" : "Minimal") {
                    model.performance.toggle()
                    model.saveCurrentProfile()
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }

            LibraryMetrics()
                .frame(maxWidth: .infinity)

            FrameTimeGraph(width: 300, height: 48, scale: 1.0, seconds: 4.0, colours: true)
                .frame(maxWidth: .infinity)

            if liveLogs {
                LibraryLiveLogs()
                    .frame(height: 150)
            }
        }
        .padding(14)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var displayControlsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("TV Display & Performance", systemImage: "tv")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.cyan)

            VStack(alignment: .leading, spacing: 6) {
                Text("Scaling Mode").font(.caption).foregroundStyle(.secondary)
                Picker("Scaling", selection: $external.displayMode) {
                    ForEach(DisplayMode.allCases, id: \.self) { m in Text(m.label).tag(m) }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Aspect Ratio Override").font(.caption).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ExternalAspectRatio.allCases) { ar in
                            let on = external.aspectOverride == ar
                            Button(ar.label) { external.aspectOverride = ar }
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .foregroundStyle(on ? .black : .white)
                                .background(Capsule().fill(on ? Color.cyan : Color.white.opacity(0.12)))
                                .buttonStyle(.plain)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("TV Overscan Margin").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.1f%%", external.overscanPercent)).font(.caption.monospacedDigit())
                }
                Slider(value: $external.overscanPercent, in: 0...10, step: 0.5) { editing in
                    if editing { external.previewOverscanGuides() }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("FPS Cap").font(.caption).foregroundStyle(.secondary)
                Picker("FPS Cap", selection: Binding(get: { model.fpsMode }, set: { model.setFPS($0) })) {
                    if ProMotionIntent.has30Cap || model.fpsMode == 3 { Text("30").tag(3) }
                    if ProMotionIntent.has40Cap || model.fpsMode == 4 { Text("40").tag(4) }
                    Text("60").tag(1)
                    Text("MAX").tag(0)
                    Text("RAW").tag(2)
                }
                .pickerStyle(.segmented)
            }

            Toggle("Eco Mode (Cooler / Lower Clocks)", isOn: Binding(get: { eco }, set: { on in
                eco = on
                madeira_set_eco(on ? 1 : 0)
            }))
            .font(.subheadline)
        }
        .padding(14)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var inputIsolationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Phone Input Mode", systemImage: "hand.tap")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.cyan)
            Text("In Companion Deck mode, stray touches on your phone cannot click or disturb the game on your TV.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Phone Mode", selection: $external.phoneMode) {
                ForEach(ExternalPhoneMode.allCases) { m in Text(m.label).tag(m) }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 12) {
                let padCount = GCController.controllers().count
                Label("\(padCount) Pad\(padCount == 1 ? "" : "s")", systemImage: "gamecontroller.fill")
                    .foregroundStyle(padCount > 0 ? .green : .secondary)
                Label(hardware.keyboardConnected ? "KB" : "No KB", systemImage: "keyboard")
                    .foregroundStyle(hardware.keyboardConnected ? .white : .secondary)
                Label(hardware.mouseConnected ? "Mouse" : "No Mouse", systemImage: "computermouse")
                    .foregroundStyle(hardware.mouseConnected ? .white : .secondary)
            }
            .font(.caption)
        }
        .padding(14)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var sessionActionsRow: some View {
        HStack(spacing: 12) {
            Button {
                model.showMenu()
            } label: {
                Label("TV Menu", systemImage: "line.3.horizontal")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                LibraryKeyboard.show()
            } label: {
                Label("Keyboard", systemImage: "keyboard")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button(role: .destructive) {
                model.requestQuit()
            } label: {
                Label("Quit", systemImage: "stop.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }
}
#endif
