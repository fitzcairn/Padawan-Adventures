import Foundation
import Testing
@testable import Padawan_Adventures

struct TerrainCatalogTests {
    private let desertAccents = [
        "boulder-red", "boulder", "boulder-wide", "boulder-gray",
        "rocks-small", "rocks-pile", "rocks-scatter", "rocks-gray", "rocks-dark", "rocks-mixed",
    ]
    private let desertSpecials = [
        "canyon", "canyon-mesa", "canyon-ridge", "meteorite", "meteorite-cracked",
    ]
    private let dirtAccents = [
        "rocks-small", "rocks-pile", "rocks-scatter", "rocks-gray", "rocks-dark", "rocks-mixed",
        "stump", "stump-mossy", "stump-carved", "stump-small",
    ]
    private let dirtVolcanicAccents = [
        "rock-volcanic", "rock-lava", "ember-spark", "rocks-dark",
        "stump", "stump-mossy", "stump-carved", "stump-small",
    ]
    private let grasslandAccents = [
        "flora-teal", "flora-sparse", "flora-odd", "flowers", "flowers-green", "flowers-yellow",
        "log", "log-mossy", "stump", "stump-mossy", "stump-carved", "stump-small",
        "rocks-small", "rocks-pile", "rocks-scatter", "rocks-gray", "rocks-dark", "rocks-mixed",
    ]
    private let grasslandSpecials = [
        "foliage", "foliage-lush", "foliage-dark",
        "mushroom", "mushroom-blue", "mushroom-glow", "flora-mixed",
    ]
    private let industrialAccents = ["sparkle", "sparkle-soft", "ember-spark"]
    private let swampAccents = [
        "log", "log-mossy", "stump", "stump-mossy", "stump-carved", "stump-small",
        "flora-teal", "flora-sparse", "flora-odd",
    ]
    private let waterAccents = ["sparkle", "sparkle-soft", "whirlpool"]
    private let iceWaterAccents = ["ice-block", "sparkle", "sparkle-soft"]
    private let iceWaterSpecials = [
        "ice-cave", "ice-arch", "ice-shard", "ice-crystal", "ice-spire", "ice-ridge",
        "iceberg", "iceberg-tall", "iceberg-wide", "glacier", "glacier-wall",
    ]

    @Test func resolvesPalettesFromInlineYAML() throws {
        let yaml = """
        sprite:
          root: Sprites/Floor
          sheet: floor-spritesheet
          atlas_root: Sprites/Floor
          atlas: atlas
        palettes:
          desert:
            accents: [boulder, rocks-small]
            specials: [canyon]
        terrains:
          sand: { row: 0, col: 0, palette: desert }
          sand-override:
            row: 0
            col: 1
            palette: desert
            accents: [boulder-red]
            specials: []
          flora-teal: { row: 3, col: 8, type: accent }
          foliage: { row: 3, col: 0, type: special }
        """
        let catalog = try TerrainCatalog.decode(from: Data(yaml.utf8))
        #expect(catalog.terrains["sand"]?.type == .base)
        #expect(catalog.accents(for: "sand") == ["boulder", "rocks-small"])
        #expect(catalog.specials(for: "sand") == ["canyon"])
        #expect(catalog.accents(for: "sand-override") == ["boulder-red"])
        #expect(catalog.specials(for: "sand-override") == [])
        #expect(catalog.terrains["flora-teal"]?.type == .accent)
        #expect(catalog.accents(for: "flora-teal") == [])
        #expect(catalog.specials(for: "flora-teal") == [])
        #expect(catalog.accents(for: "foliage") == [])
        #expect(catalog.specials(for: "foliage") == [])
    }

