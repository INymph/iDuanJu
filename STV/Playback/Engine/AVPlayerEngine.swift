import AVFoundation
import AVKit
import MediaPlayer
import UIKit

/// iOS 16 system player, including the resource-loader AES path and decrypted CENC files.
@MainActor final class AVPlayerEngine: PlayerEngine {
    let kind = PlayerEngineKind.avplayer
    var onFailed: ((Error?) -> Void)?
    var onEnded: (() -> Void)?
    var onPlaybackRequested: ((Bool) -> Void)?
    private let transport = PlayerTransportObserver()

    final class Surface: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    let player: AVPlayer = {
        let p = AVPlayer()
        p.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        return p
    }()
    private let view = Surface()
    var surface: UIView { view }
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var generation = 0
    private var tracksTask: Task<Void, Never>?
    private var loadedTrackCount: Int?
    private var audioGroup: AVMediaSelectionGroup?
    private var legibleGroup: AVMediaSelectionGroup?
    private(set) var audioTracks: [MediaTrack] = []
    private(set) var subtitleTracks: [MediaTrack] = []
    private(set) var selectedAudio: Int?
    private(set) var selectedSubtitle: Int?

    init() {
        view.backgroundColor = .black
        view.isUserInteractionEnabled = false
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        transport.onRequest = { [weak self] in self?.onPlaybackRequested?($0) }
    }

    func supports(_ src: PlaybackCoordinator.Source) -> Bool { true }

