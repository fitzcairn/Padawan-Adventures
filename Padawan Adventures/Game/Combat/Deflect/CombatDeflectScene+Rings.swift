import SpriteKit
import UIKit

extension CombatDeflectScene {
    // MARK: - Rings

    /// Binds palette colors to the fight's initial left-to-right graphemes so they
    /// travel with the letter across shuffles and layout rebuilds.
    func captureRingColors() {
        ringColorByGrapheme.removeAll()
        let count = max(engine.graphemes.count, 1)
        for (index, grapheme) in engine.graphemes.enumerated() {
            let paletteIndex = min(
                index * ringColors.count / count,
                ringColors.count - 1
            )
            ringColorByGrapheme[grapheme.grapheme] = ringColors[paletteIndex]
        }
    }

    func rebuildRings() {
        let pendingShuffle = ringShuffleCompletion
        ringShuffleCompletion = nil
        ringLayer.removeAction(forKey: ringShuffleActionKey)
        ringLayer.removeAllChildren()
        pendingShuffle?()
        let geo = geometry

        for ring in geo.rings {
            guard let letter = letter(for: ring) else { continue }
            let color = ringColor(for: ring)
            let container = SKNode()
            container.name = "ring:\(letter)"
            container.position = geo.ringCenter(ring)
            container.zPosition = Layer.rings
            if container.userData == nil { container.userData = NSMutableDictionary() }
            container.userData?["grapheme"] = letter

            let ellipse = makeDashedEllipse(radii: geo.ringRadii, color: color)
            container.addChild(ellipse)

            let label = makeOutlinedLetter(
                letter,
                fontSize: max(geo.ringRadii.height * 1.6, 18),
                outline: color
            )
            label.position = CGPoint(x: 0, y: geo.ringRadii.height)
            label.zPosition = 1
            container.addChild(label)
            ringLayer.addChild(container)
        }
    }

    func ringColor(for ring: CombatDeflectRing) -> UIColor {
        if let letter = letter(for: ring), let color = ringColorByGrapheme[letter] {
            return color
        }
        let count = max(engine.graphemes.count, 1)
        // Spread the 6-color palette across whatever ring count is configured so
        // the default 3-letter set still lands on red / yellow / blue.
        let paletteIndex = min(
            ring.index * ringColors.count / count,
            ringColors.count - 1
        )
        return ringColors[paletteIndex]
    }

    func letter(for ring: CombatDeflectRing) -> String? {
        let letters = engine.graphemes
        guard ring.index >= 0, ring.index < letters.count else { return nil }
        return letters[ring.index].grapheme
    }

    /// Permutes seats and eases each ring along the upper orbit. Calls `completion`
    /// when the motion lands, or immediately when the order cannot change.
    func shuffleAndAnimateRings(completion: @escaping () -> Void) {
        let geo = geometry
        var oldAngles: [String: CGFloat] = [:]
        for (index, grapheme) in engine.graphemes.enumerated() {
            oldAngles[grapheme.grapheme] = geo.angle(for: CombatDeflectRing(index))
        }
        guard engine.shuffleRingOrder() else {
            completion()
            return
        }
        remappedActiveOrbRing()
        ringShuffleCompletion = completion

        let duration = Self.ringShuffleDuration
        for (index, grapheme) in engine.graphemes.enumerated() {
            let letter = grapheme.grapheme
            guard let node = ringNode(for: letter),
                  let from = oldAngles[letter] else { continue }
            let to = geo.angle(for: CombatDeflectRing(index))
            node.removeAction(forKey: ringShuffleActionKey)
            let follow = SKAction.customAction(withDuration: duration) { node, elapsed in
                let t = min(max(CGFloat(elapsed) / CGFloat(duration), 0), 1)
                node.position = geo.pointOnOrbit(from: from, to: to, t: t)
            }
            node.run(follow, withKey: ringShuffleActionKey)
        }

        ringLayer.removeAction(forKey: ringShuffleActionKey)
        ringLayer.run(
            .sequence([
                .wait(forDuration: duration),
                .run { [weak self] in
                    let done = self?.ringShuffleCompletion
                    self?.ringShuffleCompletion = nil
                    done?()
                },
            ]),
            withKey: ringShuffleActionKey
        )
    }

    func remappedActiveOrbRing() {
        guard var orb = activeOrb,
              let index = engine.graphemes.firstIndex(where: { $0.grapheme == orb.letter })
        else { return }
        orb.ring = CombatDeflectRing(index)
        activeOrb = orb
    }

    private func ringNode(for grapheme: String) -> SKNode? {
        ringLayer.children.first { node in
            (node.userData?["grapheme"] as? String) == grapheme
        }
    }

    /// `SKShapeNode` has no dash property, so the dashes are baked into the path.
    /// `radii` is local to a container sitting on the ring center.
    func makeDashedEllipse(radii: CGSize, color: UIColor) -> SKShapeNode {
        let rect = CGRect(
            x: -radii.width,
            y: -radii.height,
            width: radii.width * 2,
            height: radii.height * 2
        )
        let base = CGPath(ellipseIn: rect, transform: nil)
        let dashed = base.copy(dashingWithPhase: 0, lengths: ringDashLengths)
        let node = SKShapeNode(path: dashed)
        node.strokeColor = color
        node.fillColor = .clear
        node.lineWidth = ringLineWidth
        node.isAntialiased = true
        return node
    }

    /// `SKLabelNode` cannot stroke text, so outlined letters need `attributedText`.
    /// A negative `strokeWidth` fills *and* strokes; positive would give hollow text.
    func makeOutlinedLetter(
        _ text: String,
        fontSize: CGFloat,
        outline: UIColor
    ) -> SKLabelNode {
        let font = UIFont(name: AppFont.name, size: fontSize)
            ?? UIFont.boldSystemFont(ofSize: fontSize)
        let label = SKLabelNode(attributedText: NSAttributedString(
            string: text.uppercased(),
            attributes: [
                .font: font,
                .foregroundColor: UIColor.white,
                .strokeColor: outline,
                .strokeWidth: -6.0,
            ]
        ))
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        return label
    }
}
