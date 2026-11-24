import Foundation
import Metal
import UIKit
import os

/// Graphics presets. The engine reads quality settings once at boot; only the
/// resolution can change while it runs.
enum GraphicsPreset: Int, CaseIterable {
    case battery, performance, balanced, quality, ultra, max

    var title: String { [L10n.text("Tiết kiệm pin"), L10n.text("Ưu tiên mượt"), L10n.text("Cân bằng"), L10n.text("Rõ nét"), L10n.text("Cao"), L10n.text("Tối đa (4K)")][rawValue] }
    /// Render height in pixels; width follows the screen's shape.
    var height: Int { [432, 540, 720, 900, 1080, 2160][rawValue] }
    var detail: String {
        [L10n.text("432p · ít tốn RAM và pin"), L10n.text("540p · giảm hiệu ứng nặng"), L10n.text("720p · cân bằng hình ảnh và tốc độ"),
         L10n.text("900p · tăng chi tiết và khoảng nhìn"), L10n.text("1080p · bóng và phản chiếu cao"),
         L10n.text("2160p (4K) · chi tiết đồ họa tối đa (Native 4K)")][rawValue]
    }

    /// Engine command-line options. Shader quality never goes below 1 (the
    /// low shader set is mostly missing), and must not exceed 1 (Quality 2 shaders
    /// are not compiled for Metal). Tessellation, MSAA and depth of field stay off.
    var engineOptions: [String] {
        switch self {
        case .battery, .performance:
            return ["-shaderQuality=1", "-textureQuality=0", "-shadowQuality=-1", "-reflectionQuality=0", "-particleQuality=0",
                    "-grassQuality=0", "-cityDensity=0", "-lodScale=0", "-pedLodBias=0", "-vehicleLodBias=0", "-pedVariety=0", "-vehicleVariety=0"]
        case .balanced:
            return ["-shaderQuality=1", "-textureQuality=0", "-shadowQuality=0", "-reflectionQuality=0", "-particleQuality=0",
                    "-grassQuality=0", "-cityDensity=0.2", "-lodScale=0.2", "-pedLodBias=0", "-vehicleLodBias=0", "-pedVariety=0.2", "-vehicleVariety=0.2"]
        case .quality:
            return ["-shaderQuality=1", "-textureQuality=1", "-shadowQuality=0", "-reflectionQuality=1", "-particleQuality=1",
                    "-grassQuality=1", "-cityDensity=0.4", "-lodScale=0.4", "-pedLodBias=0.2", "-vehicleLodBias=0.2", "-pedVariety=0.4", "-vehicleVariety=0.4"]
        case .ultra:
            return ["-shaderQuality=1", "-textureQuality=1", "-shadowQuality=1", "-reflectionQuality=1", "-particleQuality=1",
                    "-grassQuality=1", "-cityDensity=0.6", "-lodScale=0.6", "-pedLodBias=0.4", "-vehicleLodBias=0.4", "-pedVariety=0.6", "-vehicleVariety=0.6"]
        case .max:
            return ["-shaderQuality=1", "-textureQuality=1", "-shadowQuality=1", "-reflectionQuality=2", "-particleQuality=1",
                    "-grassQuality=1", "-cityDensity=0.8", "-lodScale=0.8", "-pedLodBias=0.5", "-vehicleLodBias=0.5", "-pedVariety=0.8", "-vehicleVariety=0.8"]
        }
    }
}

/// What this device can afford, measured before the engine starts.
struct DeviceTier {
    /// Measured OS process allowance for diagnostics; never an allocation cap.
    let processAllowanceMB: Int
    let physicalMemoryMB: Int
    let model: String
    let supportsBCTextures: Bool
    /// The GPU as Metal names it ("Apple A15 GPU") and its Apple GPU family (4 is A11 ... 9 is A17 and
    /// newer; 0 unknown). Families below 7 have no sampler border colours (edges clamp instead).
    let gpuName: String
    let gpuFamily: Int
    /// Metal's recommended GPU working set in MB (reported from iOS 16; 0 before).
    let metalWorkingSetMB: Int
    let systemVersion: String

