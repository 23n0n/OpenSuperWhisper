import XCTest
@testable import OpenSuperWhisper

/// The deterministic guard on the tone path: text in, verdict out, no model
/// call anywhere.
///
/// The positive cases are the exact strings the shipped model produced in
/// `fm-20260924-10/raw`, fed through the guard as they were measured; the
/// negative cases are the legitimate outputs the guard must leave alone.
final class TransformGuardTests: XCTestCase {

    // MARK: - The measured failures, fed through as they were

    /// `Please send the report to the client today, and copy me on the reply.`
    /// came back as this from `qwen2.5-1.5b-instruct-q4_k_m`.
    func testAssistantAcknowledgement_isRejected() {
        let input = "Please send the report to the client today, and copy me on the reply."
        let measured = "Sure, send the report to the client today and make sure to copy me on the reply."
        XCTAssertEqual(
            TransformGuard.rejection(of: measured, for: input, language: .english),
            .assistantFrame("sure")
        )
    }

    /// The preamble the proposed prompt produced on the same model.
    func testPreambleInsteadOfARewrite_isRejected() {
        let input = "Please send the report to the client today."
        let measured = "Sure, here's the rewritten text in a casual register:\n\n"
            + "Sure, send the report to the client today!"
        let rejection = TransformGuard.rejection(of: measured, for: input, language: .english)
        XCTAssertEqual(rejection, .assistantFrame("sure"))
    }

    /// Temperature 0 collapsed a twelve-word run-on into this on the small
    /// model. The frame rule catches it first; the stub rule is what catches the
    /// same collapse when it is not an assistant word.
    func testChatCollapse_isRejected() {
        let input = "ok so the plan is first we test then we deploy and then we watch the logs"
        XCTAssertEqual(
            TransformGuard.rejection(of: "Understood.", for: input, language: .english),
            .assistantFrame("understood")
        )
        XCTAssertEqual(
            TransformGuard.rejection(of: "Plan done.", for: input, language: .english),
            .stub(wordsIn: 17, wordsOut: 2)
        )
    }

    /// Polish frames are caught by the same rule, in Polish.
    func testPolishAssistantFrames_areRejected() {
        let input = "Proszę wysłać raport do klienta dzisiaj."
        XCTAssertEqual(
            TransformGuard.rejection(of: "Oczywiście, wysyłam raport do klienta.", for: input, language: .polish),
            .assistantFrame("oczywiście")
        )
        XCTAssertEqual(
            TransformGuard.rejection(of: "Oto przepisany tekst.", for: input, language: .polish),
            .assistantFrame("oto")
        )
        XCTAssertEqual(
            TransformGuard.rejection(of: "Jasne, wysyłam raport do klienta dzisiaj.", for: input, language: .polish),
            .assistantFrame("jasne")
        )
    }

    func testLabelLines_areRejected() {
        let input = "Please send the report to the client today."
        XCTAssertEqual(
            TransformGuard.rejection(
                of: "Register: formal\nPlease send the report to the client today.",
                for: input,
                language: .english
            ),
            .label("register:")
        )
        XCTAssertEqual(
            TransformGuard.rejection(
                of: "Output: Please send the report to the client today.",
                for: input,
                language: .english
            ),
            .label("output:")
        )
        XCTAssertEqual(
            TransformGuard.rejection(
                of: "The rewritten version: please send the report today.",
                for: input,
                language: .english
            ),
            .label("rewritten version")
        )
    }

    func testLanguageFlip_isRejected() {
        let polish = "Cześć, wysyłam raport do klienta dzisiaj."
        let english = "Hello, I am sending the report to the client today."
        XCTAssertEqual(
            TransformGuard.rejection(of: english, for: polish, language: .polish),
            .languageFlip(expected: .polish)
        )
        XCTAssertEqual(
            TransformGuard.rejection(of: polish, for: english, language: .english),
            .languageFlip(expected: .english)
        )
    }

    // MARK: - The cases it must not touch

    /// Already in the requested register: the model is expected to return the
    /// dictation unchanged, and that is not a stub, a frame or a flip.
    func testAlreadyInRegister_isUntouched() {
        let text = "Please send the report to the client today."
        XCTAssertNil(TransformGuard.rejection(of: text, for: text, language: .english))
    }

    /// A two-word dictation is not "a sentence", so the stub rule never applies
    /// to it.
    func testTwoWordDictation_isUntouched() {
        XCTAssertNil(
            TransformGuard.rejection(of: "Dzień dobry.", for: "Dzień dobry.", language: .polish)
        )
        XCTAssertNil(
            TransformGuard.rejection(of: "Send it.", for: "Send it now.", language: .english)
        )
    }

    /// A fragment comes back as it is, and comes back whole.
    func testFragment_isUntouched() {
        let text = "the deployment is done and"
        XCTAssertNil(TransformGuard.rejection(of: text, for: text, language: .english))
    }

    /// A technical term from another language inside the text is not a flip: the
    /// detector classifies by the language around it.
    func testMixedLanguageTechnicalTerm_isUntouched() {
        let text = "We deploy the backend na produkcję every Friday evening."
        XCTAssertNil(TransformGuard.rejection(of: text, for: text, language: .english))
        XCTAssertNil(
            TransformGuard.rejection(
                of: "We should deploy the backend na produkcję every Friday evening.",
                for: text,
                language: .english
            ),
            "the technical term does not make the rewrite a language flip"
        )
    }

    /// A real rewrite that changes only the register passes: content is kept,
    /// words count, the language holds.
    func testRegisterRewrite_passes() {
        let input = "I think we should probably just ship it on friday if nothing breaks"
        let output = "I believe we should probably ship it on Friday if nothing breaks."
        XCTAssertNil(TransformGuard.rejection(of: output, for: input, language: .english))
    }

    /// The documented limit: subtle content drift is text the guard cannot judge
    /// — a dropped article and an invented noun both pass it. This test exists
    /// so the limit is recorded, not so the behaviour is wanted.
    func testSubtleContentDrift_isOutOfReach() {
        let input = "invoice number is 423 and the amount is three thousand zloty"
        let droppedArticle = "Invoice number is 423 and the amount is three thousand zloty."
        XCTAssertNil(TransformGuard.rejection(of: droppedArticle, for: input, language: .english))

        let shipped = "I think we should probably just ship it on friday if nothing breaks"
        let inventedNoun = "I think we should probably just ship the product on Friday if nothing breaks."
        XCTAssertNil(TransformGuard.rejection(of: inventedNoun, for: shipped, language: .english))
    }

    /// Clean-up alone carries no tone policy, so the guard is never consulted for
    /// it: the caller gates on `promptTone`.
    func testGuardAppliesOnlyToPoliciesThatSendToneText() {
        XCTAssertNil(TransformPolicy.cleanUp(language: .english).promptTone)
        XCTAssertNotNil(TransformPolicy.tone(language: .english, tone: .formal).promptTone)
        XCTAssertNotNil(TransformPolicy.cleanUpWithTone(language: .polish, tone: .casual).promptTone)
    }
}
