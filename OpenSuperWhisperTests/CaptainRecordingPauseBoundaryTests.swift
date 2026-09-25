import Foundation
import XCTest

@testable import OpenSuperWhisper

/// The before/after measurement for "long pauses end the sentence", on the
/// captain's own recordings and through the app's own decode path.
///
/// Opt-in, like the model fixtures: `OSW_TEST_CAPTAIN_RECORDINGS` has to name a
/// directory holding the recordings, and a multilingual model has to be
/// available. With either missing the cases skip, so the plain suite never
/// depends on one developer's dictation.
///
/// What it measures per recording, under the switch off, the audio half alone,
/// and the switch on — each with the `initialPrompt` kept and cleared:
///
/// * the pauses the VAD found, and how long they were;
/// * how much of those pauses the decoder was actually given;
/// * the transcript, its sentences, its fragments, and the sentence boundaries
///   the pause closed rather than the decoder.
final class WhisperPauseBoundaryMeasurementTests: XCTestCase {

    /// The recordings the captain's complaint is about, read out of
    /// `recordings.sqlite` (the stored text there is the raw engine output).
    private struct CaptainRecording {
        let label: String
        let fileName: String
        /// The transcript the app stored for it, for the one check that this
        /// harness really is the app's own path: the switch-off run has to
        /// reproduce it.
        let storedTranscript: String
    }

    private static let recordings = [
        CaptainRecording(
            label: "pl-1 (12.1 s)",
            fileName: "5C68BFAC-5EC8-45CC-8239-3B5659272C1A.wav",
            storedTranscript: "Dobra ziameczku tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. "
                + "Bo tu chodzi o to że żeś pieprzył po całości."
        ),
        CaptainRecording(
            label: "pl-2 (23.3 s)",
            fileName: "B2EA9010-97C9-40AB-A7A2-746323A45297.wav",
            storedTranscript: "Dobra wiadomość jest taka, że odzyskałem swój polski. Udało mi się zrobić fork. "
                + "Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku."
        ),
        CaptainRecording(
            label: "en control (33.0 s)",
            fileName: "D92A0B10-EB8D-4D47-80B9-A9F3A88C112F.wav",
            storedTranscript: "Also add feature to ignore pauses. Basically how it creates a sentence without "
                + "a sense because of my long pauses. The pauses need to be ignored."
        ),
    ]

    /// His stored preference, verbatim: an instruction sitting in whisper's
    /// decoder context, which is what the A/B below measures.
    private static let captainInitialPrompt =
        "You are a transcriber. Your role is just to clean up the text and make it look pretty and attractive. "
        + "Do not change the sense of the sentences."

    private struct Arm {
        let name: String
        let policy: WhisperEngine.PauseBoundaryPolicy
    }

    private static let arms = [
        Arm(name: "before (switch off)", policy: .upstream),
        Arm(
            name: "audio only (no terminator)",
            policy: WhisperEngine.PauseBoundaryPolicy(
                maxPause: 0.8,
                minPause: 0.1,
                sentenceThreshold: .infinity,
                closesSentence: false
            )
        ),
        Arm(name: "after (switch on)", policy: .restored),
    ]

    // MARK: - Fixtures

