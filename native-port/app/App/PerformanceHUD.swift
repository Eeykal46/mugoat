import UIKit
import os

/// In-game performance overlay (Settings › Graphics › Performance Overlay; a tap cycles the modes).
/// Original is the app's first FPS label (kept by the owner's choice); Compact, Card and Detailed add the
/// frame time, the app's memory against its iOS limit, the phone's memory, the heat level iOS reports,
/// the battery and, in Detailed, a frame-time graph, CPU and GPU time.
///
/// iOS gives apps no temperature in degrees, only four heat levels (ProcessInfo.thermalState): the
/// overlay shows the level and its colour.
enum PerformanceOverlayMode: String, CaseIterable {
    case off, original, compact, card, detailed
    var title: String {
        switch self {
        case .off: return "Off"
        case .original: return "Original FPS"
        case .compact: return "Compact"
        case .card: return "Card"
        case .detailed: return "Detailed"
        }
    }
    /// The tap order: Off is only chosen in Settings.
    var next: PerformanceOverlayMode {
        switch self {
        case .off, .detailed: return .original
        case .original: return .compact
        case .compact: return .card
        case .card: return .detailed
        }
    }
}

/// One reading of everything the overlay shows.
struct PerformanceReading {
    var fps: Double = 0
    var frameMs: Double = 0
    var lowFPS: Double = 0			// 1% low over the frames held
    var frames: [Float] = []		// recent frame intervals, oldest first
    var gpuMs: Double = 0
    var cpuPercent: Double = 0		// of all cores
    var appMB = 0, appLimitMB = 0
    var phoneUsedMB = 0, phoneTotalMB = 0
    var thermal = ProcessInfo.ThermalState.nominal
    var battery: Float = -1			// 0...1, -1 unknown
    var charging = false
    var lowPower = false
    var targetMs = 1000.0 / 30

    static func read(targetFPS: Double) -> PerformanceReading {
        var r = PerformanceReading()
        r.targetMs = 1000 / max(1, targetFPS)
        r.fps = PGRenderedFramesPerSecond()
        var buffer = [Float](repeating: 0, count: 300)
        var gpu = 0.0
        let count = Int(PGHUDFrameTimes(&buffer, Int32(buffer.count), &gpu))
        r.frames = Array(buffer.prefix(count))
        r.gpuMs = gpu
        let recent = r.frames.suffix(120)
        if !recent.isEmpty {
            r.frameMs = Double(recent.reduce(0, +)) / Double(recent.count)
            let sorted = recent.sorted()
            let p99 = Double(sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.99))])
            r.lowFPS = p99 > 0 ? 1000 / p99 : 0
        }
        r.cpuPercent = Self.cpuPercent()
        var info = task_vm_info_data_t()
        var count32 = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count32)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count32) }
        }
        if kr == KERN_SUCCESS {
            let footprint = Int(info.phys_footprint / 1_048_576)
            r.appMB = footprint
            r.appLimitMB = footprint + Int(os_proc_available_memory() / 1_048_576)
        }
        (r.phoneUsedMB, r.phoneTotalMB) = Self.phoneMemory()
        r.thermal = ProcessInfo.processInfo.thermalState
        r.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let device = UIDevice.current
        if !device.isBatteryMonitoringEnabled { device.isBatteryMonitoringEnabled = true }
        r.battery = device.batteryLevel
        r.charging = device.batteryState == .charging || device.batteryState == .full
        return r
    }

    /// The app's CPU time over the last call, as a share of all cores.
    private static var lastCPU: (time: Double, at: CFTimeInterval)?
    private static func cpuPercent() -> Double {
        var threads: thread_act_array_t?
        var threadCount = mach_msg_type_number_t(0)
        guard task_threads(mach_task_self_, &threads, &threadCount) == KERN_SUCCESS, let threads else { return 0 }
        defer {
            for i in 0..<Int(threadCount) { mach_port_deallocate(mach_task_self_, threads[i]) }
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threads)), vm_size_t(Int(threadCount) * MemoryLayout<thread_t>.stride))
        }
        var total = 0.0
        for i in 0..<Int(threadCount) {
            var basic = thread_basic_info()
            var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<natural_t>.size)
            let kr = withUnsafeMutablePointer(to: &basic) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &count) }
            }
            guard kr == KERN_SUCCESS else { continue }
            total += Double(basic.user_time.seconds) + Double(basic.user_time.microseconds) / 1e6
            total += Double(basic.system_time.seconds) + Double(basic.system_time.microseconds) / 1e6
        }
        let now = CACurrentMediaTime()
        defer { lastCPU = (total, now) }
        guard let last = lastCPU, now > last.at, total >= last.time else { return 0 }
        let cores = Double(max(1, ProcessInfo.processInfo.activeProcessorCount))
        return min(100, (total - last.time) / (now - last.at) / cores * 100)
    }

    /// mach_host_self() adds a reference to the host port at every call; the overlay asks twice a second.
    private static let host = mach_host_self()
    private static let pageSize: UInt64 = {
        var size = vm_size_t(0)
        return host_page_size(host, &size) == KERN_SUCCESS && size > 0 ? UInt64(size) : 16384
    }()

    /// The phone's memory in use (everything but free, inactive and speculative pages) and its RAM.
    private static func phoneMemory() -> (Int, Int) {
        let total = Int(ProcessInfo.processInfo.physicalMemory / 1_048_576)
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(host, HOST_VM_INFO64, $0, &count) }
        }
        guard kr == KERN_SUCCESS else { return (0, total) }
        let available = (UInt64(stats.free_count) + UInt64(stats.inactive_count) + UInt64(stats.speculative_count)) * pageSize
        let used = max(0, total - Int(available / 1_048_576))
        return (used, total)
    }
}

