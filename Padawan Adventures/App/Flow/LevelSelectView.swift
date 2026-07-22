import SwiftUI

struct LevelSelectView: View {
    let session: AppSession
    let router: FlowRouter
    private let levels: [LevelDescriptor]

    init(
        session: AppSession,
        router: FlowRouter,
        levels: [LevelDescriptor]? = nil
    ) {
        self.session = session
        self.router = router
        self.levels = levels ?? LevelCatalog.loadFromBundle()
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            HStack(spacing: 8) {
                Image(systemName: "star.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 22, weight: .semibold))
                Text("\(session.playerState?.totalStars ?? 0)")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AppChrome.primaryTextColor)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("levelSelect.totalStars")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(levels, id: \.resourceName) { level in
                        AppLargeButton(
                            title: level.displayName,
                            accessibilityID: "levelSelect.\(level.resourceName)"
                        ) {
                            do {
                                try session.selectLevel(resourceName: level.resourceName)
                                router.navigate(to: .preparing(.newGame))
                            } catch {
                                // Ignore invalid/missing level resources.
                            }
                        }
                        .frame(minWidth: 160)
                    }
                }
                .padding(.horizontal)
            }

            Spacer()

            AppLargeButton(title: "Back", accessibilityID: "levelSelect.back") {
                if router.path.isEmpty {
                    router.showMenu()
                } else {
                    router.pop()
                }
            }
            .frame(maxWidth: 280)
            .padding(.bottom, 24)
        }
        .appScreenBackground()
        .playScreenMusic("level_select")
    }
}
