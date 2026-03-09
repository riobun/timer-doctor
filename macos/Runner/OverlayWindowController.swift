import Cocoa

class OverlayWindowController: NSObject {
  private var panel: NSPanel?
  private var bubble: NSView?
  private var label: NSTextField?
  private var dragView: DragCatcherView?

  // Style
  private var fontSize: CGFloat = 14
  private var textColorValue: Int = 0xFFFFFFFF
  private var bgColorValue: Int = 0xFF141414
  private var bgOpacity: Double = 0.5

  // MARK: - Public API

  func show(text: String) {
    if panel == nil { buildPanel() }
    applyText(text)
    panel?.orderFrontRegardless()
  }

  func hide() {
    panel?.orderOut(nil)
  }

  func updateText(_ text: String) {
    applyText(text)
  }

  func updateStyle(fontSize: Double, textColor: Int, bgColor: Int, bgOpacity: Double) {
    self.fontSize = CGFloat(fontSize)
    self.textColorValue = textColor
    self.bgColorValue = bgColor
    self.bgOpacity = bgOpacity
    guard panel != nil else { return }
    applyStyle()
    applyLayout(text: label?.stringValue ?? "")
  }

  // MARK: - Build

  private func buildPanel() {
    let initW: CGFloat = 200
    let initH: CGFloat = 30

    let p = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: initW, height: initH),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    p.level = .floating
    p.isOpaque = false
    p.backgroundColor = .clear
    p.hasShadow = true
    p.isMovableByWindowBackground = true
    p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    p.hidesOnDeactivate = false

    let bv = NSView(frame: NSRect(x: 0, y: 0, width: initW, height: initH))
    bv.wantsLayer = true
    bv.layer?.cornerRadius = initH / 2
    bv.layer?.masksToBounds = true

    let tf = NSTextField(labelWithString: "")
    tf.isBordered = false
    tf.isEditable = false
    tf.isSelectable = false
    tf.drawsBackground = false
    tf.wantsLayer = true
    bv.addSubview(tf)

    let dv = DragCatcherView(frame: NSRect(x: 0, y: 0, width: initW, height: initH))
    bv.addSubview(dv)

    p.contentView = bv

    if let screen = NSScreen.main {
      let sf = screen.visibleFrame
      p.setFrameOrigin(NSPoint(x: sf.midX - initW / 2, y: sf.maxY - initH - 16))
    }

    panel = p
    bubble = bv
    label = tf
    dragView = dv

    applyStyle()
  }

  // MARK: - Style

  private func applyStyle() {
    guard let bv = bubble, let tf = label else { return }
    bv.layer?.backgroundColor = nsColor(from: bgColorValue)
      .withAlphaComponent(CGFloat(bgOpacity)).cgColor
    tf.textColor = nsColor(from: textColorValue)
    tf.font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
  }

  // MARK: - Text & Layout

  private func applyText(_ text: String) {
    label?.stringValue = text
    applyLayout(text: text)
  }

  private func applyLayout(text: String) {
    guard let panel = panel,
          let bv = bubble,
          let tf = label,
          let dv = dragView else { return }

    let hPad: CGFloat = 24  // horizontal padding (12 each side)
    let vPad: CGFloat = 10  // vertical padding (5 each side)

    let font = tf.font ?? NSFont.systemFont(ofSize: fontSize)
    let attrs: [NSAttributedString.Key: Any] = [.font: font]
    let measured = (text as NSString).size(withAttributes: attrs)
    let textW = ceil(measured.width)
    let textH = ceil(measured.height)

    // Height adapts to font size
    let h = textH + vPad

    let screen = NSScreen.main ?? NSScreen.screens.first!
    let maxW = screen.visibleFrame.width * 0.88

    // Stop existing marquee and reset transform
    tf.layer?.removeAllAnimations()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    tf.layer?.transform = CATransform3DIdentity
    CATransaction.commit()

    let panelW: CGFloat
    let isMarquee: Bool

    if textW + hPad <= maxW {
      panelW = textW + hPad
      isMarquee = false
    } else {
      panelW = maxW
      isMarquee = true
    }

    // Keep top edge fixed while resizing (macOS Y is bottom-up)
    var pf = panel.frame
    let topEdge = pf.origin.y + pf.size.height
    pf.size.height = h
    pf.origin.y = topEdge - h
    pf.origin.x = max(0, min(pf.origin.x, screen.visibleFrame.width - panelW))
    pf.size.width = panelW
    panel.setFrame(pf, display: true)

    bv.frame = NSRect(x: 0, y: 0, width: panelW, height: h)
    bv.layer?.cornerRadius = h / 2   // keep pill shape
    dv.frame = NSRect(x: 0, y: 0, width: panelW, height: h)

    // Perfectly centered
    let textY = (h - textH) / 2

    if isMarquee {
      tf.frame = NSRect(x: 0, y: textY, width: textW, height: textH)

      let anim = CABasicAnimation(keyPath: "transform.translation.x")
      anim.fromValue = panelW
      anim.toValue = -textW
      anim.duration = Double(panelW + textW) / 60.0
      anim.repeatCount = .infinity
      anim.timingFunction = CAMediaTimingFunction(name: .linear)
      tf.layer?.add(anim, forKey: "marquee")
    } else {
      // Horizontally and vertically centered
      let textX = (panelW - textW) / 2
      tf.frame = NSRect(x: textX, y: textY, width: textW, height: textH)
    }
  }

  // MARK: - Helpers

  private func nsColor(from colorValue: Int) -> NSColor {
    let r = CGFloat((colorValue >> 16) & 0xFF) / 255
    let g = CGFloat((colorValue >> 8) & 0xFF) / 255
    let b = CGFloat(colorValue & 0xFF) / 255
    return NSColor(red: r, green: g, blue: b, alpha: 1.0)
  }
}

private class DragCatcherView: NSView {
  override var mouseDownCanMoveWindow: Bool { return true }
}
