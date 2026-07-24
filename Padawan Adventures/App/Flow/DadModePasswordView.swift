import SwiftUI

/// Fullscreen 4-digit Dad mode password entry.
struct DadModePasswordView: View {
    let expectedPassword: String
    let onSuccess: () -> Void
    let onCancel: () -> Void

    @State private var digits: [String] = Array(repeating: "", count: 4)
    @State private var showIncorrect = false
    @FocusState private var focusedSlot: Int?

    var body: some View {
        AppScreen {
            VStack(spacing: 24) {
                Spacer()

                Text("Enter password")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(AppChrome.primaryTextColor)
                    .accessibilityIdentifier("dadModePassword.title")

                HStack(spacing: 16) {
                    ForEach(0..<4, id: \.self) { index in
                        TextField("", text: binding(for: index))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(AppChrome.buttonForegroundColor)
                            .frame(width: 56, height: 64)
                            .background(AppChrome.buttonBackgroundColor, in: RoundedRectangle(cornerRadius: 12))
                            .focused($focusedSlot, equals: index)
                            .accessibilityIdentifier("dadModePassword.slot.\(index)")
                    }
                }

                if showIncorrect {
                    Text("incorrect")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("dadModePassword.incorrect")
                }

                Spacer()

                AppLargeButton(title: "Cancel", accessibilityID: "dadModePassword.cancel", action: onCancel)
                    .frame(maxWidth: 280)
            }
        }
        .onAppear {
            focusedSlot = 0
        }
    }

    private func binding(for index: Int) -> Binding<String> {
        Binding(
            get: { digits[index] },
            set: { newValue in
                let filtered = newValue.filter(\.isNumber)
                if filtered.isEmpty {
                    digits[index] = ""
                    showIncorrect = false
                    return
                }
                let digit = String(filtered.suffix(1))
                digits[index] = digit
                showIncorrect = false

                if index < 3 {
                    focusedSlot = index + 1
                } else {
                    focusedSlot = nil
                    submitIfComplete()
                }
            }
        )
    }

    private func submitIfComplete() {
        let entered = digits.joined()
        guard entered.count == 4 else { return }
        if entered == expectedPassword {
            onSuccess()
        } else {
            showIncorrect = true
            digits = Array(repeating: "", count: 4)
            focusedSlot = 0
        }
    }
}