final class PerformanceHUD: UIView {
    var mode: PerformanceOverlayMode = .card { didSet { if mode != oldValue { rebuild() } } }
    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let stack = UIStackView()
    private var labels: [String: UILabel] = [:]
    private var bars: [String: MeterBar] = [:]
    private let graph = FrameGraph()
    private var widthConstraint: NSLayoutConstraint?

    static let green = UIColor(red: 61 / 255, green: 220 / 255, blue: 132 / 255, alpha: 1)
    static let yellow = UIColor(red: 1, green: 210 / 255, blue: 63 / 255, alpha: 1)
    static let orange = UIColor(red: 1, green: 159 / 255, blue: 28 / 255, alpha: 1)
    static let red = UIColor(red: 1, green: 46 / 255, blue: 77 / 255, alpha: 1)

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 12
        layer.borderWidth = 1
        layer.borderColor = UIColor(white: 1, alpha: 0.12).cgColor
        clipsToBounds = true
        backgroundColor = UIColor(red: 12 / 255, green: 10 / 255, blue: 14 / 255, alpha: 0.55)
        blur.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blur)
        stack.axis = .vertical
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            blur.leadingAnchor.constraint(equalTo: leadingAnchor), blur.trailingAnchor.constraint(equalTo: trailingAnchor),
            blur.topAnchor.constraint(equalTo: topAnchor), blur.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10), stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 7), stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
        rebuild()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Building

    private func label(_ key: String, size: CGFloat, mono: Bool = true, alpha: CGFloat = 1, weight: UIFont.Weight = .regular) -> UILabel {
        let l = UILabel()
        l.font = mono ? LoadingFonts.mono(size) : .systemFont(ofSize: size, weight: weight)
        l.textColor = UIColor(white: 1, alpha: alpha)
        l.adjustsFontSizeToFitWidth = true
        l.minimumScaleFactor = 0.7
        labels[key] = l
        return l
    }
    private func row(_ views: [UIView], spacing: CGFloat = 6) -> UIStackView {
        let s = UIStackView(arrangedSubviews: views)
        s.axis = .horizontal
        s.spacing = spacing
        s.alignment = .firstBaseline
        return s
    }
    private func spread(_ a: UIView, _ b: UIView) -> UIStackView {
        let s = UIStackView(arrangedSubviews: [a, UIView(), b])
        s.axis = .horizontal
        s.alignment = .center
        return s
    }
    private func meter(_ key: String, title: String) -> UIView {
        let name = label(key + "Title", size: 7.5, alpha: 0.55)
        name.text = title
        let value = label(key, size: 7.5)
        let bar = MeterBar()
        bars[key] = bar
        let box = UIStackView(arrangedSubviews: [spread(name, value), bar])
        box.axis = .vertical
        box.spacing = 3
        bar.heightAnchor.constraint(equalToConstant: 3).isActive = true
        return box
    }

    private func rebuild() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        labels.removeAll(); bars.removeAll()
        widthConstraint?.isActive = false
        switch mode {
        case .off, .original:
            isHidden = true
            return
        case .compact:
            stack.spacing = 2
            stack.addArrangedSubview(row([label("fpsBig", size: 13, mono: false, weight: .heavy), label("fpsUnit", size: 9.5), label("ms", size: 9.5, alpha: 0.55),
                                          label("temp", size: 9.5)]))
            stack.addArrangedSubview(row([label("ramLine", size: 9.5)]))
            widthConstraint = nil
        case .card:
            stack.spacing = 5
            stack.addArrangedSubview(spread(row([label("fpsBig", size: 22, mono: false, weight: .heavy), label("fpsUnit", size: 9, alpha: 0.75)], spacing: 4),
                                            label("ms", size: 9, alpha: 0.6)))
            stack.addArrangedSubview(meter("app", title: "APP RAM"))
            stack.addArrangedSubview(meter("phone", title: "PHONE RAM"))
            stack.addArrangedSubview(spread(label("temp", size: 8.5), label("bat", size: 8.5, alpha: 0.75)))
            widthConstraint = widthAnchor.constraint(equalToConstant: 150)
        case .detailed:
            stack.spacing = 0
            let left = UIStackView(arrangedSubviews: [row([label("fpsBig", size: 21, mono: false, weight: .heavy), label("fpsUnit", size: 8, alpha: 0.75)], spacing: 4),
                                                      label("ms", size: 6.8, alpha: 0.6), graph, label("graphTitle", size: 6.5, alpha: 0.5)])
            left.axis = .vertical
            left.spacing = 3
            graph.heightAnchor.constraint(equalToConstant: 30).isActive = true
            labels["graphTitle"]?.text = "FRAME TIME · 10 s"
            left.widthAnchor.constraint(equalToConstant: 84).isActive = true
            let right = UIStackView(arrangedSubviews: [spread(label("cpu", size: 8), label("gpu", size: 8)), meter("app", title: "APP"), meter("phone", title: "PHONE"),
                                                       label("temp", size: 8), spread(label("bat", size: 7.5, alpha: 0.75), label("lowPower", size: 7.5, alpha: 0.75))])
            right.axis = .vertical
            right.spacing = 4
            let columns = UIStackView(arrangedSubviews: [left, right])
            columns.axis = .horizontal
            columns.spacing = 9
            columns.alignment = .top
            stack.addArrangedSubview(columns)
            widthConstraint = widthAnchor.constraint(equalToConstant: 212)
        }
        widthConstraint?.isActive = true
        isHidden = false
        labels["fpsUnit"]?.text = "FPS"
    }

    // MARK: - Values

    func show(_ r: PerformanceReading) {
        guard mode != .off, mode != .original else { return }
        labels["fpsBig"]?.text = r.fps > 0 ? String(format: "%.0f", r.fps) : "—"
        switch mode {
        case .compact: labels["ms"]?.text = String(format: "%.1f ms", r.frameMs)
        case .detailed: labels["ms"]?.text = String(format: "%.1fms · 1%% LOW %.0f", r.frameMs, r.lowFPS)
        default: labels["ms"]?.text = String(format: "%.1f ms", r.frameMs)
        }
        let appShare = r.appLimitMB > 0 ? Double(r.appMB) / Double(r.appLimitMB) : 0
        let phoneShare = r.phoneTotalMB > 0 ? Double(r.phoneUsedMB) / Double(r.phoneTotalMB) : 0
        if mode == .compact {
            let text = NSMutableAttributedString(string: "APP ", attributes: [.foregroundColor: UIColor.white])
            text.append(NSAttributedString(string: "\(r.appMB)", attributes: [.foregroundColor: Self.level(appShare)]))
            text.append(NSAttributedString(string: "/\(r.appLimitMB) · RAM \(r.phoneUsedMB)/\(r.phoneTotalMB)", attributes: [.foregroundColor: UIColor.white]))
            labels["ramLine"]?.attributedText = text
        } else {
            labels["app"]?.text = "\(r.appMB)/\(r.appLimitMB) MB"
            labels["phone"]?.text = "\(r.phoneUsedMB)/\(r.phoneTotalMB) MB"
            bars["app"]?.set(appShare, color: Self.level(appShare))
            bars["phone"]?.set(phoneShare, color: Self.level(phoneShare))
        }
        labels["temp"]?.attributedText = Self.temperature(r.thermal, prefix: mode != .compact)
        if r.battery >= 0 { labels["bat"]?.text = String(format: "BAT %.0f%%%@", r.battery * 100, r.charging ? " ⚡︎" : "") } else { labels["bat"]?.text = "BAT —" }
        labels["lowPower"]?.text = r.lowPower ? "LOW PWR ON" : "LOW PWR OFF"
        labels["cpu"]?.text = String(format: "CPU %.0f%%", r.cpuPercent)
        labels["gpu"]?.text = String(format: "GPU %.1fms", r.gpuMs)
        if mode == .detailed { graph.set(frames: Array(r.frames.suffix(150)), targetMs: r.targetMs) }
    }

    static func level(_ share: Double) -> UIColor { share < 0.7 ? green : share < 0.85 ? yellow : share < 0.95 ? orange : red }

    static func temperature(_ state: ProcessInfo.ThermalState, prefix: Bool) -> NSAttributedString {
        let (name, color): (String, UIColor) = {
            switch state {
            case .nominal: return ("NORMAL", green)
            case .fair: return ("WARM", yellow)
            case .serious: return ("HOT", orange)
            case .critical: return ("CRITICAL", red)
            @unknown default: return ("—", .white)
            }
        }()
        let text = NSMutableAttributedString(string: "● ", attributes: [.foregroundColor: color])
        if prefix { text.append(NSAttributedString(string: "TEMP ", attributes: [.foregroundColor: UIColor.white])) }
        text.append(NSAttributedString(string: name, attributes: [.foregroundColor: color]))
        return text
    }
}

