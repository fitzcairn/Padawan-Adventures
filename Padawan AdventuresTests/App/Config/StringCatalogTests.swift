import Foundation
import Testing
@testable import Padawan_Adventures

struct StringCatalogTests {
    @Test func loadsFromBundleAndValidates() throws {
        let catalog = try StringCatalog.loadFromBundle()
        try catalog.validate()
        #expect(!catalog.entries.isEmpty)
    }

    @Test func everyEntryHasTextAndValidSfx() throws {
        let catalog = try StringCatalog.loadFromBundle()
        for (id, entry) in catalog.entries {
            #expect(!entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(id)")
            if !entry.sfx.isEmpty {
                #expect(entry.sfx.hasPrefix("sfx_ui_"), "\(id): \(entry.sfx)")
            }
        }
    }

    @Test func everyEntryHasContextAndBraceFreeSpoken() throws {
        let catalog = try StringCatalog.loadFromBundle()
        for (id, entry) in catalog.entries {
            #expect(!entry.context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(id) missing context")
            if entry.sfx.isEmpty {
                #expect(entry.spoken.isEmpty, "\(id) unspoken should not set spoken")
            } else {
                #expect(!entry.spoken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(id) missing spoken")
                #expect(!entry.spoken.contains("{"), "\(id) spoken has braces")
            }
        }
    }

    @Test func sfxValuesAreUnique() throws {
        let catalog = try StringCatalog.loadFromBundle()
        let sfxValues = catalog.entries.values.map(\.sfx).filter { !$0.isEmpty }
        #expect(Set(sfxValues).count == sfxValues.count)
    }

    @Test func fallbackMatchesBundledIdsAndText() throws {
        let bundled = try StringCatalog.loadFromBundle()
        let fallback = StringCatalog.fallback
        #expect(Set(fallback.entries.keys) == Set(bundled.entries.keys))
        for (id, entry) in bundled.entries {
            #expect(fallback.entry(id)?.text == entry.text, "\(id)")
        }
    }

    @Test @MainActor func textSubstitutesPlaceholders() {
        Strings._resetForTesting(
            StringCatalog(entries: [
                "menu_welcome_named": UIString(
                    id: "menu_welcome_named",
                    text: "Welcome, {name}",
                    sfx: "sfx_ui_menu_welcome_named",
                    context: "test",
                    spoken: "Welcome"
                ),
                "plain": UIString(
                    id: "plain",
                    text: "Hello {name} and {name}",
                    sfx: "sfx_ui_plain",
                    context: "test",
                    spoken: "Hello"
                ),
            ])
        )
        defer { Strings._resetForTesting(nil) }

        #expect(Strings.text("menu_welcome_named", ["name": "Galen"]) == "Welcome, Galen")
        #expect(Strings.text("plain", ["name": "Galen"]) == "Hello Galen and Galen")
        #expect(Strings.text("menu_welcome_named") == "Welcome, {name}")
    }

    @Test func rejectsMalformedYAML() {
        #expect(throws: StringCatalogError.self) {
            try StringCatalog.decode(from: """
            strings:
              broken:
                text: "Hello"
                spoken: "Hello"
            """)
        }
        #expect(throws: StringCatalogError.self) {
            try StringCatalog.decode(from: """
            strings:
              broken:
                text: "Hello {Name}"
                sfx: sfx_ui_broken
            """)
        }
        #expect(throws: StringCatalogError.self) {
            try StringCatalog.decode(from: """
            strings:
              broken:
                text: "Hello {name"
                sfx: sfx_ui_broken
            """)
        }
        #expect(throws: StringCatalogError.self) {
            try StringCatalog.decode(from: """
            strings:
              broken:
                text: "Hello {name}"
                spoken: "Hello {name}"
                sfx: sfx_ui_broken
            """)
        }
    }
}
