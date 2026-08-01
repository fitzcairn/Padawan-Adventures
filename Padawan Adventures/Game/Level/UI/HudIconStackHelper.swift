import UIKit

extension GameHUDView {
    func addIcon(image: UIImage?, to stack: UIStackView, animated: Bool) {
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isUserInteractionEnabled = false
        let size = CGFloat(config.iconSize)
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: size),
            imageView.heightAnchor.constraint(equalToConstant: size),
        ])

        imageView.alpha = animated ? 0 : 1
        // Avoid UIStackView's implicit layout animation fighting SpriteKit's frame.
        UIView.performWithoutAnimation {
            stack.addArrangedSubview(imageView)
            stack.layoutIfNeeded()
        }

        guard animated else { return }
        UIView.animate(
            withDuration: Self.hudIconFadeDuration,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            imageView.alpha = 1
        }
    }

    func removeIcon(from stack: UIStackView, animated: Bool) {
        guard let icon = stack.arrangedSubviews.last else { return }
        let remove = {
            UIView.performWithoutAnimation {
                stack.removeArrangedSubview(icon)
                icon.removeFromSuperview()
                stack.layoutIfNeeded()
            }
        }
        guard animated else {
            remove()
            return
        }
        UIView.animate(
            withDuration: Self.hudIconFadeDuration,
            delay: 0,
            options: [.curveEaseIn, .allowUserInteraction],
            animations: { icon.alpha = 0 },
            completion: { _ in remove() }
        )
    }

    func clearIcons(in stack: UIStackView) {
        UIView.performWithoutAnimation {
            for view in stack.arrangedSubviews {
                stack.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
            stack.layoutIfNeeded()
        }
    }

    static func makeIconStack(spacing: Int) -> UIStackView {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = CGFloat(spacing)
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isUserInteractionEnabled = false
        return stack
    }
}