    static func probe() -> DeviceTier {
        var info = utsname(); uname(&info)
        let model = withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        let device = MTLCreateSystemDefaultDevice()
        let supportsBC: Bool
        if #available(iOS 16.4, *) { supportsBC = device?.supportsBCTextureCompression ?? false }
        else { supportsBC = false }
        var family = 0, workingSet = 0
        if let device {
            // Raw values (Apple3 is 1003 ... Apple9 is 1009); newer families are only asked on the iOS that knows them.
            var families: [Int] = [7, 6, 5, 4, 3]
            if #available(iOS 16.0, *) { families.insert(8, at: 0) }
            if #available(iOS 17.0, *) { families.insert(9, at: 0) }
            family = families.first { raw in MTLGPUFamily(rawValue: 1000 + raw).map { device.supportsFamily($0) } ?? false } ?? 0
            if #available(iOS 16.0, *) { workingSet = Int(device.recommendedMaxWorkingSetSize / 1_048_576) }
        }
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return DeviceTier(processAllowanceMB: Self.measureProcessAllowanceMB(),
                          physicalMemoryMB: Int(ProcessInfo.processInfo.physicalMemory / 1_048_576),
                          model: model,
                          supportsBCTextures: supportsBC,
                          gpuName: device?.name ?? "No Metal GPU",
                          gpuFamily: family,
                          metalWorkingSetMB: workingSet,
                          systemVersion: version.patchVersion > 0 ? "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)" : "\(version.majorVersion).\(version.minorVersion)")
    }

    /// Jetsam limit = memory still available + what the app already uses.
    private static func measureProcessAllowanceMB() -> Int {
        var vm = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        let footprint = result == KERN_SUCCESS ? Int(vm.phys_footprint) : 0
        return (Int(os_proc_available_memory()) + footprint) / 1_048_576
    }

