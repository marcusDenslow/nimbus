import AppKit
import GameController

/// Single pipe for controller and keyboard input.
///
/// Controllers are polled at 30 Hz rather than driven by per-element handlers so
/// held directions can auto-repeat with a typing-style delay curve, which is what
/// makes long grids tolerable to navigate with a stick.
@MainActor
final class InputRouter {
    private enum Direction { case left, right, up, down }

    private weak var model: AppModel?
    private var pollTimer: Timer?
    private var keyMonitor: Any?
    private var mouseMonitor: Any?

    private enum TriggerFeel { case armed, firing, off }
    private var currentFeel: TriggerFeel?
    private var lastShotAt: TimeInterval = 0        // cadence clock for recoil accents
    private static let shotInterval: TimeInterval = 0.5    // fire rate: 2 rounds/sec

    /// Direct-to-motor rumble over raw HID — CoreHaptics can't reach the DualSense grips on macOS.
    private let rumble = DualSenseRumble()

    private var heldDirection: Direction?
    private var nextRepeatDeadline: TimeInterval = 0
    private var previousButtons: Set<String> = []

    // Hold Circle (B) to snap the shelf back to the first game.
    private var backHeldSince: TimeInterval?
    private var backHoldFired = false

    private static let initialRepeatDelay: TimeInterval = 0.35
    private static let repeatInterval: TimeInterval = 0.09
    private static let holdHomeDelay: TimeInterval = 0.45
    // Generous dead zone: a drifting stick that idles past a lower threshold
    // reads as an endless scroll in one direction.
    private static let stickThreshold: Float = 0.65

