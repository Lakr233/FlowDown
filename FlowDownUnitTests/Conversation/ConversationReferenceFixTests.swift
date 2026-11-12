//
//  ConversationReferenceFixTests.swift
//  FlowDownUnitTests
//

@preconcurrency @testable import FlowDown
import Foundation
import Testing

@Suite(.serialized)
struct ConversationReferenceFixTests {
    private func resolve(_ content: String, links: [Int: String] = [:]) -> String {
        ConversationSession.resolveReferences(in: content, with: links)
    }

    // MARK: - Markers that resolve to nothing

    @Test
    func `invented marker is removed from a chinese reply without links`() {
        let reply = "今天是 2026 年 11 月 12 日，星期四[^Date_001]。"

        #expect(resolve(reply) == "今天是 2026 年 11 月 12 日，星期四。")
    }

    @Test
    func `invented marker takes its leading space when it hangs before punctuation`() {
        #expect(resolve("Today is Thursday [^Date_001].") == "Today is Thursday.")
        #expect(resolve("Today is Thursday [^Date_001]") == "Today is Thursday")
        #expect(resolve("Today [^Date_001] is Thursday.") == "Today is Thursday.")
    }

    @Test
    func `invented marker glued to the next word keeps the surrounding text`() {
        #expect(resolve("Today [^Date_001]is Thursday.") == "Today is Thursday.")
        #expect(resolve("Today[^Date_001] is Thursday.") == "Today is Thursday.")
    }

    @Test
    func `numeric marker without any link is removed`() {
        #expect(resolve("The sky is blue[^7].") == "The sky is blue.")
        #expect(resolve("The sky is blue[^7, 8].") == "The sky is blue.")
        #expect(resolve("The sky is blue[^7].", links: [1: "https://example.com/1"]) == "The sky is blue.")
    }

    @Test
    func `multiple invented markers in one reply are all removed`() {
        let reply = "今天是星期四[^Date_001]，天气晴[^Weather_1]。\n\nIt is sunny [^Weather_002] [^3]. Enjoy[^Source1]!"

        #expect(resolve(reply) == "今天是星期四，天气晴。\n\nIt is sunny. Enjoy!")
    }

    @Test
    func `a marker followed by a colon in the middle of a line is still removed`() {
        #expect(resolve("Today[^Date_001]: Thursday.") == "Today: Thursday.")
    }

    // MARK: - Markers that resolve to a link

    @Test
    func `numeric marker with a link is rewritten to a linked citation`() {
        let links = [1: "https://example.com/1"]

        #expect(resolve("The sky is blue[^1].", links: links) == "The sky is blue[^1](https://example.com/1).")
    }

    @Test
    func `numeric list keeps the mapped numbers only`() {
        let links = [1: "https://example.com/1"]

        #expect(resolve("The sky is blue[^1, 2].", links: links) == "The sky is blue[^1](https://example.com/1).")
        #expect(resolve("The sky is blue[^1, ^2].", links: links) == "The sky is blue[^1](https://example.com/1).")
    }

    @Test
    func `linked and invented markers are handled in the same reply`() {
        let links = [1: "https://example.com/1", 2: "https://example.com/2"]
        let reply = "Blue sky[^1, 2]. Today is Thursday [^Date_001]. Nothing here[^9]."
        let expected = "Blue sky[^1](https://example.com/1) [^2](https://example.com/2). Today is Thursday. Nothing here."

        #expect(resolve(reply, links: links) == expected)
    }

    @Test
    func `already linked citation is left unchanged`() {
        let reply = "The sky is blue[^1](https://x)."

        #expect(resolve(reply) == reply)
        #expect(resolve(reply, links: [1: "https://example.com/1"]) == reply)
    }

    // MARK: - Markers that must stay

    @Test
    func `marker inside inline code is kept`() {
        let reply = "Write `[^Date_001]` to cite, or ``a ` [^7]``."

        #expect(resolve(reply) == reply)
    }

    @Test
    func `marker next to inline code is still removed`() {
        #expect(resolve("Use `date` here[^Date_001] and `time` there.") == "Use `date` here and `time` there.")
    }

    @Test
    func `marker inside a fenced code block is kept`() {
        let reply = "Example:\n\n```markdown\nA fact[^Date_001].\nAnother[^7]\n```\n\nDone."

        #expect(resolve(reply) == reply)
    }

