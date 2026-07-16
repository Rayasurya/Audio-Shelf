import Foundation
import Testing
@testable import AudiobookLibrary

@Test func textRuleRemovesTriggerWord() {
    let rules = [TextRule(pattern: "spider", replacement: "")]
    let result = applyTextRules("A spider crawled. The Spider was gone.", rules: rules)
    #expect(result == "A crawled. The was gone.")
}

@Test func textRuleReplacesWholeWordsOnly() {
    let rules = [TextRule(pattern: "cat", replacement: "dog")]
    let result = applyTextRules("The cat concatenated categories.", rules: rules)
    #expect(result == "The dog concatenated categories.")
}

@Test func textRuleIsCaseInsensitiveAndKeepsPunctuation() {
    let rules = [TextRule(pattern: "Damn", replacement: "")]
    let result = applyTextRules("Well, damn, that hurt.", rules: rules)
    #expect(result == "Well,, that hurt.")
}

@Test func emptyRulesLeaveTextUntouched() {
    let text = "Nothing   changes here."
    #expect(applyTextRules(text, rules: []) == text)
}
