import Foundation
let cases: [(String, String, String, TransformLanguage, String?)] = [
    ("ack", "Please send the report to the client today, and copy me on the reply.",
     "Sure, send the report to the client today and make sure to copy me on the reply.", .english, "assistantFrame(sure)"),
    ("preamble", "Please send the report to the client today.",
     "Sure, here's the rewritten text in a casual register:\n\nSure, send the report to the client today!", .english, "assistantFrame(sure)"),
    ("collapse", "ok so the plan is first we test then we deploy and then we watch the logs", "Understood.", .english, "assistantFrame(understood)"),
    ("stub", "ok so the plan is first we test then we deploy and then we watch the logs", "Plan done.", .english, "stub(17,2)"),
    ("pl-frame-ocz", "Proszę wysłać raport do klienta dzisiaj.", "Oczywiście, wysyłam raport do klienta.", .polish, "assistantFrame(oczywiście)"),
    ("pl-frame-oto", "Proszę wysłać raport do klienta dzisiaj.", "Oto przepisany tekst.", .polish, "assistantFrame(oto)"),
    ("pl-frame-jasne", "Proszę wysłać raport do klienta dzisiaj.", "Jasne, wysyłam raport do klienta dzisiaj.", .polish, "assistantFrame(jasne)"),
    ("label-register", "Please send the report to the client today.", "Register: formal\nPlease send the report to the client today.", .english, "label(register:)"),
    ("label-output", "Please send the report to the client today.", "Output: Please send the report to the client today.", .english, "label(output:)"),
    ("label-rewritten", "Please send the report to the client today.", "The rewritten version: please send the report today.", .english, "label(rewritten version)"),
    ("flip-en->pl", "Hello, I am sending the report to the client today.", "Cześć, wysyłam raport do klienta dzisiaj.", .english, "languageFlip(English)"),
    ("flip-pl->en", "Cześć, wysyłam raport do klienta dzisiaj.", "Hello, I am sending the report to the client today.", .polish, "languageFlip(Polish)"),
    // negatives
    ("n-in-register", "Please send the report to the client today.", "Please send the report to the client today.", .english, nil),
    ("n-two-word", "Send it now.", "Send it.", .english, nil),
    ("n-fragment", "the deployment is done and", "the deployment is done and", .english, nil),
    ("n-mixed-term", "We deploy the backend na produkcję every Friday evening.",
     "We should deploy the backend na produkcję every Friday evening.", .english, nil),
    ("n-rewrite", "I think we should probably just ship it on friday if nothing breaks",
     "I believe we should probably ship it on Friday if nothing breaks.", .english, nil),
    ("n-drift-article", "invoice number is 423 and the amount is three thousand zloty",
     "Invoice number is 423 and the amount is three thousand zloty.", .english, nil),
    ("n-drift-noun", "I think we should probably just ship it on friday if nothing breaks",
     "I think we should probably just ship the product on Friday if nothing breaks.", .english, nil),
]
var failures = 0
for (name, input, output, language, expected) in cases {
    let r = TransformGuard.rejection(of: output, for: input, language: language)
    let got: String?
    switch r {
    case .none: got = nil
    case .some(.assistantFrame(let f)): got = "assistantFrame(\(f))"
    case .some(.label(let l)): got = "label(\(l))"
    case .some(.stub(let i, let o)): got = "stub(\(i),\(o))"
    case .some(.languageFlip(let e)): got = "languageFlip(\(e.displayName))"
    }
    let ok = got == expected
    if !ok { failures += 1 }
    print("\(ok ? "PASS" : "FAIL") \(name): got \(got ?? "nil") expected \(expected ?? "nil")")
}
print(failures == 0 ? "ALL \(cases.count) CASES PASS" : "\(failures) FAILURES")
