import AVFoundation
import ImageIO
import SwiftUI
import UIKit

/// Obsidian-style live preview for the formatted editor: YAML frontmatter
/// shows as a Properties panel and embed lines (`![[clip.wav]]`,
/// `![](photo.jpg)`) as a player or viewer. The Markdown itself is never
/// changed; a block shows its source again while the caret is inside it.
enum MarkdownRichBlocks {
    struct Property: Equatable {
        var key: String
        var values: [String]
    }

    struct Frontmatter: Equatable {
        /// From the opening `---` through the closing `---` (no trailing newline).
        var range: NSRange
        /// The closing `---` line, which carries the room for the panel.
        var closingLineRange: NSRange
        var properties: [Property]
    }

    enum EmbedKind: Equatable {
        case audio, image, video

        init?(path: String) {
            switch (path as NSString).pathExtension.lowercased() {
            case "wav", "m4a", "mp3", "aac", "caf", "aif", "aiff", "flac", "ogg": self = .audio
            case "png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "tif", "tiff", "bmp": self = .image
            case "mov", "mp4", "m4v", "webm": self = .video
            default: return nil
            }
        }
    }

    struct Embed: Equatable {
        /// The whole line holding only the embed (no newline).
        var range: NSRange
        var target: String
        var kind: EmbedKind
    }

    static func frontmatter(in string: NSString) -> Frontmatter? {
        guard string.length >= 3, string.hasPrefix("---") else { return nil }
        let firstLine = string.lineRange(for: NSRange(location: 0, length: 0))
        guard string.substring(with: firstLine).trimmingCharacters(in: .whitespacesAndNewlines) == "---" else {
            return nil
        }
        var location = NSMaxRange(firstLine)
        var bodyLines: [String] = []
        while location < string.length {
            let line = string.lineRange(for: NSRange(location: location, length: 0))
            let text = string.substring(with: line).trimmingCharacters(in: .newlines)
            if text.trimmingCharacters(in: .whitespaces) == "---" {
                var closing = line
                if string.substring(with: closing).hasSuffix("\n") { closing.length -= 1 }
                return Frontmatter(
                    range: NSRange(location: 0, length: NSMaxRange(closing)),
                    closingLineRange: closing,
                    properties: properties(fromYAMLLines: bodyLines)
                )
            }
            bodyLines.append(text)
            location = NSMaxRange(line)
        }
        return nil
    }