    init(model: AppModel) {
        self.model = model

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak model] event in
            guard let model else { return event }
            return model.handleKey(event) ? nil : event
        }

        // Pointer activity resets the idle clock; only a deliberate click wakes standby (a moving
        // or scrolling mouse shouldn't yank you out — same rule as the controller's designated button).
        mouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown, .scrollWheel]
        ) { [weak model] event in
            if event.type == .leftMouseDown { model?.wakeFromStandby() }
            model?.noteActivity()
            return event
        }

        NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshControllerState() }
        }
        NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshControllerState() }
        }
        refreshControllerState()

        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    deinit {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
        }
        pollTimer?.invalidate()
    }

    private func refreshControllerState() {
        model?.controllerConnected = GCController.controllers().contains { $0.extendedGamepad != nil }
    }

    private func poll() {
        guard let model else { return }
        guard let controller = GCController.controllers().first(where: { $0.extendedGamepad != nil }),
              let pad = controller.extendedGamepad else {
            heldDirection = nil
            previousButtons = []
            backHeldSince = nil
            backHoldFired = false
            currentFeel = nil
            rumble.stop()
            model.stickDirection = .zero
            model.backHoldProgress = 0
            return
        }

        updateAdaptiveTriggers(pad)

        // Raw stick vector drives the particle background drift (dead-zoned).
        let sx = pad.leftThumbstick.xAxis.value, sy = pad.leftThumbstick.yAxis.value
        model.stickDirection = CGVector(
            dx: abs(sx) > 0.12 ? CGFloat(sx) : 0,
            dy: abs(sy) > 0.12 ? CGFloat(sy) : 0
        )

        // Buttons fire on the press edge only.
        var buttons = Set<String>()
        if pad.buttonA.isPressed { buttons.insert("a") }
        if pad.buttonB.isPressed { buttons.insert("b") }
        if pad.buttonX.isPressed { buttons.insert("x") }
        if pad.buttonY.isPressed { buttons.insert("y") }
        if pad.buttonMenu.isPressed { buttons.insert("menu") }
        if pad.buttonOptions?.isPressed == true { buttons.insert("options") }
        if pad.leftShoulder.isPressed { buttons.insert("l1") }
        if pad.rightShoulder.isPressed { buttons.insert("r1") }
        // R2 pushed through the gun trigger's break (~0.6 wall) = fire. Half-pulls stall on the wall.
        if pad.rightTrigger.value >= 0.65 { buttons.insert("r2") }
        // L2 pull = find in library (search overlay scoped to the user's own shelf).
        if pad.leftTrigger.value >= 0.65 { buttons.insert("l2") }

        let newPresses = buttons.subtracting(previousButtons)
        let dpadActive = pad.dpad.left.isPressed || pad.dpad.right.isPressed
            || pad.dpad.up.isPressed || pad.dpad.down.isPressed
        let stickActive = abs(sx) >= Self.stickThreshold || abs(sy) >= Self.stickThreshold

        // Standby: only ✕ / Cross wakes it; every other button, d-pad, or stick nudge is swallowed
        // so you can't yank the screen out of standby by bumping the controller.
        if model.standby {
            if newPresses.contains("a") { model.wakeFromStandby() }
            previousButtons = buttons
            heldDirection = nil
            return
        }

        if !newPresses.isEmpty || dpadActive || stickActive { model.noteActivity() }

        // During the boot intro, any button press starts the app.
        if !model.booted {
            if !newPresses.isEmpty { model.finishBoot() }
            previousButtons = buttons
            return
        }

        for pressed in newPresses {
            switch pressed {
            case "a": model.handle(.confirm)      // Cross → Play / activate
            case "b": model.handle(.back)         // Circle → out
            case "x": model.handle(.info)         // Square → open info
            case "y": model.handle(.remove)       // Triangle → remove
            case "menu": model.handle(.toggleSearch)
            case "options": model.handle(.sync)
            case "l1": model.handle(.folderPrev)
            case "r1": model.handle(.folderNext)
            case "r2": model.launchFromTrigger()
            case "l2": model.openLibrarySearchFromTrigger()
            default: break
            }
        }
        // Recoil is driven by the full-auto loop in updateAdaptiveTriggers, not here.
        previousButtons = buttons

        // D-pad wins over the stick; the stick uses a dead zone and dominant-axis pick.
        var direction: Direction?
        if pad.dpad.left.isPressed { direction = .left }
        else if pad.dpad.right.isPressed { direction = .right }
        else if pad.dpad.up.isPressed { direction = .up }
        else if pad.dpad.down.isPressed { direction = .down }
        else {
            let x = pad.leftThumbstick.xAxis.value
            let y = pad.leftThumbstick.yAxis.value
            if abs(x) >= Self.stickThreshold || abs(y) >= Self.stickThreshold {
                direction = abs(x) > abs(y) ? (x > 0 ? .right : .left) : (y > 0 ? .up : .down)
            }
        }

        let now = ProcessInfo.processInfo.systemUptime

        // Circle press already fired `.back` (press edge); a sustained hold additionally snaps
        // the shelf to the first game once, so a deep Surprise-Me pick is one hold from home.
        // The hold's progress feeds a ring on the hint bar so you can see it filling.
        if buttons.contains("b"), model.canJumpToShelfStart {
            if backHeldSince == nil { backHeldSince = now }
            let elapsed = now - (backHeldSince ?? now)
            if !backHoldFired {
                let progress = min(1, elapsed / Self.holdHomeDelay)
                if abs(model.backHoldProgress - progress) > 0.01 { model.backHoldProgress = progress }
                if elapsed >= Self.holdHomeDelay {
                    backHoldFired = true
                    model.backHoldProgress = 0
                    model.jumpToShelfStart()
                }
            }
        } else {
            backHeldSince = nil
            backHoldFired = false
            if model.backHoldProgress != 0 { model.backHoldProgress = 0 }
        }

        switch (direction, heldDirection) {
        case (nil, _):
            heldDirection = nil
        case let (new?, held) where new != held:
            heldDirection = new
            nextRepeatDeadline = now + Self.initialRepeatDelay
            emit(new)
        case let (new?, _):
            if now >= nextRepeatDeadline {
                nextRepeatDeadline = now + Self.repeatInterval
                emit(new)
            }
        }
    }

    /// DualSense only: arm R2 as a gun trigger — free take-up, a hard wall, then a break where
    /// the shot fires — and idle everywhere else. Feeds the live pull value to the Play button.
    private func updateAdaptiveTriggers(_ pad: GCExtendedGamepad) {
        let launchReady = model?.booted == true && model?.stage == .ready
            && model?.standby == false && model?.mode == .library
            && model?.profileMenuOpen == false && model?.keyboardActive == false
            && model?.trailerMode == false && model?.customizeGameID == nil
            && model?.libraryZone == .shelf && model?.focusedGame != nil

        let rawPull = CGFloat(pad.rightTrigger.value)

        guard let ds = pad as? GCDualSenseGamepad, let model else { currentFeel = nil; return }

        // Live pull for the Play button's draw animation (throttled to avoid churn).
        let pull: CGFloat = launchReady ? rawPull : 0
        if abs(pull - model.triggerPull) > 0.02 || (pull == 0 && model.triggerPull != 0) {
            model.triggerPull = pull
        }

        guard launchReady else {
            if currentFeel != .off { rumble.stop(); ds.rightTrigger.setModeOff(); currentFeel = .off }
            return
        }

        // Gun trigger (Nielk1 #4): free take-up, then a firm wall 0.45→0.6 you push THROUGH to fire.
        // Past the break the grips rumble via raw HID: a strong sustain the whole hold, spiked by a
        // sharp punch twice a second (the rounds). Left motor (strong/low-freq) leads. The trigger
        // itself never vibrates. Hysteresis (fire ≥0.65, back to the wall <0.5) debounces the edge.
        let firing = currentFeel == .firing ? rawPull >= 0.5 : rawPull >= 0.65
        if firing {
            let now = ProcessInfo.processInfo.systemUptime
            if currentFeel != .firing { currentFeel = .firing; lastShotAt = now }
            if now - lastShotAt >= Self.shotInterval { lastShotAt = now }   // next round, 2/sec
            let punch = Float(exp(-(now - lastShotAt) / 0.06))              // sharp attack, fast decay
            let level = max(0.55, punch)                                    // never below a strong sustain
            rumble.set(left: level, right: level * 0.7)
        } else if currentFeel != .armed {
            rumble.stop()
            ds.rightTrigger.setModeWeaponWithStartPosition(0.45, endPosition: 0.6, resistiveStrength: 1.0)
            currentFeel = .armed
        }
    }

    private func emit(_ direction: Direction) {
        switch direction {
        case .left: model?.handle(.left)
        case .right: model?.handle(.right)
        case .up: model?.handle(.up)
        case .down: model?.handle(.down)
        }
    }
}
