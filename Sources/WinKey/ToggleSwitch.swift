import AppKit

/// 自绘的滑动开关。
///
/// 为什么不用 `NSSwitch`：
/// `NSSwitch` 没有任何公开 API 可以改颜色 —— 它既没有 `contentTintColor`
/// 也没有 `tintColor`（实测 KVC 设 `tintColor` 会直接抛
/// `NSUnknownKeyException`），开关的填充色完全由系统 accent color 决定。
/// 在菜单项的自定义 view 里它甚至可能不跟随 accent color 渲染，
/// 表现就是「开启后颜色不受控（不是想要的蓝）」。
///
/// 因此这里自己画一个：圆角胶囊底 + 圆形滑块，开启时填充系统蓝，
/// 视觉上对齐系统设置里 Wi-Fi 开关的样子，同时颜色完全可控。
final class ToggleSwitch: NSControl {

    /// 开关状态变化时回调。
    var onChange: ((Bool) -> Void)?

    /// 胶囊尺寸，与系统开关观感接近（系统约 54x24，这里稍小以适配菜单）。
    private let trackSize = NSSize(width: 42, height: 24)
    private let knobInset: CGFloat = 2.5

    private var isOn: Bool = false

    /// 开启时的填充色。
    /// 用系统蓝 —— 与 macOS 默认强调色一致，观感最贴近系统设置里的开关。
    var onColor: NSColor = .systemBlue {
        didSet { needsDisplay = true }
    }
    /// 关闭时的填充色。
    var offColor: NSColor = NSColor.quaternaryLabelColor {
        didSet { needsDisplay = true }
    }

    // MARK: - 初始化

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(origin: frameRect.origin, size: trackSize))
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        // 让控件在菜单视图里也能收到鼠标事件
        isEnabled = true
    }

    override var intrinsicContentSize: NSSize { trackSize }

    override var isFlipped: Bool { false }

    /// 当前状态（与 NSSwitch 的 state 语义一致，方便替换）。
    var state: NSControl.StateValue {
        get { isOn ? .on : .off }
        set {
            let newValue = (newValue == .on)
            guard newValue != isOn else { return }
            isOn = newValue
            needsDisplay = true
            onChange?(isOn)
        }
    }

    /// 不触发回调地设置状态（用于初始化）。
    func setState(_ on: Bool, notify: Bool = false) {
        isOn = on
        needsDisplay = true
        if notify { onChange?(isOn) }
    }

    // MARK: - 交互

    override func mouseDown(with event: NSEvent) {
        // 按下即切换，手感与系统开关一致（不做拖拽也让逻辑简单可靠）
        isOn.toggle()
        needsDisplay = true
        onChange?(isOn)
        sendAction(action, to: target)
    }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds
        let height = bounds.height
        let radius = height / 2

        // ---- 胶囊底 ----
        let trackRect = bounds
        let trackPath = NSBezierPath(roundedRect: trackRect, xRadius: radius, yRadius: radius)

        // 开启时用系统蓝，关闭时用中性灰；对比明确，避免「看不出开没开」
        let fill = isOn ? onColor : offColor
        fill.setFill()
        trackPath.fill()

        // 关闭时描一圈细边，让胶囊轮廓在浅色背景上也能看清
        if !isOn {
            NSColor.separatorColor.setStroke()
            trackPath.lineWidth = 1
            trackPath.stroke()
        }

        // ---- 圆形滑块 ----
        let knobDiameter = height - knobInset * 2
        let knobY = knobInset
        // 关闭时靠左，开启时靠右
        let knobX = isOn ? (bounds.width - knobDiameter - knobInset) : knobInset
        let knobRect = NSRect(x: knobX, y: knobY, width: knobDiameter, height: knobDiameter)

        let knobPath = NSBezierPath(ovalIn: knobRect)
        NSColor.white.setFill()
        knobPath.fill()

        // 滑块加一点投影，增加立体感
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
        shadow.shadowBlurRadius = 2.5
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()
        NSColor.white.setFill()
        knobPath.fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}
