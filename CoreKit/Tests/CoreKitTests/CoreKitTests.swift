import Testing
@testable import CoreKit

@Test func coreKitImportWorks() async throws {
    // 確認 CoreKit 模組可正常匯入
    let engine = ASREngineType.whisperTurbo
    #expect(engine.rawValue == "whisper_turbo")
}