    /// The small YAML subset notes use: `key: value`, `key: [a, b]`, and
    /// `key:` followed by `- item` lines.
    static func properties(fromYAMLLines lines: [String]) -> [Property] {
        var result: [Property] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            if trimmed.hasPrefix("- "), !result.isEmpty {
                result[result.count - 1].values.append(unquote(String(trimmed.dropFirst(2))))
                continue
            }
            guard let colon = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
            let raw = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            var values: [String] = []
            if raw.hasPrefix("["), raw.hasSuffix("]") {
                values = raw.dropFirst().dropLast().split(separator: ",")
                    .map { unquote(String($0).trimmingCharacters(in: .whitespaces)) }
                    .filter { !$0.isEmpty }
            } else if !raw.isEmpty {
                values = [unquote(raw)]
            }
            result.append(Property(key: key, values: values))
        }
        return result
    }

    private static func unquote(_ value: String) -> String {
        var value = value
        if value.count >= 2, let first = value.first, first == value.last, first == "\"" || first == "'" {
            value = String(value.dropFirst().dropLast())
        }
        return value
    }

    private static let wikiEmbed = try! NSRegularExpression(pattern: #"^\s*!\[\[([^\]|#]+)(?:[|#][^\]]*)?\]\]\s*$"#)
    private static let markdownEmbed = try! NSRegularExpression(pattern: #"^\s*!\[[^\]]*\]\(<?([^)>]+?)>?\)\s*$"#)

    /// Embed lines (an embed alone on its line) for audio, images and video.
    static func embeds(in string: NSString) -> [Embed] {
        var result: [Embed] = []
        var location = 0
        while location < string.length {
            let line = string.lineRange(for: NSRange(location: location, length: 0))
            var content = line
            if string.substring(with: content).hasSuffix("\n") { content.length -= 1 }
            let text = string.substring(with: content)
            let local = NSRange(location: 0, length: (text as NSString).length)
            for pattern in [wikiEmbed, markdownEmbed] {
                guard let match = pattern.firstMatch(in: text, range: local),
                      let targetRange = Range(match.range(at: 1), in: text) else { continue }
                let target = String(text[targetRange]).trimmingCharacters(in: .whitespaces)
                    .removingPercentEncoding ?? String(text[targetRange])
                if let kind = EmbedKind(path: target) {
                    result.append(Embed(range: content, target: target, kind: kind))
                }
                break
            }
            location = NSMaxRange(line)
        }
        return result
    }

    /// Obsidian keeps a block as source while the caret is on it.
    static func isRevealed(_ block: NSRange, by selection: NSRange) -> Bool {
        let end = NSMaxRange(block)
        if selection.length == 0 {
            return selection.location >= block.location && selection.location <= end
        }
        return NSIntersectionRange(block, selection).length > 0
            || (selection.location <= block.location && NSMaxRange(selection) >= end)
    }
}

// MARK: - Views

/// Shared card chrome for embed and properties widgets.
class MarkdownRichCardView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(Geist.card)
        layer.cornerRadius = 14
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = UIColor(Geist.border).cgColor
        clipsToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        layer.borderColor = UIColor(Geist.border).cgColor
    }

    static func label(_ size: CGFloat, weight: UIFont.Weight = .regular, mono: Bool = false, color: Color = Geist.text) -> UILabel {
        let label = UILabel()
        let name = mono ? "GeistMono-Regular" : (weight == .semibold ? "Geist-SemiBold" : "Geist-Regular")
        label.font = UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)
        label.textColor = UIColor(color)
        label.adjustsFontForContentSizeCategory = false
        return label
    }
}

/// `![[clip.wav]]` as a player: play/pause, progress and duration.
final class MarkdownAudioEmbedView: MarkdownRichCardView {
    static let height: CGFloat = 64
    private let button = UIButton(type: .system)
    private let nameLabel = MarkdownRichCardView.label(13, weight: .semibold)
    private let timeLabel = MarkdownRichCardView.label(11.5, mono: true, color: Geist.muted)
    private let track = UIView()
    private let fill = UIView()
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var url: URL?
    private var fraction: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        button.tintColor = .white
        button.backgroundColor = UIColor(Geist.accent)
        button.layer.cornerRadius = 20
        button.addTarget(self, action: #selector(toggle), for: .touchUpInside)
        track.backgroundColor = UIColor(Geist.well)
        track.layer.cornerRadius = 2
        fill.backgroundColor = UIColor(Geist.accent)
        fill.layer.cornerRadius = 2
        track.addSubview(fill)
        [button, nameLabel, timeLabel, track].forEach(addSubview)
        updateButton()
        isAccessibilityElement = false
        button.accessibilityIdentifier = "markdown_audio_embed_play"
    }

    func configure(target: String, url: URL?) {
        nameLabel.text = (target as NSString).lastPathComponent
        guard url != self.url else { return }
        self.url = url
        stop()
        player = url.flatMap { try? AVAudioPlayer(contentsOf: $0) }
        player?.prepareToPlay()
        button.isEnabled = player != nil
        timeLabel.text = player.map { Self.format($0.duration) } ?? String(localized: "File not found")
        fraction = 0
        updateButton()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        button.frame = CGRect(x: 12, y: (bounds.height - 40) / 2, width: 40, height: 40)
        let textX: CGFloat = 64
        let width = bounds.width - textX - 14
        let timeWidth = ceil(timeLabel.sizeThatFits(CGSize(width: 200, height: 18)).width)
        timeLabel.frame = CGRect(x: bounds.width - 14 - timeWidth, y: 12, width: timeWidth, height: 18)
        nameLabel.frame = CGRect(x: textX, y: 12, width: max(0, timeLabel.frame.minX - textX - 8), height: 18)
        timeLabel.textAlignment = .right
        track.frame = CGRect(x: textX, y: 40, width: width, height: 4)
        fill.frame = CGRect(x: 0, y: 0, width: width * fraction, height: 4)
    }

