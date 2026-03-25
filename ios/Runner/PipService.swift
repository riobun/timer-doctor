import AVFoundation
import AVKit
import UIKit

/// Displays a floating text reminder via iOS Picture-in-Picture.
/// Requires iOS 15+ and the "audio" UIBackgroundModes entry.
@available(iOS 15.0, *)
class PipService: NSObject, AVPictureInPictureControllerDelegate {
    static let shared = PipService()

    private var pipController: AVPictureInPictureController?
    private var callViewController: PipContentViewController?
    private var textLabel: UILabel?
    private var textLabel2: UILabel?   // loop copy
    private var scrollView: UIScrollView?
    private var pipPossibleObserver: NSKeyValueObservation?
    private var pipActiveObserver: NSKeyValueObservation?
    private var marqueeTimer: Timer?
    private var heightConstraint: NSLayoutConstraint?

    // ── Persistent state ──────────────────────────────────────────────────────
    private var isOverlayActive = false
    private var currentText = ""
    private var currentFontSize: Double = 14
    private var currentTextColorArgb: Int = 0xFFFFFFFF
    private var currentBgColorArgb: Int = 0xFF141414
    private var currentBgOpacity: Double = 0.85

    // PiP 宽度固定，高度跟字号动态变化
    private let pipWidth: CGFloat = 400
    private let pipHPad: CGFloat = 10   // 左右各 10pt
    private var pipHeight: CGFloat { CGFloat(currentFontSize) * 1.4 + 8 }

    private override init() { super.init() }

    // MARK: - Public API

