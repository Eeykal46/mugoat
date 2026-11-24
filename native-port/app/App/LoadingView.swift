import UIKit
import CoreText

/// The loading screen while the game boots: design B "Skyline", chosen by the owner. The city image
/// darkened, the logo and mode at the top, the percentage with its stage on the left, a tip card on the
/// right and a 30-segment bar. It is native (the web launcher is closed during loading to free its memory)
/// and owns one image; it is removed once the 3D world shows.
///
/// The engine only reports two points (first frame, world ready), so the percentage follows the boot's
/// log milestones and, while the city loads, the time this phone needed last time.
final class LoadingView: UIView {
    enum Stage: Int, Comparable {
        case starting, graphics, files, city, ready
        static func < (a: Stage, b: Stage) -> Bool { a.rawValue < b.rawValue }
        var title: String {
            switch self {
            case .starting: return "STARTING ENGINE"
            case .graphics: return "PREPARING GRAPHICS"
            case .files: return "LOADING GAME FILES"
            case .city: return "BUILDING THE CITY"
            case .ready: return "READY"
            }
        }
        var detail: String {
            switch self {
            case .starting: return "Memulakan enjin permainan."
            case .graphics: return "Menyediakan grafik untuk GPU telefon kau."
            case .files: return "Membaca fail game, audio dan skrip."
            case .city: return "Membina jalan, bangunan dan trafik di sekeliling kau."
            case .ready: return "Selamat datang ke Malay City."
            }
        }
        /// Where the percentage stands when the stage begins.
        var percent: Double {
            switch self {
            case .starting: return 4
            case .graphics: return 14
            case .files: return 24
            case .city: return 36
            case .ready: return 100
            }
        }
    }

    static let red = UIColor(red: 1, green: 46 / 255, blue: 77 / 255, alpha: 1)
    private static let cityKey = "MCLoadingCitySeconds"
    private static let builtInTips = [
        "Polis akan kejar lebih lama kalau kau langgar kereta mereka. Lari ke lorong kecil untuk hilangkan bintang.",
        "Tekan butang radio untuk tukar stesen semasa memandu.",
        "Hidupkan Auto Smooth di Settings › Graphics supaya FPS kekal stabil bila telefon panas.",
        "Keluar dari kawasan carian merah dan bersembunyi sampai bintang polis hilang.",
        "Simpan permainan di rumah selamat sebelum keluar dari app.",
        "Ubah susun atur butang di Settings › Controls › Edit Controls Layout.",
        "Kalau telefon cepat panas, pilih preset Smooth atau Battery Saver.",
        "Pause When Leaving buka menu pause bila kau keluar dari app."
    ]

    private let background = UIImageView()
    private let shade = CAGradientLayer()
    private let scanlines = UIView()
    private let logo = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let chip = UIView()
    private let chipDot = UIView()
    private let chipLabel = UILabel()
    private let percentLabel = UILabel()
    private let stageLabel = UILabel()
    private let detailLabel = UILabel()
    private let tipCard = UIView()
    private let tipMask = CAShapeLayer()
    private let tipHeader = UILabel()
    private let tipLabel = UILabel()
    private let bar = SegmentBar(count: 30)

    private var stage: Stage = .starting
    private var shown: Double = 0
    private var target: Double = Stage.starting.percent
    private var cityStarted: CFTimeInterval?
    private var tips: [String]
    private var tipIndex = 0
    private var ticker: Timer?
    private var tipTimer: Timer?
    private var failed = false

    init(mode: String, tips extra: [String]) {
        tips = (extra.filter { !$0.isEmpty } + Self.builtInTips)
        super.init(frame: .zero)
        backgroundColor = UIColor(red: 5 / 255, green: 3 / 255, blue: 5 / 255, alpha: 1)
        clipsToBounds = true
        build(mode: mode)
        apply(stage: .starting)
        tipIndex = Int.random(in: 0..<tips.count)
        tipLabel.text = tips[tipIndex]
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, ticker == nil, !failed {
            ticker = Timer.scheduledTimer(withTimeInterval: 1.0 / 20, repeats: true) { [weak self] _ in self?.tick() }
            tipTimer = Timer.scheduledTimer(withTimeInterval: 7, repeats: true) { [weak self] _ in self?.nextTip() }
        } else if window == nil {
            stopTimers()
        }
    }

