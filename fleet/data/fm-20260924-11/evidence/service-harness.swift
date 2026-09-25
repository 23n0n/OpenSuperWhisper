import Foundation
import CryptoKit
func sha(_ d: Data) -> String { SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined() }
let payload = Data("weights".utf8)
let shipped = TransformModel(id: TransformModelManager.defaultModelID, displayName: "Qwen2.5 1.5B Instruct (Q4_K_M)",
    fileName: "1.5b.gguf", downloadURL: URL(string: "https://example.invalid/1.5b")!, sha256: sha(payload),
    sizeBytes: Int64(payload.count), memoryBytes: 1_159_641_497, licence: "Apache-2.0", source: "test")
let eightBee = TransformModel(id: TransformModelManager.polishOutputModelID, displayName: "Qwen3 8B (Q4_K_M)",
    fileName: "8b.gguf", downloadURL: URL(string: "https://example.invalid/8b")!, sha256: sha(payload),
    sizeBytes: Int64(payload.count), memoryBytes: 5_723_163_853, licence: "Apache-2.0", source: "test")

actor Recorder {
    var calls: [(String, String, String)] = []
    func add(_ s: String, _ u: String, _ m: String) { calls.append((s, u, m)) }
    func all() -> [(String, String, String)] { calls }
}
let recorder = Recorder()

/// The service exactly as the app builds it, except that the runtime answers
/// with `answer` and the model resolver is the real one over a fake catalogue.
func makeService(tone: ToneMode, cleanUp: Bool, answer: String, installEightBee: Bool = false) -> TransformService {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("fm2411-service-\(UUID().uuidString)")
    let manager = TransformModelManager(directory: directory, catalogue: [shipped, eightBee])
    if installEightBee {
        let source = directory.appendingPathComponent("downloaded.gguf")
        try? payload.write(to: source)
        try? manager.install(fileAt: source, model: eightBee)
    }
    return TransformService(
        localTransform: { systemPrompt, userText, model in
            await recorder.add(systemPrompt, userText, model.id)
            return answer
        },
        modelForPolicy: { manager.model(for: $0) },
        gateSettings: { GateSettings(tone: true, cleanUp: cleanUp, toneMode: tone) }
    )
}

print("=== the system prompt a Polish formal tone turn sends ===")
print(TransformService.systemPrompt(for: .tone(language: .polish, tone: .formal), cleanUp: false))
print("=== the framed user turn ===")
print(TransformService.userPrompt(for: "wyślij raport do klienta dzisiaj", language: .polish, tone: .formal))
print("=== the system prompt clean-up alone sends (unchanged wording) ===")
print(TransformService.systemPrompt(for: .cleanUp(language: .english), cleanUp: true))
print("=== clean-up alone: the user turn is still the bare transcript (chained below) ===")

var failures = 0
func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    if !ok { failures += 1 }
    print("\(ok ? "PASS" : "FAIL") \(label)\(detail.isEmpty ? "" : ": \(detail)")")
}

let text = "wyślij raport do klienta dzisiaj"
// 1. a good answer is delivered, and the turn was framed
let good = makeService(tone: .formal, cleanUp: false, answer: "Proszę wysłać raport do klienta dzisiaj.",
                       installEightBee: true)
let goodOutcome = await good.transformDetailed(text, sourceLanguage: "pl")
check("good answer delivered", goodOutcome.text == "Proszę wysłać raport do klienta dzisiaj.")
check("no rejection recorded", goodOutcome.guardRejection == nil)
let calls = await recorder.all()
check("turn was framed", calls.last?.1.contains("<<<TRANSCRIPT") == true, calls.last?.1 ?? "")
check("prompt names the language", calls.last?.0.contains("in Polish") == true)
check("tone ran on the 8B once it is installed (Polish)", calls.last?.2 == TransformModelManager.polishOutputModelID,
      calls.last?.2 ?? "")

// the same tone job in ENGLISH, 8B installed -> still the 8B; 8B absent -> shipped
let englishToneInstalled = makeService(tone: .casual, cleanUp: false, answer: "Send the report today.",
                                       installEightBee: true)
