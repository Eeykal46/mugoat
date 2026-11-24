import UIKit

/// Frame-rate Auto, across sessions: learns the render height this phone sustains 60 FPS at without
/// running hot. The back buffer cannot change size during play (the engine's ResizeBuffers crashed), so
/// a change applies at the next start; within a session the governor (NativeSmoothGovernor) moves the
/// frame cap between the screen's rate, 60 and 30 for late frames and heat.
///
/// Each performance-log window (about a minute of world frames) is added; a decision needs 2 minutes:
/// - hot (iOS "serious" or worse) for over a third of the time: one step lower;
/// - under 54 FPS with the GPU busy over 80% of a 60 FPS frame and over 70% of the frames it actually
///   gives: one step lower (fewer pixels help). When the game's own threads hold the frame rate (the GPU
///   then waits part of each frame), fewer pixels would only blur the picture;
/// - 58 FPS or more with the GPU under 55% of a 60 FPS frame and never hot: one step higher;
/// - otherwise (the game's own threads are the limit) the height stays.
final class AutoTune {
    static let shared = AutoTune()
    static let steps = [432, 480, 540, 600, 660, 720, 810, 900, 1080, 1296, 1440, 2160]
    private let defaults = UserDefaults.standard
    private var frames = 0.0, seconds = 0.0, gpuMs = 0.0, hotSeconds = 0.0
    /// Receives a line for the app log when the learned height changes.
    var log: ((String) -> Void)?

    /// 0 until a height was learned.
    var learnedHeight: Int {
        get { defaults.integer(forKey: "autoTuneHeight") }
        set { defaults.set(newValue, forKey: "autoTuneHeight") }
    }

    func record(frames windowFrames: Int, seconds windowSeconds: Double, gpuMsPerFrame: Double, thermal: Int) {
        guard windowFrames >= 60, windowSeconds > 10 else { return }		// paused or loading
        frames += Double(windowFrames)
        seconds += windowSeconds
        gpuMs += gpuMsPerFrame * Double(windowFrames)
        if thermal >= 2 { hotSeconds += windowSeconds }
        if seconds >= 120 { decide() }
    }

    /// Returns a line for the log when the height changed.
    @discardableResult
    func decide() -> String? {
        let settings = GameSettings.shared
        defer { frames = 0; seconds = 0; gpuMs = 0; hotSeconds = 0 }
        guard settings.frameRateAuto, settings.renderHeight == 0, seconds >= 120, frames > 0 else { return nil }
        let presetHeight = settings.graphicsPreset.height
        var (_, current) = GraphicsConfiguration.size(for: settings.graphicsPreset, renderHeight: GraphicsConfiguration.effectiveRenderHeight(settings),
                                                     screen: UIScreen.main.nativeBounds.size, matchScreenShape: false)
        current = min(current, presetHeight)
        let fps = frames / seconds, gpu = gpuMs / frames, hot = hotSeconds / seconds
        let budget = 1000.0 / 60, frameMs = 1000 / max(fps, 1)
        let gpuBound = gpu > budget * 0.8 && gpu > frameMs * 0.7
        let index = Self.steps.lastIndex(where: { $0 <= current }) ?? 0
        var next = current
        if hot > 0.33 || (fps < 54 && gpuBound) { next = Self.steps[max(0, index - 1)] }
        else if fps >= 58 && gpu < budget * 0.55 && hot == 0 { next = min(presetHeight, Self.steps[min(Self.steps.count - 1, index + 1)]) }
        guard next != current else { return nil }
        learnedHeight = next >= presetHeight ? 0 : next
        let line = String(format: "Auto: next start renders at %dp (was %dp; %.1f FPS, GPU %.1f ms/frame, hot %.0f%% of the time)", next, current, fps, gpu, hot * 100)
        log?(line)
        return line
    }
}