    /// Moves to a later stage (earlier ones are ignored, so log order does not matter).
    func advance(to next: Stage) {
        guard !failed, next > stage else { return }
        if next == .city { cityStarted = CACurrentMediaTime() }
        if next == .ready, let started = cityStarted {
            // Remember how long the city took on this phone (smoothed) for the next loading screen.
            let measured = CACurrentMediaTime() - started
            let previous = UserDefaults.standard.double(forKey: Self.cityKey)
            UserDefaults.standard.set(previous > 0 ? previous * 0.6 + measured * 0.4 : measured, forKey: Self.cityKey)
        }
        apply(stage: next)
    }

    func showError(_ text: String) {
        failed = true
        stopTimers()
        setStageText("COULD NOT START", color: Self.red)
        detailLabel.text = text
        bar.setFilled(bar.filled, color: UIColor(white: 1, alpha: 0.35))
    }

    func stopTimers() {
        ticker?.invalidate(); ticker = nil
        tipTimer?.invalidate(); tipTimer = nil
    }

    // MARK: - Progress

    private func apply(stage next: Stage) {
        stage = next
        target = max(target, next.percent)
        setStageText(next.title, color: .white)
        detailLabel.text = next.detail
    }

    private func tick() {
        if stage == .city, let started = cityStarted {
            // 36% to 97%: about 95% when the time this phone needed last time has passed (60 s at first).
            let expected = max(15, UserDefaults.standard.double(forKey: Self.cityKey).nonZero ?? 60)
            let t = CACurrentMediaTime() - started
            target = max(target, Stage.city.percent + 61 * (1 - exp(-3 * t / expected)))
        } else if stage < .city {
            // Creep inside the stage so the bar never looks stuck (never past the next stage's start).
            let ceiling = Stage(rawValue: stage.rawValue + 1)?.percent ?? 100
            target = min(max(target, target + 0.04), ceiling - 1)
        }
        let step = max(0.15, (target - shown) * 0.12)
        let next = min(target, shown + step)
        guard Int(next) != Int(shown) || shown == 0 else { shown = next; return }
        shown = next
        let value = Int(shown.rounded(.down))
        percentLabel.attributedText = percentText(value)
        bar.setFilled(Int((Double(bar.count) * shown / 100).rounded(.down)), color: Self.red)
    }

    private func nextTip() {
        guard tips.count > 1 else { return }
        tipIndex = (tipIndex + 1) % tips.count
        UIView.transition(with: tipLabel, duration: 0.35, options: .transitionCrossDissolve) {
            self.tipLabel.text = self.tips[self.tipIndex]
        }
    }

    // MARK: - Layout

