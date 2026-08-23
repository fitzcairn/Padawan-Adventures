import Foundation
import Yams

/// YAML shape for one entry under `strings.<id>:`.
nonisolated struct UIStringSpec: Decodable, Equatable, Sendable {
    var text: String?
    var sfx: String?
    var context: String?
    /// Brace-free form for voice-over; defaults to `text`.
    var spoken: String?
}

nonisolated struct UIString: Equatable, Sendable {
    var id: String
    var text: String
    var sfx: String
    var context: String
    var spoken: String
}

/// UI copy loaded from `Resources/Config/Catalogs/strings.yaml`.
nonisolated struct StringCatalog: Equatable, Sendable {
    static let subdirectory = ConfigPath.catalogRoot

    private(set) var entries: [String: UIString]

    func entry(_ id: String) -> UIString? {
        entries[id]
    }

    /// Text-only safety net for Release when the YAML fails to load.
    /// `sfx` is derived as `sfx_ui_<id>` because voice-over is optional in that path.
    nonisolated static let fallback = StringCatalog(texts: [
        "button_back": "Back",
        "button_cancel": "Cancel",
        "button_ok": "OK",
        "button_delete": "Delete",
        "button_new": "New",
        "loading_loading": "Loading...",
        "loading_tap_to_start": "Tap to start",
        "preparing_takeoff": "PREPARING FOR TAKEOFF...",
        "preparing_error_title": "COULD NOT LOAD ENEMIES",
        "preparing_error_body": "Oops!  Problem there was.  Select a new level, you must.",
        "menu_welcome": "Welcome",
        "menu_welcome_named": "Welcome, {name}",
        "menu_continue": "CONTINUE",
        "menu_new_game": "NEW GAME",
        "menu_new_game_confirm": "This will restart your game!  Are you sure?",
        "menu_settings": "SETTINGS",
        "menu_quit": "EXIT",
        "cutscene_tap_to_skip": "Tap to skip",
        "player_select_title": "Select Player",
        "player_select_empty": "No players yet. Tap New to create one.",
        "player_new_title": "New Player",
        "player_new_message": "Enter a unique player name.",
        "player_name_placeholder": "Player name",
        "player_delete_title": "Delete Player",
        "player_delete_message": "Delete \"{name}\" and all saved progress? This cannot be undone.",
        "player_name_taken_title": "Name Already Taken",
        "player_name_taken_message": "Player names must be unique. Choose a different name.",
        "player_default_name": "Padawan",
        "selfie_title": "Smile, {name}!",
        "selfie_capture": "Click!",
        "selfie_camera_unavailable": "Camera unavailable",
        "settings_title": "Settings",
        "settings_sound_effects": "Sound Effects",
        "settings_music": "Music",
        "level_select_dad_mode": "Dad mode",
        "level_select_inventory": "Inventory",
        "level_locked": "Complete the current level first!",
        "dad_mode_unlocked": "Dad mode unlocked!",
        "level_tython": "Tython",
        "level_tatooine": "Tatooine",
        "level_ilum": "Ilum",
        "level_kashyyyk": "Kashyyyk",
        "level_dagobah": "Dagobah",
        "level_coruscant": "Coruscant",
        "level_mustafar": "Mustafar",
        "level_geonosis": "Geonosis",
        "level_default": "Level",
        "planet_high_score": "High Score: {stars}",
        "level_detail_replay_prompt": "Highest score:",
        "level_detail_continue_prompt": "Continue your adventure on {planet}?",
        "level_detail_start_over": "Start over!",
        "level_detail_take_off": "Let's go!",
        "level_detail_not_ready": "Not yet.",
        "level_detail_try_again": "Let's go!",
        "level_detail_no_thanks": "Not yet.",
        "dad_mode_enter_password": "Enter password",
        "dad_mode_incorrect": "Incorrect",
        "you_win": "You win!",
        "you_win_high_score": "New high score!",
        "campaign_win_congratulations": "Congratulations!",
        "campaign_win_tap_to_play_more": "tap to play more",
        "minigame_coins_won": "You won {coins} coins!",
        "minigame_tutorial_sound_out_word_pit": "Tutorial goes here",
        "minigame_tutorial_ending_sound_pit": "Tutorial goes here",
        "minigame_tutorial_starting_sound_pit": "Tutorial goes here",
        "minigame_tutorial_sound_out_word_gate": "Tutorial goes here",
        "minigame_tutorial_grapheme_sound_gate": "Tutorial goes here",
        "minigame_tutorial_starting_sound_gate": "Tutorial goes here",
        "minigame_tutorial_ending_sound_gate": "Tutorial goes here",
        "minigame_tutorial_grapheme_sound_combat": "The monster throws letters at you. Slash the letter you hear to send it back. A wrong letter flashes and fades — keep going until you find the right one.",
        "minigame_tutorial_starting_sound_combat": "The monster throws a word with its first sound missing. Tap the word to hear it, then tap the circle with the missing sound to send it back. A wrong circle mixes the rings up — keep looking until you find the right one.",
        "minigame_tutorial_ending_sound_combat": "The monster throws a word with its last sound missing. Tap the word to hear it, then tap the circle with the missing sound to send it back. A wrong circle mixes the rings up — keep looking until you find the right one.",
        "minigame_tutorial_continue": "Tap to continue",
        "defeated": "Defeated",
        "hud_flee": "Flee the planet!",
        "hud_leave": "Leave",
        "control_checked": "checked",
        "control_unchecked": "unchecked",
        "control_percent": "{percent} percent",
        "world_tutorial_intro": "Tap where you want to go. Drag to look around.",
        "world_tutorial_tap_to_continue": "Tap to continue",
        "merchant_item_bridge": "this is a bridge, it looks great",
        "merchant_item_crystal_green": "this is a green crystal, it looks great",
        "merchant_item_crystal_purple": "this is a purple crystal, it looks great",
        "merchant_item_crystal_yellow": "this is a yellow crystal, it looks great",
        "merchant_item_double_saber": "this is a double saber, it looks great",
        "merchant_item_jetpack": "this is a jetpack, it looks great",
        "merchant_item_satelite": "this is a satelite, it looks great",
        "merchant_item_scanner": "this is a scanner, it looks great",
        "merchant_item_vector": "this is a vector, it looks great",
        "merchant_replace_item": "Replace item?",
        "merchant_coins_spent": "You spent {coins} coins!",
    ])

    nonisolated init(entries: [String: UIString]) {
        self.entries = entries
    }

    /// Builds a catalog from id → text, deriving `sfx_ui_<id>` for each entry.
    nonisolated init(texts: [String: String]) {
        var resolved: [String: UIString] = [:]
        resolved.reserveCapacity(texts.count)
        for (id, text) in texts {
            resolved[id] = UIString(
                id: id,
                text: text,
                sfx: "sfx_ui_\(id)",
                context: "",
                spoken: text
            )
        }
        self.entries = resolved
    }

    func validate() throws {
        guard !entries.isEmpty else {
            throw StringCatalogError.invalid("strings catalog must not be empty")
        }
        for (id, entry) in entries {
            let text = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw StringCatalogError.invalid("\(id).text must be non-empty")
            }
            let sfx = entry.sfx.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sfx.isEmpty else {
                throw StringCatalogError.invalid("\(id).sfx must be non-empty")
            }
            guard sfx.hasPrefix("sfx_ui_") else {
                throw StringCatalogError.invalid("\(id).sfx must start with sfx_ui_")
            }
            if entry.spoken.contains("{") {
                throw StringCatalogError.invalid("\(id).spoken must not contain brace placeholders")
            }
            try Self.validatePlaceholders(in: entry.text, id: id)
        }
    }

    static func loadFromBundle(
        named name: String = "strings",
        withExtension ext: String = "yaml",
        subdirectory: String? = subdirectory
    ) throws -> StringCatalog {
        let data = try ConfigStore.data(
            at: ConfigPath(basename: name, subdirectory: subdirectory)
        )
        return try decode(from: data)
    }

    static func decode(from data: Data) throws -> StringCatalog {
        do {
            let decoded = try YAMLDecoder().decode(StringCatalogDTO.self, from: data)
            var resolved: [String: UIString] = [:]
            resolved.reserveCapacity(decoded.strings.count)
            for (key, spec) in decoded.strings {
                guard let entry = resolveEntry(id: key, spec: spec) else {
                    throw StringCatalogError.invalid("\(key) is missing required text/sfx")
                }
                resolved[key] = entry
            }
            let catalog = StringCatalog(entries: resolved)
            try catalog.validate()
            return catalog
        } catch let error as StringCatalogError {
            throw error
        } catch {
            throw StringCatalogError.invalid(String(describing: error))
        }
    }

    static func decode(from yaml: String) throws -> StringCatalog {
        try decode(from: Data(yaml.utf8))
    }

    nonisolated static func resolveEntry(id: String, spec: UIStringSpec?) -> UIString? {
        guard let spec,
              let text = trimmedNonEmpty(spec.text),
              let sfx = trimmedNonEmpty(spec.sfx) else {
            return nil
        }
        let context = trimmedNonEmpty(spec.context) ?? ""
        let spoken = trimmedNonEmpty(spec.spoken) ?? text
        return UIString(id: id, text: text, sfx: sfx, context: context, spoken: spoken)
    }

    private nonisolated static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func validatePlaceholders(in text: String, id: String) throws {
        var depth = 0
        var current = ""
        for character in text {
            if character == "{" {
                depth += 1
                guard depth == 1 else {
                    throw StringCatalogError.invalid("\(id).text has nested braces")
                }
                current = ""
                continue
            }
            if character == "}" {
                guard depth == 1 else {
                    throw StringCatalogError.invalid("\(id).text has unbalanced braces")
                }
                depth = 0
                guard !current.isEmpty,
                      current.unicodeScalars.allSatisfy({ Self.placeholderScalars.contains($0) }) else {
                    throw StringCatalogError.invalid(
                        "\(id).text placeholder '{\(current)}' must match [a-z_]+"
                    )
                }
                continue
            }
            if depth == 1 {
                current.append(character)
            }
        }
        guard depth == 0 else {
            throw StringCatalogError.invalid("\(id).text has unbalanced braces")
        }
    }

    private static let placeholderScalars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz_")
}

private nonisolated struct StringCatalogDTO: Decodable {
    var strings: [String: UIStringSpec?]
}

nonisolated enum StringCatalogError: Error, Equatable {
    case invalid(String)
}
