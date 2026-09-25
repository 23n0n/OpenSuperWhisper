import Foundation

// Prints the app's own LanguageDetector verdict for every text handed to it.
// Input: JSON array of {"tag": String, "text": String}. Output: `tag<TAB>verdict`.
let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let items = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
for item in items {
    let tag = item["tag"] as! String
    let text = item["text"] as! String
    let verdict: String
    switch LanguageDetector.detect(text) {
    case .english: verdict = "english"
    case .polish: verdict = "polish"
    case .unknown: verdict = "unknown"
    }
    print("\(tag)\t\(verdict)\t\(LanguageDetector.languageCode(for: text) ?? "-")")
}