    private func build(mode: String) {
        if let url = Bundle.main.url(forResource: "bg", withExtension: "jpg", subdirectory: "Launcher/media") {
            background.image = UIImage(contentsOfFile: url.path)
        }
        background.contentMode = .scaleAspectFill
        shade.colors = [UIColor(red: 5 / 255, green: 3 / 255, blue: 5 / 255, alpha: 0.55), UIColor(red: 5 / 255, green: 3 / 255, blue: 5 / 255, alpha: 0.1),
                        UIColor(red: 5 / 255, green: 3 / 255, blue: 5 / 255, alpha: 0.75), UIColor(red: 5 / 255, green: 3 / 255, blue: 5 / 255, alpha: 1)].map(\.cgColor)
        shade.locations = [0, 0.35, 0.68, 1]
        scanlines.backgroundColor = UIColor(patternImage: Self.scanlinePattern())
        scanlines.isUserInteractionEnabled = false

        if let url = Bundle.main.url(forResource: "logo", withExtension: "png", subdirectory: "Launcher/media") {
            logo.image = UIImage(contentsOfFile: url.path)
        }
        logo.image = logo.image ?? UIImage(named: "LaunchLogo")
        logo.contentMode = .scaleAspectFit

        let title = NSMutableAttributedString(string: "MALAY ", attributes: [.font: LoadingFonts.display(17), .foregroundColor: UIColor.white, .kern: 1.4])
        title.append(NSAttributedString(string: "CITY", attributes: [.font: LoadingFonts.display(17), .foregroundColor: Self.red, .kern: 1.4]))
        titleLabel.attributedText = title
        subtitleLabel.attributedText = NSAttributedString(string: "YOUR CITY. YOUR STORY.", attributes: [.font: LoadingFonts.mono(8), .foregroundColor: UIColor(white: 1, alpha: 0.62), .kern: 1.6])

        chip.layer.borderWidth = 1
        chip.layer.borderColor = Self.red.withAlphaComponent(0.5).cgColor
        chip.backgroundColor = Self.red.withAlphaComponent(0.1)
        chipDot.backgroundColor = Self.red
        chipDot.layer.cornerRadius = 3
        chipDot.layer.shadowColor = Self.red.cgColor
        chipDot.layer.shadowRadius = 4
        chipDot.layer.shadowOpacity = 1
        chipDot.layer.shadowOffset = .zero
        let modeName = ["story": "STORY MODE", "freeroam": "FREE ROAM", "online": "ONLINE"][mode] ?? "STORY MODE"
        chipLabel.attributedText = NSAttributedString(string: modeName, attributes: [.font: LoadingFonts.mono(9), .foregroundColor: UIColor.white, .kern: 1.6])

        percentLabel.attributedText = percentText(0)
        detailLabel.font = .systemFont(ofSize: 10, weight: .regular)
        detailLabel.textColor = UIColor(white: 1, alpha: 0.62)
        detailLabel.numberOfLines = 2

        tipCard.backgroundColor = UIColor(red: 10 / 255, green: 6 / 255, blue: 10 / 255, alpha: 0.72)
        tipCard.layer.mask = tipMask
        let edge = UIView()
        edge.backgroundColor = Self.red
        tipHeader.attributedText = NSAttributedString(string: "// DID YOU KNOW", attributes: [.font: LoadingFonts.mono(8.5), .foregroundColor: Self.red, .kern: 1.6])
        tipLabel.font = .systemFont(ofSize: 10.5, weight: .regular)
        tipLabel.textColor = UIColor(white: 0.93, alpha: 1)
        tipLabel.numberOfLines = 4

        for view in [background, scanlines, logo, titleLabel, subtitleLabel, chip, percentLabel, stageLabel, detailLabel, tipCard, bar] as [UIView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        layer.insertSublayer(shade, above: background.layer)
        for view in [chipDot, chipLabel] as [UIView] { view.translatesAutoresizingMaskIntoConstraints = false; chip.addSubview(view) }
        for view in [edge, tipHeader, tipLabel] as [UIView] { view.translatesAutoresizingMaskIntoConstraints = false; tipCard.addSubview(view) }

        // Content area: the safe area, at least 28 pt from the screen edge, on every iPhone and iPad.
        let content = UILayoutGuide()
        addLayoutGuide(content)
        let safe = safeAreaLayoutGuide
        let leadingSafe = content.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 4); leadingSafe.priority = .defaultHigh
        let trailingSafe = content.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -4); trailingSafe.priority = .defaultHigh
        let tipWidth = tipCard.widthAnchor.constraint(equalToConstant: 250); tipWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: leadingAnchor), background.trailingAnchor.constraint(equalTo: trailingAnchor),
            background.topAnchor.constraint(equalTo: topAnchor), background.bottomAnchor.constraint(equalTo: bottomAnchor),
            scanlines.leadingAnchor.constraint(equalTo: leadingAnchor), scanlines.trailingAnchor.constraint(equalTo: trailingAnchor),
            scanlines.topAnchor.constraint(equalTo: topAnchor), scanlines.bottomAnchor.constraint(equalTo: bottomAnchor),

            leadingSafe, trailingSafe,
            content.leadingAnchor.constraint(greaterThanOrEqualTo: safe.leadingAnchor, constant: 4),
            content.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 28),
            content.trailingAnchor.constraint(lessThanOrEqualTo: safe.trailingAnchor, constant: -4),
            content.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -28),
            content.topAnchor.constraint(equalTo: safe.topAnchor, constant: 20),
            content.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -10),

            logo.leadingAnchor.constraint(equalTo: content.leadingAnchor), logo.topAnchor.constraint(equalTo: content.topAnchor),
            logo.widthAnchor.constraint(equalToConstant: 40), logo.heightAnchor.constraint(equalToConstant: 40),
            titleLabel.leadingAnchor.constraint(equalTo: logo.trailingAnchor, constant: 10), titleLabel.topAnchor.constraint(equalTo: logo.topAnchor, constant: 3),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor), subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),

            chip.trailingAnchor.constraint(equalTo: content.trailingAnchor), chip.centerYAnchor.constraint(equalTo: logo.centerYAnchor, constant: -6),
            chipDot.leadingAnchor.constraint(equalTo: chip.leadingAnchor, constant: 9), chipDot.centerYAnchor.constraint(equalTo: chip.centerYAnchor),
            chipDot.widthAnchor.constraint(equalToConstant: 6), chipDot.heightAnchor.constraint(equalToConstant: 6),
            chipLabel.leadingAnchor.constraint(equalTo: chipDot.trailingAnchor, constant: 7), chipLabel.trailingAnchor.constraint(equalTo: chip.trailingAnchor, constant: -10),
            chipLabel.topAnchor.constraint(equalTo: chip.topAnchor, constant: 4), chipLabel.bottomAnchor.constraint(equalTo: chip.bottomAnchor, constant: -4),

            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor), bar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: content.bottomAnchor), bar.heightAnchor.constraint(equalToConstant: 6),

            tipCard.trailingAnchor.constraint(equalTo: content.trailingAnchor), tipCard.bottomAnchor.constraint(equalTo: bar.topAnchor, constant: -26),
            tipWidth, tipCard.widthAnchor.constraint(lessThanOrEqualTo: content.widthAnchor, multiplier: 0.42),
            edge.leadingAnchor.constraint(equalTo: tipCard.leadingAnchor), edge.topAnchor.constraint(equalTo: tipCard.topAnchor),
            edge.bottomAnchor.constraint(equalTo: tipCard.bottomAnchor), edge.widthAnchor.constraint(equalToConstant: 2),
            tipHeader.leadingAnchor.constraint(equalTo: tipCard.leadingAnchor, constant: 13), tipHeader.topAnchor.constraint(equalTo: tipCard.topAnchor, constant: 11),
            tipLabel.leadingAnchor.constraint(equalTo: tipHeader.leadingAnchor), tipLabel.trailingAnchor.constraint(equalTo: tipCard.trailingAnchor, constant: -13),
            tipLabel.topAnchor.constraint(equalTo: tipHeader.bottomAnchor, constant: 5), tipLabel.bottomAnchor.constraint(equalTo: tipCard.bottomAnchor, constant: -11),
            tipLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),

            detailLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor), detailLabel.bottomAnchor.constraint(equalTo: tipCard.bottomAnchor),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: tipCard.leadingAnchor, constant: -16),
            stageLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor), stageLabel.bottomAnchor.constraint(equalTo: detailLabel.topAnchor, constant: -3),
            stageLabel.trailingAnchor.constraint(lessThanOrEqualTo: tipCard.leadingAnchor, constant: -16),
            percentLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: -2), percentLabel.bottomAnchor.constraint(equalTo: stageLabel.topAnchor, constant: -4)
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        shade.frame = bounds
        let size = tipCard.bounds.size, cut: CGFloat = 10
        let path = UIBezierPath()
        path.move(to: CGPoint(x: cut, y: 0)); path.addLine(to: CGPoint(x: size.width, y: 0))
        path.addLine(to: CGPoint(x: size.width, y: size.height - cut)); path.addLine(to: CGPoint(x: size.width - cut, y: size.height))
        path.addLine(to: CGPoint(x: 0, y: size.height)); path.addLine(to: CGPoint(x: 0, y: cut)); path.close()
        tipMask.path = path.cgPath
        CATransaction.commit()
    }

    private func percentText(_ value: Int) -> NSAttributedString {
        let text = NSMutableAttributedString(string: "\(value)", attributes: [.font: LoadingFonts.display(54), .foregroundColor: UIColor.white])
        text.append(NSAttributedString(string: "%", attributes: [.font: LoadingFonts.display(24), .foregroundColor: Self.red]))
        return text
    }

    private func setStageText(_ text: String, color: UIColor) {
        stageLabel.attributedText = NSAttributedString(string: text, attributes: [.font: LoadingFonts.mono(11), .foregroundColor: color, .kern: 2.2])
    }

    private static func scanlinePattern() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 1, height: 3), format: format).image { context in
            UIColor(white: 1, alpha: 0.03).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
    }
}

