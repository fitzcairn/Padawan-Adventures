import SwiftUI

struct MerchantInspectModal: View {
    let itemID: String
    let item: MerchantItemDefinition
    let onDismiss: () -> Void

    var body: some View {
        ModalOverlayShell(
            accessibilityRootID: "merchant.inspect",
            onBackgroundTap: onDismiss
        ) {
            ModalCRTPanel {
                VStack(alignment: .leading, spacing: 20) {
                    MerchantWareSpriteView(itemID: itemID, sprite: item.sprite, showsShadow: true)
                        .frame(width: inspectSpriteSize.width, height: inspectSpriteSize.height)
                        .frame(maxWidth: .infinity, alignment: .center)
                    ModalCRTText(
                        text: Strings.text(item.description),
                        size: 26,
                        weight: .semibold,
                        alignment: .leading,
                        accessibilityID: "merchant.inspect.description",
                        speakID: item.description
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: 520)
        }
        .onAppear { Strings.speak(item.description) }
        .contentShape(Rectangle())
        .onTapGesture(perform: onDismiss)
    }

    private var inspectSpriteSize: CGSize {
        MerchantWares.fittedSize(
            pixelSize: MerchantWareIcon.pixelSize(id: itemID, sprite: item.sprite),
            slotSide: 96
        )
    }
}

struct MerchantReplaceModal: View {
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ModalOverlayShell(
            accessibilityRootID: "merchant.replace",
            onBackgroundTap: onCancel
        ) {
            ModalCRTPanel {
                VStack(spacing: 28) {
                    ModalCRTText(
                        text: Strings.text("merchant_replace_item"),
                        size: 30,
                        accessibilityID: "merchant.replace.title",
                        speakID: "merchant_replace_item"
                    )
                    HStack(spacing: 36) {
                        Button(action: {
                            playMenuSound("button_click")
                            onCancel()
                        }) {
                            AppCircularIconPlate(systemName: "xmark", size: 64)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Strings.text("button_cancel"))
                        .accessibilityIdentifier("merchant.replace.cancel")

                        Button(action: {
                            onConfirm()
                        }) {
                            AppCircularIconPlate(systemName: "checkmark", size: 64)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Strings.text("button_ok"))
                        .accessibilityIdentifier("merchant.replace.ok")
                    }
                }
            }
            .frame(maxWidth: 480)
        }
        .onAppear { Strings.speak("merchant_replace_item") }
    }
}

struct MerchantCoinBurstOverlay: View {
    let origin: CGPoint
    let progress: CGFloat

    private let particles: [(dx: CGFloat, dy: CGFloat, spin: CGFloat, scale: CGFloat)] = {
        var rng = SeededGenerator(seed: 0xC01A)
        return (0..<10).map { _ in
            let angle = Double.random(in: 0..<(Double.pi * 2), using: &rng)
            let speed = CGFloat.random(in: 80...220, using: &rng)
            return (
                dx: CGFloat(cos(angle)) * speed,
                dy: CGFloat(sin(angle)) * speed,
                spin: CGFloat.random(in: -90...90, using: &rng),
                scale: CGFloat.random(in: 0.55...1.0, using: &rng)
            )
        }
    }()

    var body: some View {
        ZStack {
            ForEach(particles.indices, id: \.self) { index in
                let particle = particles[index]
                let t = progress
                ScoreCoinIcon.Image(side: 28 * particle.scale * (1 - t * 0.7))
                    .opacity(Double(1 - t))
                    .position(
                        x: origin.x + particle.dx * t,
                        y: origin.y + particle.dy * t
                    )
                    .rotationEffect(.degrees(Double(particle.spin * t)))
            }
        }
        .allowsHitTesting(false)
    }
}

private extension CGFloat {
    static func random(in range: ClosedRange<CGFloat>, using rng: inout SeededGenerator) -> CGFloat {
        let span = range.upperBound - range.lowerBound
        let unit = CGFloat(rng.next() % 10_000) / 10_000
        return range.lowerBound + span * unit
    }
}

private extension Double {
    static func random(in range: Range<Double>, using rng: inout SeededGenerator) -> Double {
        let span = range.upperBound - range.lowerBound
        let unit = Double(rng.next() % 10_000) / 10_000
        return range.lowerBound + span * unit
    }
}
