import SwiftUI
import AVFoundation

/// A looping, layer-backed video player for the ambient trailer preview. Wraps `AVPlayerLayer`
/// directly — SwiftUI's `VideoPlayer` brings transport chrome we don't want behind the shelf.
///
/// `isActive` gates both playback and audio: inactive → paused and muted, so a trailer that's
/// faded out (or whose game just lost focus) makes no sound and burns no cycles decoding.
struct TrailerPlayer: NSViewRepresentable {
    let url: URL
    let isActive: Bool
    var muted: Bool = false
    var volume: Float = 0.85
    /// Ambient background videos loop forever; a full-screen trailer plays once.
    var loops: Bool = true
    /// Called when a non-looping trailer reaches its end, so the shelf can come back.
    var onEnded: (() -> Void)? = nil
    /// Called once the layer has a first frame ready to display — the moment a fade-in
    /// becomes visible instead of fading in transparency.
    var onReady: (() -> Void)? = nil

    func makeNSView(context: Context) -> PlayerNSView {
        let view = PlayerNSView()
        view.onEnded = onEnded
        view.onReady = onReady
        view.load(url: url, loops: loops)
        view.setVolume(volume)
        return view
    }

    func updateNSView(_ nsView: PlayerNSView, context: Context) {
        nsView.onEnded = onEnded
        nsView.onReady = onReady
        nsView.setVolume(volume)
        nsView.setActive(isActive, muted: muted)
    }

    static func dismantleNSView(_ nsView: PlayerNSView, coordinator: ()) {
        nsView.teardown()
    }
}

/// Hosts an `AVPlayerLayer`. Looping content rides an `AVQueuePlayer` + `AVPlayerLooper` for a
/// seamless loop; a one-shot trailer runs a plain player and fires `onEnded` when it finishes.
final class PlayerNSView: NSView {
    private var player: AVPlayer?
    private var looper: AVPlayerLooper?
    private var endObserver: NSObjectProtocol?
    private var readyObservation: NSKeyValueObservation?
    var onEnded: (() -> Void)?
    var onReady: (() -> Void)?
    private let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspectFill   // full-bleed, matches the hero art fill
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func load(url: URL, loops: Bool) {
        readyObservation = playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
            guard layer.isReadyForDisplay else { return }
            Task { @MainActor in self?.onReady?() }
        }
        // Attach an as-yet-unloaded item: AVFoundation then spins the decoder up off the main
        // thread, so the mount itself is near-free. (Pre-loading the asset first, by contrast,
        // makes this attach do the decoder setup synchronously — a ~80ms main-thread stall.)
        let item = AVPlayerItem(url: url)
        if loops {
            let queue = AVQueuePlayer()
            queue.isMuted = true
            looper = AVPlayerLooper(player: queue, templateItem: item)
            playerLayer.player = queue
            player = queue
        } else {
            let single = AVPlayer(playerItem: item)
            single.isMuted = true
            single.actionAtItemEnd = .pause   // stop at the end rather than freezing on a black frame
            playerLayer.player = single
            player = single
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.onEnded?() }
            }
        }
    }

    func setVolume(_ volume: Float) {
        player?.volume = volume
    }

    func setActive(_ active: Bool, muted: Bool = false) {
        guard let player else { return }
        if active {
            player.isMuted = muted
            player.play()
        } else {
            player.pause()
            player.isMuted = true
        }
    }

    func teardown() {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        readyObservation?.invalidate()
        readyObservation = nil
        player?.pause()
        playerLayer.player = nil
        looper = nil
        player = nil
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}

extension AnyTransition {
    /// Background art swap: a pure opacity cross-dissolve — identical to the video layers'
    /// fade, so every background change (static or video, in or out) moves the same way.
    /// Removal is identity because the outgoing art is held statically underneath during the
    /// fade, so there's no dip to black.
    static var heroShift: AnyTransition {
        .asymmetric(insertion: .opacity, removal: .identity)
    }
}