    func load(_ src: PlaybackCoordinator.Source, stream: HGStream?, start: Double?, title: String) async throws {
        generation += 1
        let gen = generation
        tracksTask?.cancel(); tracksTask = nil; loadedTrackCount = nil
        transport.acceptingRequests = false
        transport.bind(player)
        view.playerLayer.player = player
        transport.expectPaused(true)
        statusObservation?.invalidate()
        statusObservation = nil
        guard let item = PlaybackCoordinator.makeItem(src) else { throw URLError(.badURL) }
        item.nowPlayingInfo = [MPMediaItemPropertyTitle: title]
        audioGroup = nil; legibleGroup = nil; audioTracks = []; subtitleTracks = []; selectedAudio = nil; selectedSubtitle = nil
        player.replaceCurrentItem(with: item)
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self, self.generation == gen else { return }
                if item.status == .readyToPlay { self.ensureTracks(item) }
                guard item.status == .failed else { return }
                #if DEBUG
                let ns = item.error as NSError?
                let under = (ns?.userInfo[NSUnderlyingErrorKey] as? NSError).map { "\($0.domain) \($0.code)" } ?? "-"
                NSLog("%@", "[STV] avplayer item failed \(ns?.domain ?? "-") \(ns?.code ?? 0) under=\(under)")
                #endif
                self.onFailed?(item.error)
            }
        }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.generation == gen else { return }
                self.onEnded?()
            }
        }
        if let start, start > 0 {
            await player.seek(to: CMTime(seconds: start, preferredTimescale: 600))
        }
        guard generation == gen, player.currentItem === item, !Task.isCancelled else { throw CancellationError() }
        if item.status == .failed { throw item.error ?? URLError(.cannotOpenFile) }
        transport.acceptingRequests = true
        ensureTracks(item)
    }

    func play(rate: Double) {
        transport.expectPaused(false)
        player.defaultRate = Float(rate)
        player.play()
    }

    func pause() { transport.expectPaused(true); player.pause() }

    func setRate(_ rate: Double) {
        player.defaultRate = Float(rate)
        if player.rate != 0 { player.rate = Float(rate) }
    }

    func seek(to seconds: Double) async {
        await player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func stop() {
        transport.acceptingRequests = false
        generation += 1
        tracksTask?.cancel(); tracksTask = nil; loadedTrackCount = nil
        statusObservation?.invalidate()
        statusObservation = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        transport.bind(nil)
        view.playerLayer.player = nil
        if player.currentItem != nil { player.replaceCurrentItem(with: nil) }
    }

    var currentTime: Double { player.currentTime().seconds.isFinite ? player.currentTime().seconds : 0 }
    var duration: Double {
        guard let d = player.currentItem?.duration.seconds, d.isFinite, d > 0 else { return 0 }
        return d
    }
    var bufferedUntil: Double {
        guard let ranges = player.currentItem?.loadedTimeRanges.map(\.timeRangeValue) else { return 0 }
        let t = currentTime
        let r = ranges.first { $0.start.seconds <= t + 1 && ($0.start + $0.duration).seconds >= t } ?? ranges.first
        return r.map { ($0.start + $0.duration).seconds } ?? 0
    }
    var presentationSize: CGSize { player.currentItem?.presentationSize ?? .zero }
    var isWaiting: Bool { player.timeControlStatus == .waitingToPlayAtSpecifiedRate }
    var isPaused: Bool { player.timeControlStatus == .paused }
    var muted: Bool { get { player.isMuted } set { player.isMuted = newValue } }
    var maxRate: Double { 3.0 }
    var fill: Bool = false {
        didSet { view.playerLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect }
    }

    // MARK: Tracks (AVMediaSelection)

    private func ensureTracks(_ item: AVPlayerItem) {
        guard player.currentItem === item, item.status == .readyToPlay,
              loadedTrackCount != item.tracks.count, tracksTask == nil else { return }
        let gen = generation
        let count = item.tracks.count
        tracksTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshTracks(item)
            guard self.generation == gen, self.player.currentItem === item else { return }
            self.loadedTrackCount = count
            self.tracksTask = nil
        }
    }

    private func refreshTracks(_ item: AVPlayerItem) async {
        let audible = try? await item.asset.loadMediaSelectionGroup(for: .audible)
        guard !Task.isCancelled, player.currentItem === item else { return }
        if let g = audible {
            audioGroup = g
            audioTracks = g.options.enumerated().map { MediaTrack(id: $0.offset, title: $0.element.displayName, language: $0.element.extendedLanguageTag) }
            selectedAudio = item.currentMediaSelection.selectedMediaOption(in: g).flatMap { g.options.firstIndex(of: $0) }
        }
        let legible = try? await item.asset.loadMediaSelectionGroup(for: .legible)
        guard !Task.isCancelled, player.currentItem === item else { return }
        if let g = legible {
            legibleGroup = g
            subtitleTracks = g.options.enumerated().map { MediaTrack(id: $0.offset, title: $0.element.displayName, language: $0.element.extendedLanguageTag) }
            selectedSubtitle = item.currentMediaSelection.selectedMediaOption(in: g).flatMap { g.options.firstIndex(of: $0) }
        }
    }

    func selectAudio(_ id: Int) {
        guard let item = player.currentItem, let g = audioGroup, g.options.indices.contains(id) else { return }
        item.select(g.options[id], in: g); selectedAudio = id
    }

    func selectSubtitle(_ id: Int?) {
        guard let item = player.currentItem, let g = legibleGroup else { return }
        if let id, g.options.indices.contains(id) { item.select(g.options[id], in: g); selectedSubtitle = id }
        else { item.select(nil, in: g); selectedSubtitle = nil }
    }

    var subtitleText: String? { nil }   // AVPlayer renders legible output itself

    func tech(stream: HGStream?) async -> PlayerTech {
        guard let item = player.currentItem else { return PlayerTech() }
        var t = await PlayerTech.read(item, stream: stream)
        t.engine = kind.short
        guard player.currentItem === item else { return PlayerTech() }
        ensureTracks(item)
        if let g = audioGroup {
            selectedAudio = item.currentMediaSelection.selectedMediaOption(in: g).flatMap { g.options.firstIndex(of: $0) }
        }
        if let g = legibleGroup {
            selectedSubtitle = item.currentMediaSelection.selectedMediaOption(in: g).flatMap { g.options.firstIndex(of: $0) }
        }
        return t
    }

    var avPlayer: AVPlayer? { player }
    var pipIdentity: ObjectIdentifier? { ObjectIdentifier(view.playerLayer) }
    func makePiPController() -> AVPictureInPictureController? { AVPictureInPictureController(playerLayer: view.playerLayer) }
    func setPiPActive(_ active: Bool) {}
    var routeLabel: String { "AVPlayer" }
}
