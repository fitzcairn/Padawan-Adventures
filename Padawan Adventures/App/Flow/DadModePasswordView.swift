import SwiftUI

/// Fullscreen 4-digit Dad mode password entry (on-screen keypad; no system keyboard).
struct DadModePasswordView: View {
    let expectedPassword: String
    let onSuccess: () -> Void
    let onCancel: () -> Void

    @State private var digits: [String] = []
    @State private var showIncorrect = false

    private let padRows: [[String]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["", "0", "⌫"],
    ]

    var body: some View {
        AppScreen {
            VStack(spacing: 24) {
                Spacer(minLength: 0)

                Text("Enter password")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(AppChrome.primaryTextColor)
                    .accessibilityIdentifier("dadModePassword.title")

                HStack(spacing: 16) {
                    ForEach(0..<4, id: \.self) { index in
                        Text(index < digits.count ? digits[index] : "")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(AppChrome.buttonForegroundColor)
                            .frame(width: 56, height: 64)
                            .background(AppChrome.buttonBackgroundColor, in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityIdentifier("dadModePassword.slot.\(index)")
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("dadModePassword.slots")

                if showIncorrect {
                    Text("incorrect")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("dadModePassword.incorrect")
                }

                VStack(spacing: 12) {
                    ForEach(Array(padRows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 12) {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, label in
                                padKey(label)
                            }
                        }
                    }
                }
                .frame(maxWidth: 280)
                .accessibilityIdentifier("dadModePassword.keypad")

                Spacer(minLength: 0)

                AppLargeButton(title: "Cancel", accessibilityID: "dadModePassword.cancel", action: onCancel)
                    .frame(maxWidth: 280)
            }
        }
    }

    @ViewBuilder
    private func padKey(_ label: String) -> some View {
        if label.isEmpty {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 52)
        } else {
            Button {
                handlePadTap(label)
            } label: {
                Text(label)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(AppChrome.buttonForegroundColor)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(AppChrome.buttonBackgroundColor, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(
                label == "⌫" ? "dadModePassword.key.delete" : "dadModePassword.key.\(label)"
            )
        }
    }

    private func handlePadTap(_ label: String) {
        showIncorrect = false
        if label == "⌫" {
            if !digits.isEmpty {
                digits.removeLast()
            }
            return
        }
        guard digits.count < 4, label.count == 1, label.first?.isNumber == true else { return }
        digits.append(label)
        if digits.count == 4 {
            submit()
        }
    }

    private func submit() {
        let entered = digits.joined()
        if DadModePassword.matches(entered: entered, expected: expectedPassword) {
            onSuccess()
        } else {
            showIncorrect = true
            digits = []
        }
    }
}

/// Pure password check shared with tests.
enum DadModePassword {
    static func matches(entered: String, expected: String) -> Bool {
        entered == expected
    }
}
