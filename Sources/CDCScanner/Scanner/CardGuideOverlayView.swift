#if os(iOS)
import UIKit

/// Dims the camera preview, cuts out a card-shaped window and hosts the on-screen controls.
@MainActor
final class CardGuideOverlayView: UIView {
    var onCancel: (() -> Void)?
    var onToggleTorch: (() -> Void)?

    /// Standard ID-1 card aspect ratio (85.60 mm × 53.98 mm).
    static let cardAspectRatio: CGFloat = 85.60 / 53.98

    private let configuration: ScannerConfiguration
    private let dimLayer = CAShapeLayer()
    private let strokeLayer = CAShapeLayer()
    private let titleLabel = UILabel()
    private let instructionsLabel = UILabel()
    private let cancelButton = UIButton(type: .system)
    private let torchButton = UIButton(type: .system)

    init(configuration: ScannerConfiguration) {
        self.configuration = configuration
        super.init(frame: .zero)
        backgroundColor = .clear
        isAccessibilityElement = false
        setUpLayers()
        setUpControls()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CardGuideOverlayView does not support storyboards.")
    }

    /// The card window, in this view's coordinate space. Depends only on bounds and safe area.
    var guideRect: CGRect {
        Self.guideRect(in: bounds, safeAreaInsets: safeAreaInsets)
    }

    static func guideRect(in bounds: CGRect, safeAreaInsets: UIEdgeInsets) -> CGRect {
        let content = bounds.inset(by: safeAreaInsets)
        let horizontalMargin: CGFloat = 24
        var width = min(content.width - horizontalMargin * 2, 440)
        var height = width / cardAspectRatio
        let maxHeight = content.height * 0.5
        if height > maxHeight {
            height = maxHeight
            width = height * cardAspectRatio
        }
        let x = content.midX - width / 2
        // Sit a little above centre so the instructions and the user's thumbs have room.
        let y = content.midY - height / 2 - content.height * 0.06
        return CGRect(x: x, y: y, width: width, height: height).integral
    }

    func setTorchButtonHidden(_ hidden: Bool) {
        torchButton.isHidden = hidden
    }

    func setTorchActive(_ active: Bool) {
        let symbol = active ? "bolt.fill" : "bolt.slash.fill"
        torchButton.setImage(UIImage(systemName: symbol), for: .normal)
        torchButton.accessibilityValue = active ? "On" : "Off"
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let guide = configuration.showsCardGuide ? guideRect : .null
        let path = UIBezierPath(rect: bounds)
        if !guide.isNull {
            path.append(UIBezierPath(roundedRect: guide, cornerRadius: guide.height * 0.06))
        }
        dimLayer.frame = bounds
        dimLayer.path = path.cgPath
        strokeLayer.frame = bounds
        strokeLayer.path = guide.isNull ? nil : UIBezierPath(roundedRect: guide, cornerRadius: guide.height * 0.06).cgPath

        let content = bounds.inset(by: safeAreaInsets)
        let controlSize: CGFloat = 44
        cancelButton.frame = CGRect(x: content.minX + 12, y: content.minY + 8, width: controlSize, height: controlSize)
        torchButton.frame = CGRect(x: content.maxX - 12 - controlSize, y: content.minY + 8, width: controlSize, height: controlSize)

        let titleSize = titleLabel.sizeThatFits(CGSize(width: content.width - 140, height: controlSize))
        titleLabel.frame = CGRect(
            x: content.midX - titleSize.width / 2,
            y: content.minY + 8 + (controlSize - titleSize.height) / 2,
            width: titleSize.width,
            height: titleSize.height
        )

        let instructionsWidth = content.width - 48
        let instructionsSize = instructionsLabel.sizeThatFits(CGSize(width: instructionsWidth, height: .greatestFiniteMagnitude))
        let instructionsY = guide.isNull ? content.maxY - instructionsSize.height - 32 : guide.maxY + 24
        instructionsLabel.frame = CGRect(
            x: content.midX - instructionsWidth / 2,
            y: instructionsY,
            width: instructionsWidth,
            height: instructionsSize.height
        )
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // Only the buttons take touches; everything else passes through to the camera view.
        let view = super.hitTest(point, with: event)
        return view is UIControl ? view : nil
    }

    private func setUpLayers() {
        dimLayer.fillRule = .evenOdd
        dimLayer.fillColor = UIColor.black.withAlphaComponent(0.55).cgColor
        layer.addSublayer(dimLayer)

        strokeLayer.fillColor = nil
        strokeLayer.strokeColor = UIColor.white.cgColor
        strokeLayer.lineWidth = 3
        layer.addSublayer(strokeLayer)
    }

    private func setUpControls() {
        titleLabel.text = configuration.title
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.accessibilityTraits = .header
        addSubview(titleLabel)

        instructionsLabel.text = configuration.instructions
        instructionsLabel.font = .preferredFont(forTextStyle: .body)
        instructionsLabel.textColor = .white
        instructionsLabel.textAlignment = .center
        instructionsLabel.numberOfLines = 0
        addSubview(instructionsLabel)

        configure(cancelButton, symbol: "xmark", label: "Cancel")
        cancelButton.addAction(UIAction { [weak self] _ in self?.onCancel?() }, for: .touchUpInside)
        addSubview(cancelButton)

        configure(torchButton, symbol: "bolt.slash.fill", label: "Torch")
        torchButton.isHidden = !configuration.showsTorchButton
        torchButton.addAction(UIAction { [weak self] _ in self?.onToggleTorch?() }, for: .touchUpInside)
        addSubview(torchButton)
    }

    private func configure(_ button: UIButton, symbol: String, label: String) {
        var config = UIButton.Configuration.filled()
        config.image = UIImage(systemName: symbol)
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        config.baseBackgroundColor = UIColor.black.withAlphaComponent(0.5)
        config.baseForegroundColor = .white
        config.cornerStyle = .capsule
        button.configuration = config
        button.accessibilityLabel = label
    }
}
#endif
