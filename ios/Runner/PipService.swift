import AVFoundation
import AVKit
import UIKit

/// Displays a floating text reminder via iOS Picture-in-Picture.
/// Requires iOS 15+ and the "audio" UIBackgroundModes entry.
@available(iOS 15.0, *)
class PipService: NSObject, AVPictureInPictureControllerDelegate {
    static let shared = PipService()

    private var pipController: AVPictureInPictureController?
    private var callViewController: AVPictureInPictureVideoCallViewController?
    private var textLabel: UILabel?

    private override init() { super.init() }

    // MARK: - Public API

    func show(text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Activate a silent audio session — required for PiP to appear outside the app.
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, options: .mixWithOthers)
            try? session.setActive(true)

            if self.callViewController == nil {
                self.buildPip(text: text)
            } else {
                self.textLabel?.text = text
            }
            self.pipController?.startPictureInPicture()
        }
    }

    func hide() {
        DispatchQueue.main.async { self.pipController?.stopPictureInPicture() }
    }

    func updateText(_ text: String) {
        DispatchQueue.main.async { self.textLabel?.text = text }
    }

    func updateStyle(fontSize: Double, textColorArgb: Int, bgColorArgb: Int, bgOpacity: Double) {
        DispatchQueue.main.async {
            self.textLabel?.font = .systemFont(ofSize: fontSize, weight: .medium)
            self.textLabel?.textColor = UIColor(argb: textColorArgb)
            let bg = UIColor(argb: bgColorArgb).withAlphaComponent(bgOpacity)
            self.textLabel?.backgroundColor = bg
            self.callViewController?.view.backgroundColor = bg
        }
    }

    // MARK: - Private

    private func buildPip(text: String) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else { return }

        let vc = AVPictureInPictureVideoCallViewController()
        vc.preferredContentSize = CGSize(width: 320, height: 72)
        vc.view.backgroundColor = UIColor(white: 0.08, alpha: 0.9)
        vc.view.layer.cornerRadius = 10
        vc.view.clipsToBounds = true

        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        vc.view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: vc.view.centerYAnchor),
        ])

        textLabel = label
        callViewController = vc

        let source = AVPictureInPictureControllerContentSource(
            activeVideoCallSourceView: window,
            contentViewController: vc
        )
        let pip = AVPictureInPictureController(contentSource: source)
        pip.delegate = self
        pipController = pip
    }

    // MARK: - AVPictureInPictureControllerDelegate

    func pictureInPictureControllerDidStopPictureInPicture(
        _ controller: AVPictureInPictureController
    ) {
        // Release audio session and reset state so next show() rebuilds cleanly.
        try? AVAudioSession.sharedInstance().setActive(
            false, options: .notifyOthersOnDeactivation
        )
        callViewController = nil
        textLabel = nil
        pipController = nil
    }

    func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        print("[PipService] Failed to start PiP: \(error.localizedDescription)")
    }
}

// MARK: - UIColor helper

private extension UIColor {
    /// Initialize from a Flutter ARGB integer (e.g. 0xFFFFFFFF).
    convenience init(argb: Int) {
        let a = CGFloat((argb >> 24) & 0xFF) / 255
        let r = CGFloat((argb >> 16) & 0xFF) / 255
        let g = CGFloat((argb >> 8) & 0xFF) / 255
        let b = CGFloat(argb & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}
