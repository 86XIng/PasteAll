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
}
