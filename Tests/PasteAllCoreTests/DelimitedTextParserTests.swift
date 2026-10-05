import XCTest
@testable import PasteAllCore

final class DelimitedTextParserTests: XCTestCase {
    func testQuotedCSVAndEscapedQuotes() {
        let input = "name,note\nAda,\"hello, \"\"world\"\"\""
        XCTAssertEqual(
            DelimitedTextParser.parse(input, delimiter: ","),
            [["name", "note"], ["Ada", "hello, \"world\""]]
        )
    }

    func testQuotedNewline() {
        let input = "name,note\nAda,\"line 1\nline 2\""
        XCTAssertEqual(
            DelimitedTextParser.parse(input, delimiter: ","),
            [["name", "note"], ["Ada", "line 1\nline 2"]]
        )
    }

    func testRejectsIrregularRows() {
        XCTAssertNil(DelimitedTextParser.parse("a,b\n1,2,3", delimiter: ","))
    }

    func testRejectsOneDimensionalText() {
        XCTAssertNil(DelimitedTextParser.parse("a\nb", delimiter: ","))
    }

    func testCRLFAndMixedNewlinesInCSVAndTSV() {
        for delimiter: Character in [",", "\t"] {
            let d = String(delimiter)
            let input = "a\(d)b\r\n1\(d)2\r3\(d)4\n5\(d)6\r\n"
            XCTAssertEqual(DelimitedTextParser.parse(input, delimiter: delimiter),
                           [["a", "b"], ["1", "2"], ["3", "4"], ["5", "6"]])
        }
    }

    func testQuotedCRLFIsPreserved() {
        XCTAssertEqual(DelimitedTextParser.parse("a,b\r\n1,\"two\r\nlines\"", delimiter: ","),
                       [["a", "b"], ["1", "two\r\nlines"]])
    }
}
