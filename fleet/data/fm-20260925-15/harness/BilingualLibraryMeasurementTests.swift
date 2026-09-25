import Foundation
import XCTest

@testable import OpenSuperWhisper

/// Two properties, on the captain's own voice and on his whole library, through
/// the app's own path: **the language that went in is the language that comes
/// out, and the transform does not damage what it rewrites.**
///
/// Opt-in exactly like `WhisperPauseBoundaryMeasurementTests`: the recordings
/// directory, a multilingual whisper model and the evidence file come from
/// `OSW_TEST_CAPTAIN_RECORDINGS`, `OSW_TEST_MULTILINGUAL_MODEL` and
/// `OSW_TEST_EVIDENCE`. Nothing here runs in the plain suite and nothing here
/// touches the app: it decodes, scrubs, transforms and measures.
///
/// The chain reproduced per recording is the shipping one
/// (`Indicator/IndicatorWindow.swift:305-353`):
///
///     engine → raw transcript → DictationScrubber → TransformService → pasted text
///
/// with the captain's own switches (`toneEnabled = 1`, `cleanUpDictation` unset,
/// i.e. the default `true`, `transformToneMode = neutral`, `transformReference`
/// empty, `initialPrompt` empty, `longPausesEndSentences` unset) and the weights
/// the app's own `TransformModelManager` resolves for each policy. The models are
/// hard-linked into a scratch directory — nothing is copied and the files in
/// `~/Library/Application Support` are never written.
///
/// Language is the app's own `LanguageDetector` and nothing else. The gate's
/// decision is the app's own (`TransformPolicy.resolve`, on the engine's
/// language with the detector as its documented fallback), and both are printed
/// per recording so the two can be compared.
final class BilingualLibraryMeasurementTests: XCTestCase {

    // MARK: - The recordings the captain made for exactly this

    private struct Anchor {
        let label: String
        let fileName: String
        let duration: Double
        let storedOpening: String
    }

    /// Reported in full, verbatim, before anything else.
    private static let anchors = [
        Anchor(
            label: "pl anchor (117.8 s)",
            fileName: "9039BAB0-CBA2-49B2-82E1-432FF7B94589.wav",
            duration: 117.8,
            storedOpening: "Ok, więc teraz muszę przez dwie minuty coś dyktować w języku polskim"
        ),
        Anchor(
            label: "en anchor (131.1 s)",
            fileName: "29EA0AEA-06B0-4FE1-B189-18A21822F35A.wav",
            duration: 131.1,
            storedOpening: "Okay, now I'm recording in English. So we can have some reference material"
        ),
        Anchor(
            label: "en short (29.0 s)",
            fileName: "FD7B4C64-0AD7-4431-84D6-6F9EAFC77512.wav",
            duration: 29.0,
            storedOpening: "I check if my recordings are okay, if it's good to test with them"
        ),
    ]

    // MARK: - The captain's settings, read from his own domain

    /// His switches as `defaults read ru.starmel.OpenSuperWhisper` reports them,
    /// read directly at run time rather than assumed: the whisper half is his
    /// decoder settings (`initialPrompt` empty, greedy, temperature 0, no-speech
    /// 0.6, blank suppression on, the pause switch unset → off) and the transform
    /// half is tone on, clean-up on (the key is absent, and the default is on),
    /// neutral register, empty reference.
    private struct CaptainConfiguration {
        let toneEnabled: Bool
        let cleanUpEnabled: Bool
        let toneMode: ToneMode
        let reference: String
        let initialPrompt: String
        let longPausesEndSentences: Bool
        let source: String

        var gateSettings: GateSettings {
            GateSettings(
                tone: toneEnabled,
                cleanUp: cleanUpEnabled,
                toneMode: toneMode,
                reference: reference
            )
        }

        func whisperSettings() -> Settings {
            var settings = Settings()
            settings.showTimestamps = false
            settings.temperature = 0
            settings.noSpeechThreshold = 0.6
            settings.suppressBlankAudio = true
            settings.useBeamSearch = false
            settings.initialPrompt = initialPrompt
            settings.longPausesEndSentences = longPausesEndSentences
            return settings
        }

        var pausePolicy: WhisperEngine.PauseBoundaryPolicy {
            longPausesEndSentences ? .restored : .upstream
        }
    }