/// The 30-segment progress bar; the last filled segment glows.
private final class SegmentBar: UIView {
    let count: Int
    private(set) var filled = 0
    private var segments: [CALayer] = []
    private var color = LoadingView.red

    init(count: Int) {
        self.count = count
        super.init(frame: .zero)
        for _ in 0..<count {
            let segment = CALayer()
            segment.shadowColor = LoadingView.red.cgColor
            segment.shadowRadius = 5
            segment.shadowOffset = .zero
            layer.addSublayer(segment)
            segments.append(segment)
        }
        paint()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func setFilled(_ value: Int, color newColor: UIColor) {
        let value = min(count, max(0, value))
        guard value != filled || newColor != color else { return }
        filled = value
        color = newColor
        paint()
    }

    private func paint() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for (index, segment) in segments.enumerated() {
            segment.backgroundColor = index < filled ? color.cgColor : UIColor(white: 1, alpha: 0.12).cgColor
            segment.shadowOpacity = index == filled - 1 && filled < count ? 1 : 0
        }
        CATransaction.commit()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let gap: CGFloat = 3
        let width = (bounds.width - gap * CGFloat(count - 1)) / CGFloat(count)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for (index, segment) in segments.enumerated() {
            segment.frame = CGRect(x: CGFloat(index) * (width + gap), y: 0, width: max(1, width), height: bounds.height)
        }
        CATransaction.commit()
    }
}

/// The launcher's display and mono fonts (Tektur, Share Tech Mono; SIL Open Font License), converted to
/// TrueType at build time (Scripts/make_fonts.py). System fonts stand in when they are missing.
enum LoadingFonts {
    private static let displayName: String? = register("MCTektur")
    private static let monoName: String? = register("MCShareTechMono")

    static func display(_ size: CGFloat) -> UIFont {
        displayName.flatMap { UIFont(name: $0, size: size) } ?? .systemFont(ofSize: size, weight: .black)
    }
    static func mono(_ size: CGFloat) -> UIFont {
        monoName.flatMap { UIFont(name: $0, size: size) } ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    private static func register(_ file: String) -> String? {
        guard let url = Bundle.main.url(forResource: file, withExtension: "ttf") else { return nil }
        _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let first = descriptors.first,
              let name = CTFontDescriptorCopyAttribute(first, kCTFontNameAttribute) as? String else { return nil }
        return name
    }
}

private extension Double {
    var nonZero: Double? { self > 0 ? self : nil }
}
