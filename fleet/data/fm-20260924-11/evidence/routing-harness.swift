import Foundation
import CryptoKit
func sha(_ d: Data) -> String { SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined() }
let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("fm2411-routing-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
let payload = Data("weights".utf8)
func model(_ id: String, _ file: String, _ mem: Int64) -> TransformModel {
    TransformModel(id: id, displayName: id, fileName: file,
                   downloadURL: URL(string: "https://example.invalid/\(file)")!,
                   sha256: sha(payload), sizeBytes: Int64(payload.count), memoryBytes: mem,
                   licence: "Apache-2.0", source: "test")
}
let shipped = model(TransformModelManager.defaultModelID, "1.5b.gguf", 1_159_641_497)
let eightBee = model(TransformModelManager.polishOutputModelID, "8b.gguf", 5_723_163_853)
let manager = TransformModelManager(directory: dir, catalogue: [shipped, eightBee])
var failures = 0
func check(_ label: String, _ got: TransformModel, _ expected: TransformModel) {
    let ok = got.id == expected.id
    if !ok { failures += 1 }
    print("\(ok ? "PASS" : "FAIL") \(label): \(got.id)  (expected \(expected.id))")
}
print("— 8B NOT installed (isPolishModelInstalled=\(manager.isPolishModelInstalled)) —")
check("tone EN formal", manager.model(for: .tone(language: .english, tone: .formal)), shipped)
check("tone PL casual", manager.model(for: .tone(language: .polish, tone: .casual)), shipped)
check("cleanUpWithTone EN", manager.model(for: .cleanUpWithTone(language: .english, tone: .formal)), shipped)
check("cleanup-only EN", manager.model(for: .cleanUp(language: .english)), shipped)
check("cleanup-only PL", manager.model(for: .cleanUp(language: .polish)), shipped)
let source = dir.appendingPathComponent("downloaded.gguf")
try payload.write(to: source)
try manager.install(fileAt: source, model: eightBee)
print("— 8B installed (isPolishModelInstalled=\(manager.isPolishModelInstalled)) —")
check("tone EN formal", manager.model(for: .tone(language: .english, tone: .formal)), eightBee)
check("tone PL formal", manager.model(for: .tone(language: .polish, tone: .formal)), eightBee)
check("cleanUpWithTone EN", manager.model(for: .cleanUpWithTone(language: .english, tone: .neutral)), eightBee)
check("cleanup-only EN", manager.model(for: .cleanUp(language: .english)), shipped)
check("cleanup-only PL", manager.model(for: .cleanUp(language: .polish)), eightBee)
try? FileManager.default.removeItem(at: dir)
print(failures == 0 ? "ROUTING TABLE OK" : "\(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
