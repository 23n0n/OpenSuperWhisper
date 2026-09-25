import Foundation

// Classifies model answers with the REAL TransformGuard.swift (branch fm/tone-output
// @ 9c36eae) plus the real Utils/LanguageDetector.swift. TransformLanguage is not
// mirrored: it is extracted verbatim from TransformService.swift before compiling.
// Input: JSON array of {"tag": String, "language": "english"|"polish", "input": String,
// "output": String}. Output: one line per item, `tag<TAB>ok` or `tag<TAB>reason`.

let path = CommandLine.arguments[1]
let data = try Data(contentsOf: URL(fileURLWithPath: path))
let items = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]

func describe(_ r: TransformGuardRejection?) -> String {
    switch r {
    case .none: return "ok"
    case .some(.assistantFrame(let f)): return "REJECT assistantFrame(\(f))"
    case .some(.label(let l)): return "REJECT label(\(l))"
    case .some(.stub(let i, let o)): return "REJECT stub(in:\(i),out:\(o))"
    case .some(.languageFlip(let e)): return "REJECT languageFlip(expected:\(e.displayName))"
    }
}

for item in items {
    let tag = item["tag"] as! String
    let language = TransformLanguage(rawValue: item["language"] as! String)!
    let input = item["input"] as! String
    let output = item["output"] as! String
    let verdict = TransformGuard.rejection(of: output, for: input, language: language)
    print("\(tag)\t\(describe(verdict))")
}