    @objc private func toggle() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            timer?.invalidate()
        } else {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try? AVAudioSession.sharedInstance().setActive(true)
            player.play()
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.tick()
            }
        }
        updateButton()
    }

    private func tick() {
        guard let player else { return }
        fraction = player.duration > 0 ? CGFloat(player.currentTime / player.duration) : 0
        timeLabel.text = "\(Self.format(player.currentTime)) / \(Self.format(player.duration))"
        if !player.isPlaying {
            timer?.invalidate()
            fraction = 0
            timeLabel.text = Self.format(player.duration)
            updateButton()
        }
        setNeedsLayout()
    }

    func stop() {
        player?.stop()
        timer?.invalidate()
        timer = nil
    }

    private func updateButton() {
        let playing = player?.isPlaying == true
        button.setImage(UIImage(systemName: playing ? "pause.fill" : "play.fill"), for: .normal)
        button.accessibilityLabel = playing
            ? String(localized: "Pause \(nameLabel.text ?? "")")
            : String(localized: "Play \(nameLabel.text ?? "")")
    }

    private static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    override func removeFromSuperview() {
        stop()
        super.removeFromSuperview()
    }
}

/// `![[photo.jpg]]` as an image viewer, downsampled to the card's width.
final class MarkdownImageEmbedView: MarkdownRichCardView {
    static let maximumHeight: CGFloat = 280
    private let imageView = UIImageView()
    private let missing = MarkdownRichCardView.label(12, mono: true, color: Geist.muted)
    private(set) var url: URL?
    var aspectRatio: CGFloat?
    var onAspectRatioChange: ((CGFloat) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = UIColor(Geist.well)
        imageView.isAccessibilityElement = true
        missing.textAlignment = .center
        missing.numberOfLines = 2
        addSubview(imageView)
        addSubview(missing)
    }

