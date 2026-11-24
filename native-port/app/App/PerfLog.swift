import Foundation
import UIKit
import os

/// Writes one CSV line a minute of world play to Files › Mugoat › PerfLogs, so two builds (or Mugoat and
/// another app's HUD) can be compared on the same phone, place and settings. Nothing is uploaded.
final class PerfLog {
    static let shared = PerfLog()

    private var fileURL: URL?
    private var lastWrite: CFTimeInterval = 0
    private var startedAt: CFTimeInterval = 0
    private var memoryWarnings = 0
    // Counters at the previous line: each line shows what happened during its own window.
    private var lastCounters = PGRenderCounters()
    private var lastReliefs: UInt64 = 0, lastEvictions: UInt64 = 0, lastClamps: UInt64 = 0
    private let queue = DispatchQueue(label: "mugoat.perflog", qos: .utility)
    private static let header = "time,elapsed_s,device,ram_gb,preset,render_w,render_h,frames,fps_avg,p95_ms,p99_ms,max_ms,over33,over50,over100,gpu_ms_per_frame,thermal,footprint_mb,available_mb,smooth_scale,frame_limit,memory_warnings," +
        "skipped_draws,pipeline_wait_skips,new_pipelines,texture_create_failures,texture_gpu_mb,bc_texture_gpu_mb,metal_allocated_mb," +
        "metal_working_set_mb,app_limit_mb,video_budget_mb,memory_reliefs,guard_evictions,guard_clamps,low_power,background_holds,free_address_space_mb\n"

    private init() {
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            self?.memoryWarnings += 1
        }
    }

    /// Call when the world is first shown: opens a new file for this session.
    func start() {
        guard fileURL == nil else { return }
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("PerfLogs", isDirectory: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = folder.appendingPathComponent("perf-\(formatter.string(from: Date())).csv")
        startedAt = CACurrentMediaTime()
        lastWrite = startedAt
        var discard = PGPerfWindow()
        _ = PGTakePerfWindow(&discard)	// start from an empty window
        _ = PGReadRenderCounters(&lastCounters)
        lastReliefs = PGMemoryReliefs(); lastEvictions = PGMemoryBudgetEvictions(); lastClamps = PGMemoryBudgetClamps()
        queue.async {
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try Self.header.write(to: url, atomically: true, encoding: .utf8)
                self.removeOldLogs(in: folder, keeping: 20)
            } catch {
                return
            }
        }
        fileURL = url
    }

    /// Call often (the controller poll); writes when a minute has passed.
    func tick(now: CFTimeInterval, preset: String, smoothScale: Double, frameLimit: Int32) {
        // First line after 20 s (a crash soon after loading still leaves numbers), then once a minute.
        guard let url = fileURL, now - lastWrite >= (lastWrite == startedAt ? 20 : 60) else { return }
        lastWrite = now
        var window = PGPerfWindow()
        guard PGTakePerfWindow(&window) else { return }
        var width: Int32 = 0, height: Int32 = 0
        PGGetRenderSize(&width, &height)
        let tier = GameSettings.shared.tier
        let (footprint, available) = Self.memoryMB()
        let time = ISO8601DateFormatter().string(from: Date())
        let fields: [String] = [
            time, String(format: "%.0f", now - startedAt), tier.model, String(format: "%.1f", Double(tier.physicalMemoryMB) / 1024),
            preset.replacingOccurrences(of: ",", with: " "), "\(width)", "\(height)", "\(window.frames)",
            String(format: "%.1f", window.fps), String(format: "%.1f", window.p95Ms), String(format: "%.1f", window.p99Ms),
            String(format: "%.1f", window.maxMs), "\(window.over33)", "\(window.over50)", "\(window.over100)",
            String(format: "%.2f", window.gpuMsPerFrame), "\(ProcessInfo.processInfo.thermalState.rawValue)",
            "\(footprint)", "\(available)", String(format: "%.2f", smoothScale), "\(frameLimit)", "\(memoryWarnings)"
        ] + counterFields(tier: tier)
        let line = fields.joined(separator: ",") + "\n"
        queue.async {
            guard let data = line.data(using: .utf8), let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    }

    /// Renderer and memory-guard columns: counts during this window, memory now (MB).
    private func counterFields(tier: DeviceTier) -> [String] {
        var c = PGRenderCounters()
        _ = PGReadRenderCounters(&c)
        let reliefs = PGMemoryReliefs(), evictions = PGMemoryBudgetEvictions(), clamps = PGMemoryBudgetClamps()
        func delta(_ now: UInt64, _ before: UInt64) -> String { "\(now >= before ? now - before : now)" }
        let fields = [
            delta(c.skippedDraws, lastCounters.skippedDraws), delta(c.pipelineWaitSkips, lastCounters.pipelineWaitSkips),
            delta(c.pipelinesMade, lastCounters.pipelinesMade), delta(c.textureCreateFailures, lastCounters.textureCreateFailures),
            "\(c.textureBytes / 1_048_576)", "\(c.bcTextureBytes / 1_048_576)", "\(c.metalAllocatedBytes / 1_048_576)",
            "\(tier.metalWorkingSetMB)", "\(PGEngineMemoryLimitMB())", "\(PGVideoMemoryBudgetMB())",
            delta(reliefs, lastReliefs), delta(evictions, lastEvictions), delta(clamps, lastClamps),
            ProcessInfo.processInfo.isLowPowerModeEnabled ? "1" : "0", delta(c.backgroundHolds, lastCounters.backgroundHolds),
            "\(PGFreeAddressSpaceMB())"
        ]
        lastCounters = c
        lastReliefs = reliefs; lastEvictions = evictions; lastClamps = clamps
        return fields
    }

    private func removeOldLogs(in folder: URL, keeping count: Int) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
        let logs = files.filter { $0.lastPathComponent.hasPrefix("perf-") && $0.pathExtension == "csv" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in logs.dropFirst(count) { try? FileManager.default.removeItem(at: old) }
    }

    /// The app's physical footprint and what iOS still allows before a memory kill, in MB.
    private static func memoryMB() -> (Int, Int) {
        var vm = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        let footprint = result == KERN_SUCCESS ? Int(vm.phys_footprint) / 1_048_576 : 0
        return (footprint, Int(os_proc_available_memory()) / 1_048_576)
    }
}
