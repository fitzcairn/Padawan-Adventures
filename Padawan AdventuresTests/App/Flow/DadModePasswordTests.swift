import Testing
@testable import Padawan_Adventures

struct DadModePasswordTests {
    @Test func matchesExactFourDigits() {
        #expect(DadModePassword.matches(entered: "1234", expected: "1234"))
        #expect(!DadModePassword.matches(entered: "1235", expected: "1234"))
        #expect(!DadModePassword.matches(entered: "123", expected: "1234"))
        #expect(!DadModePassword.matches(entered: "01234", expected: "1234"))
    }
}