/// A thin filled bar (memory against its total).
final class MeterBar: UIView {
    private let fill = UIView()
    private var share: CGFloat = 0
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 1, alpha: 0.14)
        layer.cornerRadius = 1.5
        clipsToBounds = true
        addSubview(fill)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    func set(_ value: Double, color: UIColor) {
        share = CGFloat(min(1, max(0, value)))
        fill.backgroundColor = color
        setNeedsLayout()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        fill.frame = CGRect(x: 0, y: 0, width: bounds.width * share, height: bounds.height)
    }
}

/// Frame intervals as a line, with the frame-rate target dashed.
final class FrameGraph: UIView {
    private var frames: [Float] = []
    private var targetMs = 33.3
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 1, alpha: 0.05)
        layer.cornerRadius = 4
        isOpaque = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    func set(frames: [Float], targetMs: Double) {
        self.frames = frames
        self.targetMs = targetMs
        setNeedsDisplay()
    }
    override func draw(_ rect: CGRect) {
        let top = max(targetMs * 2.2, 50)		// the graph's scale: a little over twice the target
        func y(_ ms: Double) -> CGFloat { bounds.height - CGFloat(min(ms, top) / top) * (bounds.height - 2) - 1 }
        let target = UIBezierPath()
        target.move(to: CGPoint(x: 0, y: y(targetMs))); target.addLine(to: CGPoint(x: bounds.width, y: y(targetMs)))
        target.setLineDash([2, 3], count: 2, phase: 0)
        target.lineWidth = 1
        PerformanceHUD.green.withAlphaComponent(0.45).setStroke()
        target.stroke()
        guard frames.count > 1 else { return }
        let line = UIBezierPath()
        let step = bounds.width / CGFloat(frames.count - 1)
        for (i, ms) in frames.enumerated() {
            let point = CGPoint(x: CGFloat(i) * step, y: y(Double(ms)))
            if i == 0 { line.move(to: point) } else { line.addLine(to: point) }
        }
        line.lineWidth = 1.2
        line.lineJoinStyle = .round
        PerformanceHUD.red.setStroke()
        line.stroke()
    }
}