_ = await englishToneInstalled.transformDetailed("send the report today", sourceLanguage: "en")
let installedCalls = await recorder.all()
check("English tone ran on the 8B once it is installed",
      installedCalls.last?.2 == TransformModelManager.polishOutputModelID, installedCalls.last?.2 ?? "")

let englishToneAbsent = makeService(tone: .casual, cleanUp: false, answer: "Send the report today.")
_ = await englishToneAbsent.transformDetailed("send the report today", sourceLanguage: "en")
let absentCalls = await recorder.all()
check("English tone falls back to the shipped model without the 8B",
      absentCalls.last?.2 == TransformModelManager.defaultModelID, absentCalls.last?.2 ?? "")

// 2. the measured 1.5B failures: frame, label, stub, flip -> transcript + notice
let frameAnswer = "Oczywiście, wysyłam raport do klienta dzisiaj."
let frameService = makeService(tone: .formal, cleanUp: false, answer: frameAnswer)
let frameOutcome = await frameService.transformDetailed(text, sourceLanguage: "pl")
check("assistant frame rejected", frameOutcome.text == text, frameOutcome.text)
check("rejection recorded", frameOutcome.guardRejection == .assistantFrame("oczywiście"),
      "\(String(describing: frameOutcome.guardRejection))")

let labelService = makeService(tone: .formal, cleanUp: false, answer: "Register: formal\nProszę wysłać raport.")
let labelOutcome = await labelService.transformDetailed(text, sourceLanguage: "pl")
check("label rejected", labelOutcome.text == text)
check("label recorded", labelOutcome.guardRejection == .label("register:"))

let flipService = makeService(tone: .formal, cleanUp: false,
                              answer: "Please send the report to the client today.")
let flipOutcome = await flipService.transformDetailed(text, sourceLanguage: "pl")
check("language flip rejected", flipOutcome.text == text)
check("flip recorded", flipOutcome.guardRejection == .languageFlip(expected: .polish))

let longText = "ok so the plan is first we test then we deploy and then we watch the logs"
let stubService = makeService(tone: .neutral, cleanUp: false, answer: "Plan done.")
let stubOutcome = await stubService.transformDetailed(longText, sourceLanguage: "en")
check("stub rejected", stubOutcome.text == longText)
check("stub recorded", stubOutcome.guardRejection == .stub(wordsIn: 17, wordsOut: 2))

// 3. clean-up alone is not guarded, and its model stays the language's
let cleanup = makeService(tone: .formal, cleanUp: true, answer: "Oczywiście, wysyłam raport do klienta dzisiaj.")
let cleanupOutcome = await cleanup.transformDetailed(text, sourceLanguage: "pl")
check("clean-up-with-tone IS guarded", cleanupOutcome.text == text)
let cleanupOnly = TransformService(
    localTransform: { _, _, model in
        await recorder.add("", "", model.id)
        return "Oczywiście, wysyłam raport do klienta dzisiaj."
    },
    modelForPolicy: { policy in policy.language == .polish ? eightBee : shipped },
    gateSettings: { GateSettings(tone: false, cleanUp: true, toneMode: .neutral) })
let cleanupOnlyOutcome = await cleanupOnly.transformDetailed("please send the report", sourceLanguage: "en")
check("clean-up alone delivers the answer unguarded",
      cleanupOnlyOutcome.text == "Oczywiście, wysyłam raport do klienta dzisiaj.")
check("clean-up alone records no rejection", cleanupOnlyOutcome.guardRejection == nil)
let cleanupCalls = await recorder.all()
check("English clean-up alone ran the shipped model", cleanupCalls.last?.2 == TransformModelManager.defaultModelID,
      cleanupCalls.last?.2 ?? "")

// 4. the notice the user sees
await MainActor.run {
    let reported = AppErrorCenter.shared.reported
    check("a notice was shown once per rejection", reported.count >= 4, "\(reported.count)")
    for (title, message) in reported.prefix(1) { print("NOTICE: \(title) — \(message)") }
}
print(failures == 0 ? "SERVICE CHECKS OK" : "\(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