    /// The memory iOS lets this app use (its memory limit), in MB; 0 when unknown (simulator).
    var appMemoryLimitMB: Int {
        #if targetEnvironment(simulator)
        return 0
        #else
        return processAllowanceMB > 256 ? processAllowanceMB : 0
        #endif
    }
    /// Recommend from the device's RAM, lowered when iOS gives this app less than such a phone usually
    /// gets (4 GB phones, or a signing that drops the larger memory limit); all presets remain selectable.
    var recommended: GraphicsPreset {
        let byRAM: GraphicsPreset = physicalMemoryMB < 3400 ? .battery : physicalMemoryMB < 4600 ? .performance : physicalMemoryMB < 6000 ? .balanced : physicalMemoryMB < 8000 ? .quality : physicalMemoryMB < 12000 ? .ultra : .max
        let limit = appMemoryLimitMB
        guard limit > 0 else { return byRAM }
        let byLimit: GraphicsPreset = limit < 2300 ? .battery : limit < 2900 ? .performance : .max
        return byLimit.rawValue < byRAM.rawValue ? byLimit : byRAM
    }
    /// Whether GTA V fits in what iOS lets this app use. On the iPhone 13 Pro (3072 MB limit) the world
    /// took about 2.3-2.4 GB at Balanced; the two lines below are first estimates, to be tuned from
    /// logs of other phones. Without a measured limit, about half the RAM is assumed.
    enum Support: String { case ok, limited, low }
    var support: Support {
        #if targetEnvironment(simulator)
        return .ok
        #else
        let limit = appMemoryLimitMB > 0 ? appMemoryLimitMB : physicalMemoryMB / 2
        return limit < 1900 ? .low : limit < 2900 ? .limited : .ok
        #endif
    }
    /// "3.0 GB"
    static func gigabytes(_ mb: Int) -> String { String(format: "%.1f GB", Double(mb) / 1024) }
    var gpuSummary: String {
        "\(gpuName)\(gpuFamily > 0 ? " · Apple\(gpuFamily)" : "") · " + (supportsBCTextures ? "BC textures native" : "BC textures decoded")
    }
    var memoryLimitSummary: String {
        let limit = appMemoryLimitMB
        let app = limit > 0 ? Self.gigabytes(limit) + " of \(marketedMemoryGB) GB" : "unknown"
        return metalWorkingSetMB > 0 ? app + " · GPU budget " + Self.gigabytes(metalWorkingSetMB) : app
    }
    /// One line for the log: everything the support decision and the preset rest on.
    var checkLine: String {
        "Device check: \(displayName) (\(model)), iOS \(systemVersion), \(gpuName) (Apple GPU family \(gpuFamily), " +
        (supportsBCTextures ? "BC native" : "BC decoded") + "), RAM \(physicalMemoryMB) MB, iOS app limit \(appMemoryLimitMB) MB, " +
        "Metal working set \(metalWorkingSetMB) MB -> \(support.rawValue), recommended \(recommended.title)"
    }
    /// Every preset can be chosen; those above the recommended one show a warning.
    var allowed: [GraphicsPreset] { GraphicsPreset.allCases }
    /// Presets shown with a warning because they may run out of memory or heat up.
    func risky(_ preset: GraphicsPreset) -> Bool { preset.rawValue > recommended.rawValue }
    /// Marketing name for the hardware identifier (iPhone14,2 is an iPhone 13 Pro); the identifier when unknown.
    var displayName: String {
        // Hardware identifier -> name (Apple identifiers; listed at everymac.com and appledb.dev).
        let names: [String: String] = [
            "iPhone8,1": "iPhone 6s", "iPhone8,2": "iPhone 6s Plus", "iPhone8,4": "iPhone SE (1st gen)",
            "iPhone9,1": "iPhone 7", "iPhone9,3": "iPhone 7", "iPhone9,2": "iPhone 7 Plus",
            "iPhone9,4": "iPhone 7 Plus", "iPhone10,1": "iPhone 8", "iPhone10,4": "iPhone 8",
            "iPhone10,2": "iPhone 8 Plus", "iPhone10,5": "iPhone 8 Plus", "iPhone10,3": "iPhone X",
            "iPhone10,6": "iPhone X", "iPhone11,2": "iPhone XS", "iPhone11,4": "iPhone XS Max",
            "iPhone11,6": "iPhone XS Max", "iPhone11,8": "iPhone XR", "iPhone12,1": "iPhone 11",
            "iPhone12,3": "iPhone 11 Pro", "iPhone12,5": "iPhone 11 Pro Max", "iPhone12,8": "iPhone SE (2nd gen)",
            "iPhone13,1": "iPhone 12 mini", "iPhone13,2": "iPhone 12", "iPhone13,3": "iPhone 12 Pro",
            "iPhone13,4": "iPhone 12 Pro Max", "iPhone14,4": "iPhone 13 mini", "iPhone14,5": "iPhone 13",
            "iPhone14,2": "iPhone 13 Pro", "iPhone14,3": "iPhone 13 Pro Max", "iPhone14,6": "iPhone SE (3rd gen)",
            "iPhone14,7": "iPhone 14", "iPhone14,8": "iPhone 14 Plus", "iPhone15,2": "iPhone 14 Pro",
            "iPhone15,3": "iPhone 14 Pro Max", "iPhone15,4": "iPhone 15", "iPhone15,5": "iPhone 15 Plus",
            "iPhone16,1": "iPhone 15 Pro", "iPhone16,2": "iPhone 15 Pro Max", "iPhone17,1": "iPhone 16 Pro",
            "iPhone17,2": "iPhone 16 Pro Max", "iPhone17,3": "iPhone 16", "iPhone17,4": "iPhone 16 Plus",
            "iPhone17,5": "iPhone 16e", "iPhone18,1": "iPhone 17 Pro", "iPhone18,2": "iPhone 17 Pro Max",
            "iPhone18,3": "iPhone 17", "iPhone18,4": "iPhone Air", "iPhone18,5": "iPhone 17e",
            "iPod9,1": "iPod touch (7th gen)", "iPad6,11": "iPad (5th gen)", "iPad6,12": "iPad (5th gen)",
            "iPad7,5": "iPad (6th gen)", "iPad7,6": "iPad (6th gen)", "iPad7,11": "iPad (7th gen)",
            "iPad7,12": "iPad (7th gen)", "iPad11,6": "iPad (8th gen)", "iPad11,7": "iPad (8th gen)",
            "iPad12,1": "iPad (9th gen)", "iPad12,2": "iPad (9th gen)", "iPad13,18": "iPad (10th gen)",
            "iPad13,19": "iPad (10th gen)", "iPad15,7": "iPad (A16)", "iPad15,8": "iPad (A16)",
            "iPad5,3": "iPad Air 2", "iPad5,4": "iPad Air 2", "iPad11,3": "iPad Air (3rd gen)",
            "iPad11,4": "iPad Air (3rd gen)", "iPad13,1": "iPad Air (4th gen)", "iPad13,2": "iPad Air (4th gen)",
            "iPad13,16": "iPad Air (5th gen)", "iPad13,17": "iPad Air (5th gen)", "iPad14,8": "iPad Air 11-inch (M2)",
            "iPad14,9": "iPad Air 11-inch (M2)", "iPad14,10": "iPad Air 13-inch (M2)", "iPad14,11": "iPad Air 13-inch (M2)",
            "iPad15,3": "iPad Air 11-inch (M3)", "iPad15,4": "iPad Air 11-inch (M3)", "iPad15,5": "iPad Air 13-inch (M3)",
            "iPad15,6": "iPad Air 13-inch (M3)", "iPad16,8": "iPad Air 11-inch (M4)", "iPad16,9": "iPad Air 11-inch (M4)",
            "iPad16,10": "iPad Air 13-inch (M4)", "iPad16,11": "iPad Air 13-inch (M4)", "iPad5,1": "iPad mini 4",
            "iPad5,2": "iPad mini 4", "iPad11,1": "iPad mini (5th gen)", "iPad11,2": "iPad mini (5th gen)",
            "iPad14,1": "iPad mini (6th gen)", "iPad14,2": "iPad mini (6th gen)", "iPad16,1": "iPad mini (A17 Pro)",
            "iPad16,2": "iPad mini (A17 Pro)", "iPad6,3": "iPad Pro 9.7-inch", "iPad6,4": "iPad Pro 9.7-inch",
            "iPad6,7": "iPad Pro 12.9-inch", "iPad6,8": "iPad Pro 12.9-inch", "iPad7,1": "iPad Pro 12.9-inch (2nd gen)",
            "iPad7,2": "iPad Pro 12.9-inch (2nd gen)", "iPad7,3": "iPad Pro 10.5-inch", "iPad7,4": "iPad Pro 10.5-inch",
            "iPad8,1": "iPad Pro 11-inch", "iPad8,2": "iPad Pro 11-inch", "iPad8,3": "iPad Pro 11-inch",
            "iPad8,4": "iPad Pro 11-inch", "iPad8,5": "iPad Pro 12.9-inch (3rd gen)", "iPad8,6": "iPad Pro 12.9-inch (3rd gen)",
            "iPad8,7": "iPad Pro 12.9-inch (3rd gen)", "iPad8,8": "iPad Pro 12.9-inch (3rd gen)", "iPad8,9": "iPad Pro 11-inch (2nd gen)",
            "iPad8,10": "iPad Pro 11-inch (2nd gen)", "iPad8,11": "iPad Pro 12.9-inch (4th gen)", "iPad8,12": "iPad Pro 12.9-inch (4th gen)",
            "iPad13,4": "iPad Pro 11-inch (3rd gen)", "iPad13,5": "iPad Pro 11-inch (3rd gen)", "iPad13,6": "iPad Pro 11-inch (3rd gen)",
            "iPad13,7": "iPad Pro 11-inch (3rd gen)", "iPad13,8": "iPad Pro 12.9-inch (5th gen)", "iPad13,9": "iPad Pro 12.9-inch (5th gen)",
            "iPad13,10": "iPad Pro 12.9-inch (5th gen)", "iPad13,11": "iPad Pro 12.9-inch (5th gen)", "iPad14,3": "iPad Pro 11-inch (4th gen)",
            "iPad14,4": "iPad Pro 11-inch (4th gen)", "iPad14,5": "iPad Pro 12.9-inch (6th gen)", "iPad14,6": "iPad Pro 12.9-inch (6th gen)",
            "iPad16,3": "iPad Pro 11-inch (M4)", "iPad16,4": "iPad Pro 11-inch (M4)", "iPad16,5": "iPad Pro 13-inch (M4)",
            "iPad16,6": "iPad Pro 13-inch (M4)", "iPad17,1": "iPad Pro 11-inch (M5)", "iPad17,2": "iPad Pro 11-inch (M5)",
            "iPad17,3": "iPad Pro 13-inch (M5)", "iPad17,4": "iPad Pro 13-inch (M5)"
        ]
        if let name = names[model] { return name }
        if model == "x86_64" || model == "arm64" { return "Simulator" }
        // A newer model than this list: the family and the identifier, e.g. "iPhone (iPhone19,1)".
        let family = model.prefix { $0.isLetter }
        return family.isEmpty ? model : "\(family) (\(model))"
    }
    /// Installed RAM as sold (iOS reports a little less: 5.5 GB on a 6 GB iPhone).
    var marketedMemoryGB: Int {
        let gb = Double(physicalMemoryMB) / 1024
        return [2, 3, 4, 6, 8, 12, 16, 24].first { Double($0) >= gb - 0.05 } ?? Int(gb.rounded())
    }
    var summary: String { "\(displayName) · \(marketedMemoryGB) GB RAM\(supportsBCTextures ? " · BC textures" : "")" }
}