    func show(text: String) {
        print("[PipService] show() called, text='\(text)'")
        isOverlayActive = true
        currentText = text
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.activateAudioSession()
            if self.callViewController == nil {
                self.buildPip()
            } else {
                print("[PipService] reusing existing PiP, updating text")
                self.refreshLabel(text: text)
            }
            self.startPipWhenReady()
        }
    }

    func hide() {
        print("[PipService] hide() called")
        isOverlayActive = false
        currentText = ""
        DispatchQueue.main.async {
            self.stopMarquee()
            self.pipController?.stopPictureInPicture()
        }
    }

    func updateText(_ text: String) {
        currentText = text
        DispatchQueue.main.async { self.refreshLabel(text: text) }
    }

    func updateStyle(fontSize: Double, textColorArgb: Int, bgColorArgb: Int, bgOpacity: Double) {
        currentFontSize = fontSize
        currentTextColorArgb = textColorArgb
        currentBgColorArgb = bgColorArgb
        currentBgOpacity = bgOpacity
        DispatchQueue.main.async { self.applyStoredStyle() }
    }

    // MARK: - Private helpers

    private func refreshLabel(text: String) {
        guard let label = textLabel, let sv = scrollView else { return }
        label.text = text
        textLabel2?.text = text
        relayoutLabel(label: label, in: sv)
    }

    private func applyStoredStyle() {
        guard let label = textLabel, let sv = scrollView else { return }
        let font = UIFont.systemFont(ofSize: currentFontSize, weight: .medium)
        let color = UIColor(argb: currentTextColorArgb)
        label.font = font
        label.textColor = color
        textLabel2?.font = font
        textLabel2?.textColor = color
        callViewController?.view.backgroundColor =
            UIColor(argb: currentBgColorArgb).withAlphaComponent(currentBgOpacity)
        heightConstraint?.constant = pipHeight
        callViewController?.preferredContentSize = CGSize(width: pipWidth, height: pipHeight)
        relayoutLabel(label: label, in: sv)
    }

    /// Position label(s) inside scroll view; start loop marquee if text overflows.
    private func relayoutLabel(label: UILabel, in sv: UIScrollView) {
        let naturalWidth = label.intrinsicContentSize.width
        let svWidth = sv.bounds.width > 1 ? sv.bounds.width : pipWidth
        let viewHeight = sv.bounds.height > 1 ? sv.bounds.height : pipHeight
        let availableWidth = svWidth - pipHPad * 2

        stopMarquee()
        sv.contentOffset = .zero
        textLabel2?.isHidden = true

        if naturalWidth <= availableWidth {
            // Text fits — center, hide copy label
            let centeredX = (svWidth - naturalWidth) / 2
            label.frame = CGRect(x: centeredX, y: 0, width: naturalWidth, height: viewHeight)
            sv.contentSize = CGSize(width: svWidth, height: viewHeight)
        } else {
            // Text overflows — place two copies for seamless loop
            let gap: CGFloat = 40
            let loopWidth = naturalWidth + gap          // distance of one full loop step
            label.frame = CGRect(x: pipHPad, y: 0, width: naturalWidth, height: viewHeight)
            if let label2 = textLabel2 {
                label2.isHidden = false
                label2.frame = CGRect(x: pipHPad + loopWidth, y: 0, width: naturalWidth, height: viewHeight)
            }
            sv.contentSize = CGSize(width: pipHPad + loopWidth * 2, height: viewHeight)
            scheduleLoopMarquee(scrollView: sv, loopWidth: loopWidth, initialDelay: 1.5)
        }
    }

    // MARK: - Marquee

    private func scheduleLoopMarquee(scrollView sv: UIScrollView, loopWidth: CGFloat, initialDelay: TimeInterval) {
        marqueeTimer?.invalidate()
        if initialDelay > 0 {
            marqueeTimer = Timer.scheduledTimer(withTimeInterval: initialDelay, repeats: false) { [weak self, weak sv] _ in
                guard let self, let sv else { return }
                self.runLoopMarquee(scrollView: sv, loopWidth: loopWidth)
            }
        } else {
            runLoopMarquee(scrollView: sv, loopWidth: loopWidth)
        }
    }

    private func runLoopMarquee(scrollView sv: UIScrollView, loopWidth: CGFloat) {
        let duration = loopWidth / 60.0   // 60 pt/s
        UIView.animate(withDuration: duration, delay: 0, options: [.curveLinear]) {
            sv.contentOffset = CGPoint(x: loopWidth, y: 0)
        } completion: { [weak self, weak sv] finished in
            guard let self, let sv, finished else { return }
            // Instant reset to 0 — seamless because copy label is at loopWidth offset
            sv.contentOffset = .zero
            self.runLoopMarquee(scrollView: sv, loopWidth: loopWidth)
        }
    }

    private func stopMarquee() {
        marqueeTimer?.invalidate()
        marqueeTimer = nil
        scrollView?.layer.removeAllAnimations()
        scrollView?.contentOffset = .zero
    }

    // MARK: - Audio / PiP setup

    private func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord,
                                    mode: .videoChat,
                                    options: [.mixWithOthers, .defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            print("[PipService] audioSession error: \(error)")
        }
    }

    private func startPipWhenReady() {
        guard let pip = pipController else {
            print("[PipService] startPipWhenReady: pipController is nil")
            return
        }
        if pip.isPictureInPicturePossible {
            pip.startPictureInPicture()
        } else {
            pipPossibleObserver = pip.observe(\.isPictureInPicturePossible, options: [.new]) { [weak self] ctrl, change in
                guard change.newValue == true else { return }
                self?.pipPossibleObserver = nil
                DispatchQueue.main.async { ctrl.startPictureInPicture() }
            }
        }
    }

    private func buildPip() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first,
              let rootVC = window.rootViewController else {
            print("[PipService] buildPip FAILED: no rootVC")
            return
        }

        let vc = PipContentViewController()
        vc.preferredContentSize = CGSize(width: pipWidth, height: pipHeight)
        vc.view.layer.cornerRadius = 8
        vc.view.clipsToBounds = true
        vc.view.backgroundColor = UIColor(argb: currentBgColorArgb).withAlphaComponent(currentBgOpacity)

        rootVC.addChild(vc)
        vc.view.translatesAutoresizingMaskIntoConstraints = false
        rootVC.view.addSubview(vc.view)
        vc.didMove(toParent: rootVC)

        let hc = vc.view.heightAnchor.constraint(equalToConstant: pipHeight)
        heightConstraint = hc
        NSLayoutConstraint.activate([
            vc.view.widthAnchor.constraint(equalToConstant: pipWidth),
            hc,
            vc.view.bottomAnchor.constraint(equalTo: rootVC.view.topAnchor, constant: -10),
            vc.view.leadingAnchor.constraint(equalTo: rootVC.view.leadingAnchor),
        ])

        // Scroll view — fills vc.view via PipContentViewController.viewDidLayoutSubviews
        let sv = UIScrollView()
        sv.showsHorizontalScrollIndicator = false
        sv.showsVerticalScrollIndicator = false
        sv.isScrollEnabled = false
        sv.clipsToBounds = true
        sv.backgroundColor = .clear
        sv.frame = CGRect(x: 0, y: 0, width: pipWidth, height: pipHeight)
        sv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        vc.view.addSubview(sv)

        // Helper to create a single-line label
        func makeLabel() -> UILabel {
            let l = UILabel()
            l.text = currentText
            l.textAlignment = .left
            l.numberOfLines = 1
            l.lineBreakMode = .byClipping
            l.backgroundColor = .clear
            l.font = .systemFont(ofSize: currentFontSize, weight: .medium)
            l.textColor = UIColor(argb: currentTextColorArgb)
            return l
        }

        let label = makeLabel()
        let label2 = makeLabel()
        label2.isHidden = true
        sv.addSubview(label)
        sv.addSubview(label2)

        textLabel = label
        textLabel2 = label2
        scrollView = sv
        callViewController = vc

        // Initial layout; also re-run after PiP finishes rendering to get real bounds
        relayoutLabel(label: label, in: sv)
        vc.onLayout = { [weak self] in
            guard let self, let l = self.textLabel, let s = self.scrollView else { return }
            self.relayoutLabel(label: l, in: s)
        }

        let source = AVPictureInPictureController.ContentSource(
            activeVideoCallSourceView: rootVC.view,
            contentViewController: vc
        )
        let pip = AVPictureInPictureController(contentSource: source)
        pip.delegate = self
        pipController = pip

        pipActiveObserver = pip.observe(\.isPictureInPictureActive, options: [.new]) { _, change in
            print("[PipService] isPictureInPictureActive → \(change.newValue ?? false)")
        }
        print("[PipService] buildPip complete")
    }

    private func tearDown() {
        stopMarquee()
        pipPossibleObserver = nil
        pipActiveObserver = nil
        heightConstraint = nil
        callViewController?.willMove(toParent: nil)
        callViewController?.view.removeFromSuperview()
        callViewController?.removeFromParent()
        callViewController = nil
        textLabel = nil
        textLabel2 = nil
        scrollView = nil
        pipController = nil
    }

    // MARK: - AVPictureInPictureControllerDelegate

    func pictureInPictureControllerDidStartPictureInPicture(
        _ controller: AVPictureInPictureController
    ) {
        print("[PipService] ✅ didStartPictureInPicture")
    }

    func pictureInPictureControllerDidStopPictureInPicture(
        _ controller: AVPictureInPictureController
    ) {
        print("[PipService] didStopPictureInPicture, isOverlayActive=\(isOverlayActive)")
        try? AVAudioSession.sharedInstance().setActive(
            false, options: .notifyOthersOnDeactivation
        )
        tearDown()

        if isOverlayActive {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.activateAudioSession()
                self.buildPip()
                self.startPipWhenReady()
            }
        }
    }

    func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        print("[PipService] ❌ failedToStart: \(error)")
    }
}

// MARK: - PipContentViewController

@available(iOS 15.0, *)
private class PipContentViewController: AVPictureInPictureVideoCallViewController {
    var onLayout: (() -> Void)?

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Fill scroll view to actual PiP-rendered bounds (may differ from preferredContentSize)
        for subview in view.subviews {
            subview.frame = view.bounds
        }
        onLayout?()
    }
}

// MARK: - UIColor helper

private extension UIColor {
    convenience init(argb: Int) {
        let a = CGFloat((argb >> 24) & 0xFF) / 255
        let r = CGFloat((argb >> 16) & 0xFF) / 255
        let g = CGFloat((argb >> 8) & 0xFF) / 255
        let b = CGFloat(argb & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}