    /// Reads his domain with `defaults export` (a plain plist read; nothing is
    /// written), and falls back to the documented defaults when the domain is
    /// not on this machine.
    private func captainConfiguration() -> CaptainConfiguration {
        var stored: [String: Any] = [:]
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["export", "ru.starmel.OpenSuperWhisper", "-"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        if (try? process.run()) != nil {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
               let dictionary = plist as? [String: Any] {
                stored = dictionary
            }
        }

        let tone = (stored["toneEnabled"] as? NSNumber)?.boolValue
        let cleanUp = (stored["cleanUpDictation"] as? NSNumber)?.boolValue
        let toneMode = (stored["transformToneMode"] as? String).flatMap { ToneMode(rawValue: $0) }
        let reference = stored["transformReference"] as? String
        let prompt = stored["initialPrompt"] as? String
        let longPauses = (stored["longPausesEndSentences"] as? NSNumber)?.boolValue

        return CaptainConfiguration(
            toneEnabled: tone ?? false,
            cleanUpEnabled: cleanUp ?? true,
            toneMode: toneMode ?? .neutral,
            reference: reference ?? "",
            initialPrompt: prompt ?? "",
            longPausesEndSentences: longPauses ?? false,
            source: stored.isEmpty ? "domain unreadable, defaults used" : "his domain, read at run time"
        )
    }

    // MARK: - The library

    private struct LibraryRow {
        let timestamp: String
        let fileName: String
        let duration: Double
        let stored: String
        let status: String
    }

    /// The rows of `recordings.sqlite`, read through the `sqlite3` binary in
    /// read-only mode: the harness never opens the captain's store for writing.
    private func libraryRows(databasePath: String) -> [LibraryRow] {
        guard FileManager.default.fileExists(atPath: databasePath) else { return [] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [
            "-json", "-readonly", databasePath,
            "select timestamp, fileName, duration, transcription, status from recordings order by timestamp;",
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return parsed.compactMap { entry in
            guard let fileName = entry["fileName"] as? String else { return nil }
            return LibraryRow(
                timestamp: entry["timestamp"] as? String ?? "",
                fileName: fileName,
                duration: (entry["duration"] as? NSNumber)?.doubleValue ?? 0,
                stored: entry["transcription"] as? String ?? "",
                status: entry["status"] as? String ?? ""
            )
        }
    }

    // MARK: - Text work

    private func language(_ text: String) -> LanguageDetector.Verdict {
        LanguageDetector.detect(text)
    }

    private func label(_ verdict: LanguageDetector.Verdict) -> String {
        switch verdict {
        case .polish: return "pl"
        case .english: return "en"
        case .unknown: return "unknown"
        }
    }

    private func words(_ text: String) -> [String] {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    /// Words present in `baseline` and not in `text` (dropped), and the other
    /// way round (added), in order, by an LCS diff of case-folded words. This is
    /// the word-level accounting the brief asks for: a word the model invented
    /// shows up as added, one it dropped as dropped, and a re-ordered sentence
    /// shows up as neither.
    private func wordDiff(baseline: String, text: String) -> (dropped: [String], added: [String]) {
        let baselineWords = words(baseline)
        let textWords = words(text)
        let a = baselineWords.map { $0.lowercased() }
        let b = textWords.map { $0.lowercased() }
        guard !a.isEmpty || !b.isEmpty else { return ([], []) }

        var table = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)
        if !a.isEmpty && !b.isEmpty {
            for i in stride(from: a.count - 1, through: 0, by: -1) {
                for j in stride(from: b.count - 1, through: 0, by: -1) {
                    table[i][j] = a[i] == b[j]
                        ? table[i + 1][j + 1] + 1
                        : max(table[i + 1][j], table[i][j + 1])
                }
            }
        }

        var dropped: [String] = []
        var added: [String] = []
        var i = 0
        var j = 0
        while i < a.count, j < b.count {
            if a[i] == b[j] {
                i += 1
                j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                dropped.append(baselineWords[i])
                i += 1
            } else {
                added.append(textWords[j])
                j += 1
            }
        }
        while i < a.count { dropped.append(baselineWords[i]); i += 1 }
        while j < b.count { added.append(textWords[j]); j += 1 }
        return (dropped, added)
    }

    /// The marks one language wears and the other cannot: Polish diacritics are
    /// the hard one (English never uses them), so a token carrying one is Polish
    /// whatever else is true of the text. The English side has no such mark, so
    /// the check uses the function words the app's own detector scores on, which
    /// is a reporting aid and not a decision.
    private static let polishDiacritics = Set("ąćęłńóśźżĄĆĘŁŃÓŚŹŻ")

    private static let englishFunctionWords: Set<String> = [
        "the", "a", "an", "and", "or", "but", "of", "to", "in", "on", "at", "is",
        "are", "was", "were", "be", "been", "it", "this", "that", "these", "those",
        "you", "your", "we", "our", "they", "their", "he", "she", "with", "for",
        "from", "so", "as", "have", "has", "had", "do", "does", "did", "not", "no",
        "yes", "will", "would", "can", "could", "should", "there", "here", "what",
        "when", "where", "which", "who", "how", "why", "because", "about",
    ]

    /// Tokens of `text` that carry the *other* language's mark, given the
    /// language that went in: Polish diacritics for an English dictation, an
    /// English function word for a Polish one.
    private func foreignTokens(in text: String, inputLanguage: String) -> [String] {
        words(text).filter { token in
            let lowered = token.lowercased()
            if inputLanguage == "en" {
                return token.contains { Self.polishDiacritics.contains($0) }
            }
            if inputLanguage == "pl" {
                return Self.englishFunctionWords.contains(lowered)
            }
            return false
        }
    }

    private func hasPolishDiacritics(_ text: String) -> Bool {
        text.contains { Self.polishDiacritics.contains($0) }
    }

    // MARK: - The measurement

    func testTheCaptainsLibraryKeepsItsLanguageAndItsWords() async throws {
        let directory = try recordingsDirectory()
        let databasePath = ProcessInfo.processInfo.environment["OSW_TEST_LIBRARY_DB"]
            ?? directory.deletingLastPathComponent().appendingPathComponent("recordings.sqlite").path
        let modelURL = try TestFixtures.multilingualModel()
        let configuration = captainConfiguration()
        let budget = TimeInterval(ProcessInfo.processInfo.environment["OSW_TEST_LIBRARY_BUDGET_SECONDS"] ?? "") ?? 5400

        TestFixtures.report("[bilingual] ============================================================")
        TestFixtures.report("[bilingual] decoding through WhisperEngine, the app's own path")
        TestFixtures.report("[bilingual]   recordings \(directory.path)")
        TestFixtures.report("[bilingual]   database \(databasePath)")
        TestFixtures.report("[bilingual]   whisper model \(modelURL.path)")
        TestFixtures.report(
            "[bilingual]   captain's switches (\(configuration.source)): tone=\(configuration.toneEnabled) "
                + "cleanUp=\(configuration.cleanUpEnabled) toneMode=\(configuration.toneMode.rawValue) "
                + "reference=\"\(configuration.reference)\" initialPrompt=\"\(configuration.initialPrompt)\" "
                + "longPausesEndSentences=\(configuration.longPausesEndSentences) → "
                + "pause policy \(configuration.pausePolicy == .upstream ? "upstream" : "restored")"
        )
        TestFixtures.report("[bilingual]   budget for the whole library: \(Int(budget)) s")

        let rows = libraryRows(databasePath: databasePath)
        let present = rows.filter {
            FileManager.default.fileExists(atPath: directory.appendingPathComponent($0.fileName).path)
        }
        let missing = rows.filter {
            !FileManager.default.fileExists(atPath: directory.appendingPathComponent($0.fileName).path)
        }
        TestFixtures.report(
            "[bilingual]   library: \(rows.count) rows in the database, \(present.count) with audio present, "
                + "\(missing.count) without"
        )
        var census: [String: Int] = [:]
        for row in present { census[label(language(row.stored)), default: 0] += 1 }
        TestFixtures.report(
            "[bilingual]   stored-text language census, the app's own LanguageDetector: pl \(census["pl"] ?? 0) "
                + "| en \(census["en"] ?? 0) | unknown \(census["unknown"] ?? 0)"
        )
        for row in missing {
            TestFixtures.report("[bilingual] SKIPPED no audio | \(row.timestamp) | \(row.fileName)")
        }

        // The anchors first, in full, so a run that is cut short has already
        // produced the two texts the whole task is about.
        var ordered: [LibraryRow] = []
        for anchor in Self.anchors {
            if let row = present.first(where: { $0.fileName == anchor.fileName }) {
                ordered.append(row)
            } else if FileManager.default.fileExists(atPath: directory.appendingPathComponent(anchor.fileName).path) {
                ordered.append(LibraryRow(
                    timestamp: "db row absent", fileName: anchor.fileName, duration: anchor.duration,
                    stored: "", status: "no row"
                ))
            }
        }
        ordered += present.filter { row in !Self.anchors.contains { $0.fileName == row.fileName } }

        // The weights: the app's own manager and runtime, pointed at a scratch
        // directory of hard links so the captain's Application Support is only
        // ever read.
        let manager = try stagedModelManager()
        let runtime = TransformRuntime(models: manager)
        TestFixtures.report(
            "[bilingual]   transform weights: shipped 1.5B present "
                + "\(manager.hasModelFile(manager.defaultModel)) | optional 8B present "
                + "\(manager.hasModelFile(manager.polishModel)) | 8B verified "
                + "\(manager.isPolishModelInstalled)"
        )
        TestFixtures.report(
            "[bilingual]   model routing: tone in either language → "
                + "\(manager.model(for: .tone(language: .english, tone: .neutral)).id); clean-up in pl → "
                + "\(manager.model(for: .cleanUp(language: .polish)).id); clean-up in en → "
                + "\(manager.model(for: .cleanUp(language: .english)).id)"
        )

        let engine = WhisperEngine(modelPath: modelURL.path)
        try await engine.initialize()
        defer { engine.unload() }
        defer { runtime.unload() }

        let service = TransformService(
            localTransform: { systemPrompt, userText, model in
                try await runtime.transform(systemPrompt: systemPrompt, userText: userText, model: model)
            },
            modelForPolicy: { manager.model(for: $0) },
            gateSettings: { configuration.gateSettings }
        )

        let started = Date()
        var processed = 0
        var totalDecodeSeconds = 0.0
        var totalTransformSeconds = 0.0
        var totalAudioSeconds = 0.0
        var skippedForBudget: [String] = []
        var undecodable: [(String, String)] = []
        var processedAnchors = Set<String>()

        for (index, row) in ordered.enumerated() {
            let isAnchor = Self.anchors.contains { $0.fileName == row.fileName }
            if !isAnchor, Date().timeIntervalSince(started) > budget {
                skippedForBudget.append(row.fileName)
                TestFixtures.report(
                    "[bilingual] SKIPPED budget | \(row.timestamp) | \(row.fileName) | "
                        + "the library pass reached the \(Int(budget)) s budget"
                )
                continue
            }

            let anchorLabel = Self.anchors.first { $0.fileName == row.fileName }?.label
            let audioURL = directory.appendingPathComponent(row.fileName)
            TestFixtures.report("[bilingual] ------------------------------------------------------------")
            TestFixtures.report(
                "[bilingual] RECORDING \(index + 1)/\(ordered.count) | \(anchorLabel ?? "library") | "
                    + "\(row.timestamp) | \(row.fileName) | \(row.duration) s | status \(row.status)"
            )

            let decodeStart = Date()
            let detailed: WhisperEngine.DetailedTranscription
            do {
                detailed = try await engine.transcribeAudioDetailed(
                    url: audioURL,
                    settings: configuration.whisperSettings(),
                    pausePolicy: configuration.pausePolicy
                )
            } catch {
                TestFixtures.report("[bilingual] UNDECODABLE | \(row.fileName) | \(error)")
                undecodable.append((row.fileName, "\(error)"))
                continue
            }
            let decodeSeconds = Date().timeIntervalSince(decodeStart)
            totalDecodeSeconds += decodeSeconds
            totalAudioSeconds += row.duration

            let raw = cleaned(detailed.text)
            let engineLanguage = detailed.language
            let rawVerdict = language(raw)

            TestFixtures.report(
                "[bilingual] DECODE \(String(format: "%.1f", decodeSeconds)) s | segments "
                    + "\(detailed.segments.count) | engine language \(engineLanguage ?? "none")"
            )
            TestFixtures.report("[bilingual] STORED: \(row.stored)")
            TestFixtures.report("[bilingual] STORED LANG: \(label(language(row.stored)))")
            TestFixtures.report("[bilingual] RAW: \(raw)")

            // 1. The deterministic clean-up, exactly as the indicator runs it.
            let scrub = configuration.cleanUpEnabled
                ? DictationScrubber.scrub(raw)
                : DictationScrubber.Result(
                    text: raw, removedFillers: 0, removedRepetitions: 0, removedAnnotations: 0
                )
            let cleanedText = scrub.text
            let cleanedVerdict = language(cleanedText)
            let scrubDelta = wordDiff(baseline: raw, text: cleanedText)
            TestFixtures.report(
                "[bilingual] SCRUB removed fillers \(scrub.removedFillers) repetitions "
                    + "\(scrub.removedRepetitions) annotations \(scrub.removedAnnotations) | "
                    + "dropped \(scrubDelta.dropped.count) \(scrubDelta.dropped) | added "
                    + "\(scrubDelta.added.count) \(scrubDelta.added)"
            )
            TestFixtures.report("[bilingual] CLEANED: \(cleanedText)")

            // 2. The transform, exactly as the gate resolves it on the engine's
            //    own language (the detector is its documented fallback).
            let sourceLanguage = engineLanguage ?? rawVerdict.languageCode
            let transformStart = Date()
            let outcome = await service.transformDetailed(cleanedText, sourceLanguage: engineLanguage)
            let transformSeconds = Date().timeIntervalSince(transformStart)
            totalTransformSeconds += transformSeconds

            let final = outcome.text
            let finalVerdict = language(final)
            let modelDelta = wordDiff(baseline: cleanedText, text: final)
            let wholeDelta = wordDiff(baseline: raw, text: final)
            let inputLanguage = engineLanguage ?? rawVerdict.languageCode ?? "unknown"
            let foreign = foreignTokens(in: final, inputLanguage: inputLanguage)
            let flip = rawVerdict != .unknown && finalVerdict != rawVerdict

            TestFixtures.report(
                "[bilingual] TRANSFORM \(String(format: "%.1f", transformSeconds)) s | policy "
                    + "\(outcome.policy?.summary ?? "none") | didRunModel \(outcome.didRunModel) | "
                    + "guard \(outcome.guardRejection.map { String(describing: $0) } ?? "none")"
            )
            if let rejection = outcome.guardRejection {
                TestFixtures.report("[bilingual] GUARD NOTICE: \(rejection.notice)")
            }
            TestFixtures.report("[bilingual] FINAL: \(final)")
            TestFixtures.report(
                "[bilingual] DELTA cleaned→final: dropped \(modelDelta.dropped.count) \(modelDelta.dropped) | "
                    + "added \(modelDelta.added.count) \(modelDelta.added)"
            )
            TestFixtures.report(
                "[bilingual] DELTA raw→final: dropped \(wholeDelta.dropped.count) \(wholeDelta.dropped) | "
                    + "added \(wholeDelta.added.count) \(wholeDelta.added)"
            )
            TestFixtures.report(
                "[bilingual] LANG engine=\(engineLanguage ?? "none") "
                    + "gate=\(sourceLanguage ?? "none") raw=\(label(rawVerdict)) "
                    + "cleaned=\(label(cleanedVerdict)) final=\(label(finalVerdict)) | "
                    + "flip=\(flip ? "YES" : "no") | polishDiacriticsInFinal=\(hasPolishDiacritics(final))"
            )
            TestFixtures.report(
                "[bilingual] FOREIGN TOKENS (\(inputLanguage) in): \(foreign)"
            )
            TestFixtures.report(
                "[bilingual] TABLE | \(row.timestamp) | \(row.fileName) | \(String(format: "%.1f", row.duration)) "
                    + "| engine=\(engineLanguage ?? "none") | raw=\(label(rawVerdict)) "
                    + "| final=\(label(finalVerdict)) | match=\(label(finalVerdict) == inputLanguage ? "yes" : "no") "
                    + "| policy=\(outcome.policy?.summary ?? "none") | didRunModel=\(outcome.didRunModel) "
                    + "| guard=\(outcome.guardRejection == nil ? "none" : String(describing: outcome.guardRejection!)) "
                    + "| dropped=\(wholeDelta.dropped.count) | added=\(wholeDelta.added.count) "
                    + "| flip=\(flip ? "YES" : "no") | decodeS=\(String(format: "%.1f", decodeSeconds)) "
                    + "| transformS=\(String(format: "%.1f", transformSeconds))"
            )

            processed += 1
            if isAnchor { processedAnchors.insert(row.fileName) }
        }

        TestFixtures.report("[bilingual] ------------------------------------------------------------")
        TestFixtures.report(
            "[bilingual] SUMMARY processed \(processed) of \(ordered.count) | skipped for budget "
                + "\(skippedForBudget.count) | undecodable \(undecodable.count) | anchors processed "
                + "\(processedAnchors.count)/\(Self.anchors.count) | elapsed "
                + "\(String(format: "%.1f", Date().timeIntervalSince(started))) s"
        )
        TestFixtures.report(
            "[bilingual] SUMMARY audio \(String(format: "%.1f", totalAudioSeconds)) s | decode "
                + "\(String(format: "%.1f", totalDecodeSeconds)) s | transform "
                + "\(String(format: "%.1f", totalTransformSeconds)) s (model call plus prompt building)"
        )
        for fileName in skippedForBudget {
            TestFixtures.report("[bilingual] SUMMARY skipped: \(fileName) (budget \(Int(budget)) s)")
        }
        for (fileName, error) in undecodable {
            TestFixtures.report("[bilingual] SUMMARY undecodable: \(fileName) — \(error)")
        }

        XCTAssertEqual(
            processedAnchors.count,
            Self.anchors.count,
            "the two anchors and the short English clip are the task: every one of them has to be decoded"
        )
    }

    // MARK: - Helpers

    private func cleaned(_ text: String) -> String {
        text
            .replacingOccurrences(of: "[MUSIC]", with: "")
            .replacingOccurrences(of: "[BLANK_AUDIO]", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func recordingsDirectory() throws -> URL {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["OSW_TEST_CAPTAIN_RECORDINGS"], !path.isEmpty else {
            throw XCTSkip("OSW_TEST_CAPTAIN_RECORDINGS is not set: the captain's recordings are not on this machine")
        }
        let directory = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: directory.path) else {
            throw XCTSkip("OSW_TEST_CAPTAIN_RECORDINGS points at no directory: \(path)")
        }
        return directory
    }

    /// The app's own transform model manager, with the real weights hard-linked
    /// into a scratch directory: `verifiedPath(for:)` then finds the stamp it
    /// already wrote for the same inode, so nothing is hashed and nothing in
    /// Application Support is written.
    private func stagedModelManager() throws -> TransformModelManager {
        let source = ProcessInfo.processInfo.environment["OSW_TEST_TRANSFORM_MODELS_DIR"]
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/ru.starmel.OpenSuperWhisper/transform-models")
                .path
        let sourceDirectory = URL(fileURLWithPath: source)
        let scratch = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/OpenSuperWhisperTests-bilingual-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)

        for model in TransformModelManager.availableModels {
            let origin = sourceDirectory.appendingPathComponent(model.fileName)
            guard FileManager.default.fileExists(atPath: origin.path) else { continue }
            let destination = scratch.appendingPathComponent(model.fileName)
            try? FileManager.default.removeItem(at: destination)
            do {
                try FileManager.default.linkItem(at: origin, to: destination)
            } catch {
                try FileManager.default.copyItem(at: origin, to: destination)
            }
            let stamp = sourceDirectory.appendingPathComponent(model.fileName + ".verified.json")
            if FileManager.default.fileExists(atPath: stamp.path) {
                try? FileManager.default.copyItem(
                    at: stamp, to: scratch.appendingPathComponent(model.fileName + ".verified.json")
                )
            }
        }

        addTeardownBlock {
            _ = try? FileManager.default.removeItem(at: scratch)
        }
        return TransformModelManager(directory: scratch, catalogue: TransformModelManager.availableModels)
    }
}