enum GraphicsConfiguration {
    /// The screen's height in pixels (the "Native" resolution).
    static var nativeHeight: Int {
        let screen = UIScreen.main
        let raw = Int(min(screen.nativeBounds.width, screen.nativeBounds.height))
        return raw > 0 ? raw : 720
    }
    /// Resolutions offered in Settings, besides "Auto" (the detail preset's own).
    static var resolutionChoices: [Int] {
        let standard = [540, 720, 900, 1080, 1290, 1440, 1620, 2160]
        var list = standard
        if !list.contains(nativeHeight) && nativeHeight >= 540 {
            list.append(nativeHeight)
        }
        list.sort()
        return list
    }
    /// The render height for this session: the chosen one, or in frame-rate Auto with resolution Auto the
    /// height this phone was learned to sustain (never above the preset's), or the preset's (0).
    static func effectiveRenderHeight(_ settings: GameSettings) -> Int {
        guard settings.renderHeight == 0, settings.frameRateAuto else { return settings.renderHeight }
        let learned = AutoTune.shared.learnedHeight
        return learned > 0 ? min(learned, settings.graphicsPreset.height) : 0
    }
    /// Width/height to render at: the chosen height (or the preset's), shaped like the screen so the
    /// picture is not stretched.
    static func size(for preset: GraphicsPreset, renderHeight: Int, screen: CGSize, matchScreenShape: Bool) -> (Int, Int) {
        let aspect = matchScreenShape && screen.height > 0 ? max(screen.width, screen.height) / min(screen.width, screen.height) : 16.0 / 9.0
        var height = Double(renderHeight > 0 ? renderHeight : preset.height)
        height = min(max(height, 360), 2160.0)
        let width = min(height * aspect, 3840.0)
        func even(_ value: Double) -> Int { Int(value.rounded()) & ~1 }
        return (max(even(width), 320), max(even(height), 240))
    }

