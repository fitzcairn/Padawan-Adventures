import SwiftUI

enum AppChrome {
    static let backgroundColor = Color.black
    static let primaryTextColor = Color.white
    static let secondaryTextColor = Color(white: 0.65)
    static let buttonBackgroundColor = Color(white: 0.92)
    static let buttonForegroundColor = Color.black
    static let maxContentWidth: CGFloat = 420

    static var versionBuildString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "v\(version) (\(build))"
    }
}

extension View {
    func appScreenBackground() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppChrome.backgroundColor.ignoresSafeArea())
    }

    func appReadableWidth() -> some View {
        frame(maxWidth: AppChrome.maxContentWidth)
            .frame(maxWidth: .infinity)
    }
}

struct AppTitleText: View {
    let text: String
    var size: CGFloat = 28
    var weight: Font.Weight = .semibold
    var color: Color = AppChrome.primaryTextColor

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
}

struct AppLargeButton: View {
    let title: String
    var accessibilityID: String? = nil
    var backgroundColor: Color = AppChrome.buttonBackgroundColor
    var opacity: Double = 1
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(AppChrome.buttonForegroundColor)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(backgroundColor, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .opacity(opacity)
        .frame(minHeight: 44)
        .accessibilityIdentifier(accessibilityID ?? title)
    }
}

/// Circular chrome control (back, lock, etc.) — light fill, dark SF Symbol.
struct AppCircularIconButton: View {
    let systemName: String
    var size: CGFloat = 52
    var accessibilityID: String? = nil
    var accessibilityLabel: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(AppChrome.buttonForegroundColor)
                .frame(width: size, height: size)
                .background(AppChrome.buttonBackgroundColor, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityID ?? systemName)
        .accessibilityLabel(accessibilityLabel ?? systemName)
    }
}

struct AppCheckbox: View {
    @Binding var isOn: Bool
    var label: String
    var isEnabled: Bool = true
    var boxSize: CGFloat = 28
    var cornerRadius: CGFloat = 6
    var borderColor: Color = AppChrome.primaryTextColor
    var fillColor: Color = AppChrome.buttonBackgroundColor
    var checkColor: Color = AppChrome.buttonForegroundColor
    var labelColor: Color = AppChrome.primaryTextColor
    var font: Font = .system(size: 18, weight: .medium)
    var accessibilityID: String? = nil

    var body: some View {
        Button {
            guard isEnabled else { return }
            isOn.toggle()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(borderColor, lineWidth: 2)
                        .background(
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .fill(isOn ? fillColor : Color.clear)
                        )
                        .frame(width: boxSize, height: boxSize)

                    if isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: boxSize * 0.55, weight: .bold))
                            .foregroundStyle(checkColor)
                    }
                }

                Text(label)
                    .font(font)
                    .foregroundStyle(labelColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityIdentifier(accessibilityID ?? label)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isOn ? "checked" : "unchecked")
    }
}

struct AppSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var isEnabled: Bool = true
    var trackHeight: CGFloat = 6
    var thumbSize: CGFloat = 22
    var activeTrackColor: Color = AppChrome.buttonBackgroundColor
    var inactiveTrackColor: Color = Color(white: 0.35)
    var thumbColor: Color = AppChrome.primaryTextColor
    var disabledOpacity: Double = 0.4
    var accessibilityID: String? = nil

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let progress = normalized(value)
            let thumbX = progress * width

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(inactiveTrackColor)
                    .frame(height: trackHeight)

                Capsule()
                    .fill(activeTrackColor)
                    .frame(width: max(thumbX, trackHeight), height: trackHeight)

                Circle()
                    .fill(thumbColor)
                    .frame(width: thumbSize, height: thumbSize)
                    .position(x: clampThumbX(thumbX, width: width), y: geo.size.height / 2)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard isEnabled else { return }
                        let fraction = min(1, max(0, drag.location.x / width))
                        value = range.lowerBound + fraction * (range.upperBound - range.lowerBound)
                    }
            )
        }
        .frame(height: max(thumbSize, 44))
        .opacity(isEnabled ? 1 : disabledOpacity)
        .allowsHitTesting(isEnabled)
        .accessibilityIdentifier(accessibilityID ?? "slider")
        .accessibilityValue(Text("\(Int((normalized(value) * 100).rounded())) percent"))
    }

    private func normalized(_ value: Double) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(1, max(0, (value - range.lowerBound) / span))
    }

    private func clampThumbX(_ x: CGFloat, width: CGFloat) -> CGFloat {
        let half = thumbSize / 2
        return min(width - half, max(half, x))
    }
}
