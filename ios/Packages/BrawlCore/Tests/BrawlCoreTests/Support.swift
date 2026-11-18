import Foundation
@testable import BrawlCore

enum Fixtures {
    static let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")
    static func data(_ name: String) -> Data { try! Data(contentsOf: dir.appendingPathComponent(name)) }
    static let catalog: EngineCatalog = try! JSONDecoder().decode(EngineCatalog.self, from: data("catalog.json"))
    static func result(_ name: String) -> EngineResult { try! JSONDecoder().decode(EngineResult.self, from: data(name + ".json")) }
    static func map(_ id: Int, _ mode: String? = nil) -> CatalogMap { catalog.maps.first { $0.id == .number(id) && (mode == nil || $0.mode == mode) }! }
    static func brawler(_ en: String) -> CatalogBrawler { catalog.brawlers.first { $0.name == en }! }
}

func line(_ t: String, x: Double = 0.5, y: Double = 0.1, conf: Double = 0.9) -> OCRLine { OCRLine(text: t, confidence: conf, midX: x, midY: y) }

func tempStore() -> SharedStore {
    SharedStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("brawlcore-test-\(UUID().uuidString)"))
}