    /// Pass the chosen settings to the engine. Call before PGStartEngine.
    static func apply(_ settings: GameSettings, screen: CGSize) -> String {
        PGSetEngineMemoryMB(Int32(settings.engineMemoryMB))
        let preset = settings.graphicsPreset
        let (width, height) = size(for: preset, renderHeight: effectiveRenderHeight(settings), screen: screen, matchScreenShape: settings.matchScreenShape)
        let options = preset.engineOptions
        var pointers = options.map { strdup($0) }
        defer { pointers.forEach { free($0) } }
        pointers.withUnsafeMutableBufferPointer { buffer in
            buffer.baseAddress!.withMemoryRebound(to: UnsafePointer<CChar>?.self, capacity: buffer.count) {
                PGConfigureEngine($0, UInt32(buffer.count), Int32(width), Int32(height), GameSettings.frameLimitCode(settings.effectiveFrameRateCap))
            }
        }
        // Even frame pacing when the cap is below the screen's refresh rate (30 on 60 Hz, 30/60 on 120 Hz).
        let cap = settings.effectiveFrameRateCap
        PGSetPresentPacing(settings.framePacing && cap > 0 && cap < UIScreen.main.maximumFramesPerSecond ? 1.0 / Double(cap) : 0)
        // Resolution floor 1000‰: auto-smooth changes only the frame cap. A live back-buffer resize during
        // play crashed in the engine's ResizeBuffers (SIGSEGV, iPhone 13 Pro, 1558×720 → 1246×576), so the
        // governor must not resize until that path is fixed.
        PGSmoothConfigure(GameSettings.frameLimitCode(cap), Double(UIScreen.main.maximumFramesPerSecond), 1000)
        return "\(preset.title) \(width)×\(height) at " + (settings.frameRateAuto ? "Auto (up to \(UIScreen.main.maximumFramesPerSecond) FPS)" : GameSettings.frameRateTitle(settings.frameRateCap))
    }
}