    func configure(target: String, url: URL?) {
        imageView.accessibilityLabel = (target as NSString).lastPathComponent
        guard url != self.url else { return }
        self.url = url
        imageView.image = nil
        missing.text = url == nil ? String(localized: "\((target as NSString).lastPathComponent) not found") : nil
        guard let url else { return }
        let maxPixel = max(UIScreen.main.bounds.width, 400) * UIScreen.main.scale
        Task.detached(priority: .utility) {
            let image = Self.downsample(url, maxPixel: maxPixel)
            await MainActor.run { [weak self] in
                guard let self, self.url == url, let image else { return }
                self.imageView.image = image
                let ratio = image.size.height / max(image.size.width, 1)
                if self.aspectRatio != ratio {
                    self.aspectRatio = ratio
                    self.onAspectRatioChange?(ratio)
                }
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        missing.frame = bounds.insetBy(dx: 12, dy: 8)
    }

    nonisolated static func downsample(_ url: URL, maxPixel: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// `![[clip.mov]]` as a video viewer: tap to play or pause.
final class MarkdownVideoEmbedView: MarkdownRichCardView {
    static let height: CGFloat = 220
    private let playerLayer = AVPlayerLayer()
    private let button = UIButton(type: .system)
    private let missing = MarkdownRichCardView.label(12, mono: true, color: Geist.muted)
    private var player: AVPlayer?
    private var url: URL?
    private var endObserver: NSObjectProtocol?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspect
        layer.addSublayer(playerLayer)
        button.tintColor = .white
        button.setImage(UIImage(systemName: "play.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)), for: .normal)
        button.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        button.layer.cornerRadius = 28
        button.addTarget(self, action: #selector(toggle), for: .touchUpInside)
        button.accessibilityIdentifier = "markdown_video_embed_play"
        missing.textAlignment = .center
        missing.textColor = .lightGray
        addSubview(missing)
        addSubview(button)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(toggle)))
    }

    func configure(target: String, url: URL?) {
        button.accessibilityLabel = String(localized: "Play \((target as NSString).lastPathComponent)")
        guard url != self.url else { return }
        self.url = url
        player?.pause()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        player = url.map { AVPlayer(url: $0) }
        playerLayer.player = player
        button.isHidden = player == nil
        missing.text = url == nil ? String(localized: "\((target as NSString).lastPathComponent) not found") : nil
        if let item = player?.currentItem {
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
            ) { [weak self] _ in
                self?.player?.seek(to: .zero)
                self?.button.isHidden = false
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
        button.frame = CGRect(x: (bounds.width - 56) / 2, y: (bounds.height - 56) / 2, width: 56, height: 56)
        missing.frame = bounds.insetBy(dx: 12, dy: 8)
    }

    @objc private func toggle() {
        guard let player else { return }
        if player.timeControlStatus == .playing {
            player.pause()
            button.isHidden = false
        } else {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            player.play()
            button.isHidden = true
        }
    }

    override func removeFromSuperview() {
        player?.pause()
        super.removeFromSuperview()
    }
}

/// YAML frontmatter as Obsidian's Properties panel. Tapping it shows the YAML.
final class MarkdownPropertiesView: MarkdownRichCardView {
    static let headerHeight: CGFloat = 34
    static let rowHeight: CGFloat = 30
    var onTap: (() -> Void)?
    private var rows: [UIView] = []
    private let header = MarkdownRichCardView.label(10.5, weight: .semibold, color: Geist.muted)

    static func height(for properties: [MarkdownRichBlocks.Property]) -> CGFloat {
        headerHeight + CGFloat(max(properties.count, 1)) * rowHeight + 8
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(Geist.Palette.gray100)
        header.attributedText = NSAttributedString(
            string: String(localized: "PROPERTIES"),
            attributes: [.kern: 0.8, .font: header.font!, .foregroundColor: UIColor(Geist.muted)]
        )
        addSubview(header)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityHint = String(localized: "Shows the YAML to edit it")
        accessibilityIdentifier = "markdown_properties"
    }

    @objc private func tapped() { onTap?() }

    func configure(_ properties: [MarkdownRichBlocks.Property]) {
        rows.forEach { $0.removeFromSuperview() }
        rows = properties.map(Self.row(for:))
        rows.forEach(addSubview)
        accessibilityLabel = String(localized: "Properties") + ", " + properties
            .map { "\($0.key): \($0.values.joined(separator: ", "))" }
            .joined(separator: "; ")
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        header.frame = CGRect(x: 14, y: 10, width: bounds.width - 28, height: 16)
        for (index, row) in rows.enumerated() {
            row.frame = CGRect(
                x: 14, y: Self.headerHeight + CGFloat(index) * Self.rowHeight,
                width: bounds.width - 28, height: Self.rowHeight
            )
            row.setNeedsLayout()
        }
    }

    private static func row(for property: MarkdownRichBlocks.Property) -> UIView {
        let row = MarkdownPropertyRowView()
        row.key.text = property.key
        row.chips = property.values.map { value in
            let chip = MarkdownRichCardView.label(12.5, color: property.values.count > 1 || property.key == "tags" ? Geist.accentText : Geist.text)
            chip.text = property.key == "tags" && !value.hasPrefix("#") ? "#\(value)" : value
            if property.values.count > 1 || property.key == "tags" {
                chip.backgroundColor = UIColor(Geist.accentSoft)
                chip.layer.cornerRadius = 8
                chip.clipsToBounds = true
                chip.textAlignment = .center
            }
            return chip
        }
        row.chips.forEach(row.addSubview)
        return row
    }
}

private final class MarkdownPropertyRowView: UIView {
    let key = MarkdownRichCardView.label(12.5, mono: true, color: Geist.muted)
    var chips: [UILabel] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(key)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let keyWidth = min(110, bounds.width * 0.32)
        key.frame = CGRect(x: 0, y: 5, width: keyWidth, height: 20)
        var x = keyWidth + 8
        for chip in chips {
            let isPill = chip.backgroundColor != nil
            let width = min(chip.intrinsicContentSize.width + (isPill ? 14 : 0), bounds.width - x)
            guard width > 8 else { chip.isHidden = true; continue }
            chip.isHidden = false
            chip.frame = CGRect(x: x, y: isPill ? 4 : 5, width: width, height: isPill ? 22 : 20)
            x += width + 6
        }
    }
}