    private func recordingsDirectory() throws -> URL {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["OSW_TEST_CAPTAIN_RECORDINGS"], !path.isEmpty else {
            throw XCTSkip(
                "OSW_TEST_CAPTAIN_RECORDINGS is not set: the captain's recordings are not on this machine"
            )
        }
        let directory = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: directory.path) else {
            throw XCTSkip("OSW_TEST_CAPTAIN_RECORDINGS points at no directory: \(path)")
        }
        return directory
    }

    /// His settings, as stored and as they reach the decoder: greedy, temperature
    /// 0, no-speech 0.6, blank suppression on, no timestamps. The pause policy is
    /// the arm, not the preference, so one process measures all of them.
    private func captainSettings(initialPrompt: String) -> Settings {
        var settings = Settings()
        settings.showTimestamps = false
        settings.temperature = 0
        settings.noSpeechThreshold = 0.6
        settings.suppressBlankAudio = true
        settings.useBeamSearch = false
        settings.initialPrompt = initialPrompt
        return settings
    }

    /// Whisper's own cleaning, as `performTranscription` applies it.
    private func cleaned(_ text: String) -> String {
        text
            .replacingOccurrences(of: "[MUSIC]", with: "")
            .replacingOccurrences(of: "[BLANK_AUDIO]", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The sentences a transcript reads as.
    private func sentences(_ text: String) -> [String] {
        let terminators: Set<Character> = [".", "!", "?", "…", "。", "！", "？"]
        var result: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if terminators.contains(character) {
                let sentence = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !sentence.isEmpty { result.append(sentence) }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { result.append(tail) }
        return result
    }

    private func wordCount(_ sentence: String) -> Int {
        sentence.split(whereSeparator: { $0.isWhitespace }).count
    }

    /// How many long pauses the transcript ran straight through.
    ///
    /// The junctions are the engine's own — `WhisperEngine.pauseJunctions` —
    /// so this measures the shipped rule rather than a second copy of it.
    ///
    /// A junction counts as open when the assembly has nothing that ends a
    /// sentence where the pause was: neither the decoder's own punctuation nor a
    /// terminator the switch inserted.
    private func junctionsLeftOpen(
        in assembly: String,
        texts: [String],
        starts: [Int64],
        endCentiseconds: [Int64],
        pauses: [WhisperEngine.StitchedPause],
        policy: WhisperEngine.PauseBoundaryPolicy,
        terminator: String
    ) -> Int {
        let junctions = WhisperEngine.pauseJunctions(
            decodedStartsCentiseconds: starts,
            decodedEndCentiseconds: endCentiseconds,
            pauses: pauses,
            threshold: policy.sentenceThreshold,
            tolerance: policy.boundaryTolerance
        )
        var open = 0
        for index in junctions {
            let upTo = cleaned(
                WhisperEngine.assembleSegmentTexts(Array(texts[0...index]), showTimestamps: false)
            )
            guard assembly.hasPrefix(upTo) else {
                open += 1
                continue
            }
            let after = assembly.dropFirst(upTo.count)
            if !(WhisperEngine.endsSentence(upTo) || after.hasPrefix(terminator)) {
                open += 1
            }
        }
        return open
    }

    // MARK: - The measurement

    func testHisRecordingsBeforeAndAfterTheSwitch() async throws {
        let directory = try recordingsDirectory()
        let modelURL = try TestFixtures.multilingualModel()
        let vadModelPath = try XCTUnwrap(
            WhisperEngine.vadModelPath,
            "Silero VAD model must be bundled with the app"
        )

        let engine = WhisperEngine(modelPath: modelURL.path)
        try await engine.initialize()
        let vad = try XCTUnwrap(MyWhisperVadContext(modelPath: vadModelPath))

        TestFixtures.report("[pauses] model \(modelURL.path)")
        TestFixtures.report("[pauses] vad \(vadModelPath)")
        TestFixtures.report(
            "[pauses] threshold \(WhisperEngine.PauseBoundaryPolicy.restored.sentenceThreshold) s, "
                + "cap \(WhisperEngine.PauseBoundaryPolicy.restored.maxPause) s"
        )

        for recording in Self.recordings {
            let audioURL = directory.appendingPathComponent(recording.fileName)
            guard FileManager.default.fileExists(atPath: audioURL.path) else {
                throw XCTSkip("\(recording.fileName) is not in \(directory.path)")
            }

            let converted = try await engine.convertAudioToPCM(fileURL: audioURL)
            let samples = try XCTUnwrap(
                converted,
                "\(recording.fileName) did not convert to PCM"
            )
            let segments = try XCTUnwrap(vad.speechSegments(in: samples))
            reportPauses(recording: recording, samples: samples, segments: segments)

            var switchOffText: String?
            for arm in Self.arms {
                for prompt in [Self.captainInitialPrompt, ""] {
                    let text = try await measure(
                        engine: engine,
                        audioURL: audioURL,
                        policy: arm.policy,
                        arm: arm.name,
                        prompt: prompt,
                        recording: recording,
                        samples: samples,
                        segments: segments
                    )
                    if arm.policy == .upstream, !prompt.isEmpty {
                        switchOffText = text
                    }
                }
            }

            // Switch off must be the transcript the app itself stored: that is
            // what makes the numbers below this app's own path and not a
            // harness's idea of it.
            TestFixtures.report(
                "[pauses] \(recording.label) switch-off text == the app's stored transcript: "
                    + "\(switchOffText == recording.storedTranscript)"
            )
        }
    }

    /// Decodes one arm, reports it, and checks the properties that must hold for
    /// this audio.
    @discardableResult
    private func measure(
        engine: WhisperEngine,
        audioURL: URL,
        policy: WhisperEngine.PauseBoundaryPolicy,
        arm: String,
        prompt: String,
        recording: CaptainRecording,
        samples: [Float],
        segments: [WhisperVadSegment]
    ) async throws -> String {
        let stitched = WhisperEngine.stitch(from: samples, segments: segments, policy: policy)
        let detailed = try await engine.transcribeAudioDetailed(
            url: audioURL,
            settings: captainSettings(initialPrompt: prompt),
            pausePolicy: policy
        )
        let text = cleaned(detailed.text)
        let texts = detailed.segments.map(\.text)
        let starts = detailed.segments.map(\.startTimeCentiseconds)
        let ends = detailed.segments.map(\.endTimeCentiseconds)
        let terminator = WhisperEngine.sentenceTerminator(forLanguage: detailed.language)
        let boundaries = WhisperEngine.sentenceBoundaries(
            decodedStartsCentiseconds: starts,
            decodedEndCentiseconds: ends,
            pauses: stitched.pauses,
            policy: policy,
            terminator: terminator
        )
        let runOn = cleaned(WhisperEngine.assembleSegmentTexts(texts, showTimestamps: false))
        let withBoundaries = cleaned(
            WhisperEngine.assembleSegmentTexts(
                texts,
                showTimestamps: false,
                sentenceBoundaries: boundaries
            )
        )
        let keptPauseSeconds = stitched.pauses.reduce(0.0) { total, pause in
            total + min(pause.seconds, policy.maxPause)
        }
        let read = sentences(text)
        let junctions = WhisperEngine.pauseJunctions(
            decodedStartsCentiseconds: starts,
            decodedEndCentiseconds: ends,
            pauses: stitched.pauses,
            threshold: policy.sentenceThreshold,
            tolerance: policy.boundaryTolerance
        )
        let ignoredByTheDecoder = junctionsLeftOpen(
            in: runOn,
            texts: texts,
            starts: starts,
            endCentiseconds: ends,
            pauses: stitched.pauses,
            policy: policy,
            terminator: terminator
        )
        let stillOpen = junctionsLeftOpen(
            in: withBoundaries,
            texts: texts,
            starts: starts,
            endCentiseconds: ends,
            pauses: stitched.pauses,
            policy: policy,
            terminator: terminator
        )
        let promptLabel = prompt.isEmpty ? "prompt cleared" : "prompt kept"
        let prefix = "\(recording.label) | \(arm) | \(promptLabel)"

        TestFixtures.report("[pauses] ------------------------------------------------------------")
        TestFixtures.report("[pauses] \(prefix)")
        TestFixtures.report(
            "[pauses]   language \(detailed.language ?? "unknown") | decoder segments \(texts.count) | "
                + "decoder audio \(Double(stitched.samples.count) / 16000) s of "
                + "\(Double(samples.count) / 16000) s | real pause kept "
                + "\(String(format: "%.2f", keptPauseSeconds)) s"
        )
        TestFixtures.report(
            "[pauses]   pauses measured \(stitched.pauses.count) | long (>= \(policy.sentenceThreshold) s) "
                + "\(stitched.pauses.filter { $0.seconds >= policy.sentenceThreshold }.count) | "
                + "junctions with a segment after them \(junctions.count) | the decoder closed "
                + "\(junctions.count - ignoredByTheDecoder) | the pause closed "
                + "\(ignoredByTheDecoder - stillOpen) | left open \(stillOpen)"
        )
        TestFixtures.report(
            "[pauses]   sentences \(read.count) | fragments (<=2 words) "
                + "\(read.filter { wordCount($0) <= 2 }.count)"
        )
        TestFixtures.report("[pauses]   text: \(text)")
        for (index, segment) in texts.enumerated() {
            TestFixtures.report("[pauses]   seg \(index) \(starts[index])->\(ends[index])cs: \(segment)")
        }
        for (index, pause) in stitched.pauses.enumerated() {
            TestFixtures.report(
                "[pauses]   pause \(index) \(pause.startCentiseconds)->\(pause.endCentiseconds)cs | "
                    + "silence \(String(format: "%.2f", pause.seconds)) s | "
                    + "long \(pause.seconds >= policy.sentenceThreshold)"
            )
        }

        if policy.closesSentence {
            XCTAssertEqual(
                withBoundaries,
                text,
                "\(prefix): the engine's transcript is not the assembler's output for this audio"
            )
            XCTAssertEqual(
                stillOpen,
                0,
                "\(prefix): a long pause is still inside a sentence in the transcript"
            )
            // Every long pause that had a decoder segment after it ends a
            // sentence in the transcript. This is the whole point of the switch.
            for index in boundaries.afterSegment.sorted() {
                let upTo = cleaned(
                    WhisperEngine.assembleSegmentTexts(Array(texts[0...index]), showTimestamps: false)
                )
                XCTAssertTrue(
                    text.hasPrefix(upTo),
                    "\(prefix): segment \(index) is not a prefix of the transcript"
                )
                let after = text.dropFirst(upTo.count)
                XCTAssertTrue(
                    WhisperEngine.endsSentence(upTo) || after.hasPrefix(terminator),
                    """
                    \(prefix): the pause after segment \(index) did not end the sentence: \
                    …\(upTo.suffix(40)) -> \(after.prefix(40))…
                    """
                )
            }
        } else {
            // Switch off — and the audio-only arm — add no punctuation at all.
            XCTAssertEqual(
                runOn,
                text,
                "\(prefix): nothing may be added to the decoder's own text on this arm"
            )
        }

        return text
    }

    private func reportPauses(
        recording: CaptainRecording,
        samples: [Float],
        segments: [WhisperVadSegment]
    ) {
        TestFixtures.report("[pauses] ============================================================")
        TestFixtures.report(
            "[pauses] \(recording.label) | \(recording.fileName) | "
                + "\(samples.count) samples (\(Double(samples.count) / 16000) s) | "
                + "VAD segments \(segments.count)"
        )

        for index in 1..<max(1, segments.count) {
            let vadGapCs = segments[index].startCs - segments[index - 1].endCs
            let decoderVisible = Double(
                Int(segments[index].startCs) * 160 - (Int(segments[index - 1].endCs) * 160 + 1600)
            ) / 16000
            TestFixtures.report(
                "[pauses]   gap \(index): VAD \(vadGapCs) cs (\(Double(vadGapCs) / 100) s) | "
                    + "decoder-visible under the switch \(String(format: "%.2f", decoderVisible)) s | "
                    + "segment \(index - 1) ends at \(segments[index - 1].endCs) cs, segment \(index) "
                    + "starts at \(segments[index].startCs) cs"
            )
        }
    }
}