    @Test func rejectsUnknownPaletteName() {
        let yaml = """
        sprite:
          root: Sprites/Floor
          sheet: floor-spritesheet
          atlas_root: Sprites/Floor
          atlas: atlas
        palettes:
          desert:
            accents: []
            specials: []
        terrains:
          sand: { row: 0, col: 0, palette: missing }
        """
        #expect(throws: TerrainCatalogError.decodeFailed("Unknown palette 'missing' for terrain 'sand'")) {
            try TerrainCatalog.decode(from: Data(yaml.utf8))
        }
    }

    @Test func bundleCatalogResolvesEveryPaletteGroup() throws {
        let catalog = try TerrainCatalog.loadFromBundle()
        #expect(catalog.terrains.count == 115)

        // Known ids
        for id in ["sand", "grass", "flora-teal", "foliage", "water", "swamp", "pit", "grate"] {
            #expect(catalog.terrains[id] != nil, "missing terrain id \(id)")
        }

        // desert
        #expect(catalog.accents(for: "sand") == desertAccents)
        #expect(catalog.specials(for: "sand") == desertSpecials)
        #expect(catalog.accents(for: "sand-dune") == desertAccents)
        #expect(catalog.specials(for: "sand-pale") == desertSpecials)

        // dirt
        #expect(catalog.accents(for: "dirt-arid") == dirtAccents)
        #expect(catalog.specials(for: "dirt-arid") == [])
        #expect(catalog.accents(for: "dirt-patchy") == dirtAccents)

        // dirt_volcanic
        #expect(catalog.accents(for: "dirt-dark") == dirtVolcanicAccents)
        #expect(catalog.accents(for: "dirt-scorched") == dirtVolcanicAccents)
        #expect(catalog.specials(for: "dirt-dark") == [])

        // grassland
        #expect(catalog.accents(for: "grass") == grasslandAccents)
        #expect(catalog.specials(for: "grass") == grasslandSpecials)
        #expect(catalog.accents(for: "plank") == grasslandAccents)
        #expect(catalog.specials(for: "grass-soft") == grasslandSpecials)

        // industrial
        #expect(catalog.accents(for: "grate") == industrialAccents)
        #expect(catalog.accents(for: "metal-rust") == industrialAccents)
        #expect(catalog.accents(for: "reflect") == industrialAccents)
        #expect(catalog.specials(for: "grate") == [])

        // swamp
        #expect(catalog.accents(for: "swamp") == swampAccents)
        #expect(catalog.specials(for: "swamp") == ["swamp-roots"])
        #expect(catalog.accents(for: "swamp-glow") == swampAccents)

        // water
        #expect(catalog.accents(for: "water") == waterAccents)
        #expect(catalog.accents(for: "water-shallow") == waterAccents)
        #expect(catalog.specials(for: "water") == [])

        // ice_water
        #expect(catalog.accents(for: "water-ice") == iceWaterAccents)
        #expect(catalog.specials(for: "water-ice") == iceWaterSpecials)
        #expect(catalog.specials(for: "water-mirror") == iceWaterSpecials)

        // empty
        #expect(catalog.accents(for: "pit") == [])
        #expect(catalog.specials(for: "pit-deep") == [])

        // accent / special types always empty placement lists
        for (id, def) in catalog.terrains where def.type != .base {
            #expect(def.accents.isEmpty, "\(id) should have empty accents")
            #expect(def.specials.isEmpty, "\(id) should have empty specials")
        }
    }

    @Test func bundleCatalogPreservesRowColAndBaseTypeDefault() throws {
        let catalog = try TerrainCatalog.loadFromBundle()
        let sand = try #require(catalog.terrains["sand"])
        #expect(sand.row == 0)
        #expect(sand.col == 0)
        #expect(sand.type == .base)

        let flora = try #require(catalog.terrains["flora-teal"])
        #expect(flora.row == 3)
        #expect(flora.col == 8)
        #expect(flora.type == .accent)

        let waterMirror = try #require(catalog.terrains["water-mirror"])
        #expect(waterMirror.row == 10)
        #expect(waterMirror.col == 10)
        #expect(waterMirror.type == .base)
    }
}
