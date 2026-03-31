import SwiftUI
import AppKit

/// Animated sprite view for Tarsbot — the robot mascot in the notch
struct TarsbotView: View {
    let state: NotchDisplayState
    @State private var currentFrame: Int = 0
    @State private var timer: Timer?

    private var spriteConfig: SpriteConfig {
        switch state {
        case .idle: return SpriteConfig(name: "Idle", frames: 121, fps: 24)
        case .working: return SpriteConfig(name: "Walk", frames: 121, fps: 24)
        case .waitingForInput: return SpriteConfig(name: "Attack", frames: 121, fps: 24)
        case .taskCompleted: return SpriteConfig(name: "Enabling", frames: 121, fps: 24)
        }
    }

    var body: some View {
        SpriteFrameView(spriteName: spriteConfig.name, frame: currentFrame, totalFrames: spriteConfig.frames)
            .frame(width: 32, height: 32)
            .onAppear { startAnimation() }
            .onDisappear { stopAnimation() }
            .onChange(of: state) {
                currentFrame = 0
                startAnimation()
            }
    }

    private func startAnimation() {
        stopAnimation()
        let config = spriteConfig
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / Double(config.fps), repeats: true) { _ in
            DispatchQueue.main.async {
                currentFrame = (currentFrame + 1) % config.frames
            }
        }
    }

    private func stopAnimation() {
        timer?.invalidate()
        timer = nil
    }
}

struct SpriteConfig {
    let name: String
    let frames: Int
    let fps: Int
}

/// Extracts a single frame from a horizontal sprite sheet
struct SpriteFrameView: View {
    let spriteName: String
    let frame: Int
    let totalFrames: Int

    var body: some View {
        GeometryReader { geo in
            if let nsImage = NSImage(named: spriteName),
               let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                let frameWidth = cgImage.width / totalFrames
                let frameHeight = cgImage.height
                if let cropped = cgImage.cropping(to: CGRect(
                    x: frame * frameWidth,
                    y: 0,
                    width: frameWidth,
                    height: frameHeight
                )) {
                    Image(nsImage: NSImage(cgImage: cropped, size: NSSize(width: frameWidth, height: frameHeight)))
                        .interpolation(.none)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
        }
    }
}