    @Test
    func `marker inside a fenced code block of a list item is kept`() {
        let reply = "- Example:\n\n  ```markdown\n  A fact[^Date_001].\n  ```\n\n- Done[^Date_002]."
        let expected = "- Example:\n\n  ```markdown\n  A fact[^Date_001].\n  ```\n\n- Done."

        #expect(resolve(reply) == expected)
    }

    @Test
    func `a reply with a real footnote is left unchanged`() {
        let reply = "The sky is blue[^note].\n\n[^note]: Rayleigh scattering explains it."

        #expect(resolve(reply) == reply)
    }

    @Test
    func `a numeric footnote defined by the reply is left unchanged`() {
        let reply = "The sky is blue[^1] and wide[^2].\n\n[^1]: Rayleigh scattering.\n   [^2]: Look up."

        #expect(resolve(reply) == reply)
    }

    @Test
    func `only the undefined marker is removed next to a real footnote`() {
        let reply = "The sky is blue[^note], today[^Date_001].\n\n[^note]: Rayleigh scattering."
        let expected = "The sky is blue[^note], today.\n\n[^note]: Rayleigh scattering."

        #expect(resolve(reply) == expected)
    }

    @Test
    func `marker with a non latin identifier is removed`() {
        #expect(resolve("今天是星期四[^来源1]。") == "今天是星期四。")
        #expect(resolve("Today is Thursday [^doc1].") == "Today is Thursday.")
    }

    // MARK: - Character classes and math

    @Test
    func `regex character classes in prose are unchanged byte for byte`() {
        let replies = [
            "Use [^a-z] to match anything but lowercase letters.",
            "Then [^0-9] skips the digits.",
            "A quoted string is \"[^\"]*\" in most engines.",
            "Split the path with [^/]+ and join it again.",
            "Also [^a-z0-9_.-], [^\\s], [^ ], [^Source 1] and [^a b] stay.",
            "Anything but [^abc] works, and x[^n] is the n-th power.",
            "Words such as [^note], [^Weather], [^x], [^来源] and [^Date_] stay too.",
        ]

        for reply in replies {
            #expect(Array(resolve(reply).utf8) == Array(reply.utf8))
            #expect(Array(resolve(reply, links: [1: "https://example.com/1"]).utf8) == Array(reply.utf8))
        }
    }

    @Test
    func `marker inside inline math is kept`() {
        let reply = "The angle is \\( x[^k1] + y[^2] \\) and the cost is $a[^2]$ here."

        #expect(resolve(reply) == reply)
    }

    @Test
    func `marker inside display math is kept`() {
        let dollars = "Therefore:\n\n$$\nx[^2] + y[^k1]\n$$\n\nDone."
        let brackets = "Therefore:\n\n\\[\nx[^2] + y[^k1]\n\\]\n\nDone."

        #expect(resolve(dollars) == dollars)
        #expect(resolve(brackets) == brackets)
    }

    @Test
    func `marker next to math is still removed`() {
        let reply = "We have \\( x^2 \\) here[^Date_001] and $y$ there [^7]."

        #expect(resolve(reply) == "We have \\( x^2 \\) here and $y$ there.")
    }

    @Test
    func `dollar amounts are not math`() {
        #expect(resolve("It costs $5 today[^Date_001] and $6 tomorrow.") == "It costs $5 today and $6 tomorrow.")
    }

    // MARK: - Untouched text

    @Test
    func `text without markers is unchanged byte for byte`() {
        let reply = "  Leading spaces, tabs\t and  double  spaces .\r\n\n- [ ] task\n- [link](https://example.com) ^caret [brackets]\n\n"

        #expect(Array(resolve(reply).utf8) == Array(reply.utf8))
        #expect(Array(resolve(reply, links: [1: "https://example.com/1"]).utf8) == Array(reply.utf8))
    }

    @Test
    func `removing a marker does not trim or reformat the rest of the reply`() {
        let reply = "  First  line[^Date_001] .\n\n\tSecond line  \n"

        #expect(resolve(reply) == "  First  line .\n\n\tSecond line  \n")
    }

    @Test
    func `empty content stays empty`() {
        #expect(resolve("") == "")
        #expect(resolve("", links: [1: "https://example.com/1"]) == "")
    }
}
