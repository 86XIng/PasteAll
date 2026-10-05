import XCTest
@testable import PasteAllCore

final class HTMLTableParserTests: XCTestCase {
    func testParsesHeadersAndColspan() {
        let html = """
        <table>
          <tr><th colspan="2">People</th></tr>
          <tr><td>Ada</td><td>36</td></tr>
        </table>
        """
        let table = HTMLTableParser.parse(html)
        XCTAssertEqual(table?.rows, [["People", ""], ["Ada", "36"]])
        XCTAssertEqual(table?.headerRows, [0])
    }

    func testIgnoresHTMLWithoutTable() {
        XCTAssertNil(HTMLTableParser.parse("<p>Hello</p>"))
    }

    func testCapsUntrustedColspanAtExcelLimit() {
        let table = HTMLTableParser.parse(
            "<table><tr><th colspan='999999999'>A</th></tr><tr><td>B</td></tr></table>"
        )
        XCTAssertEqual(table?.rows.first?.count, 16_384)
    }

    func testRowspanKeepsFollowingCellsInTheirColumns() {
        let table = HTMLTableParser.parse("<table><tr><td rowspan='2'>A</td><td>B</td></tr><tr><td>C</td></tr><tr><td>D</td><td>E</td></tr></table>")
        XCTAssertEqual(table?.rows, [["A", "B"], ["", "C"], ["D", "E"]])
    }

    func testCombinedSpansAndFullyOccupiedRows() {
        let table = HTMLTableParser.parse("<table><tr><th rowspan='2' colspan='2'>A</th><td rowspan='2'>B</td></tr><tr></tr><tr><td>C</td><td>D</td><td>E</td></tr></table>")
        XCTAssertEqual(table?.rows, [["A", "", "B"], ["", "", ""], ["C", "D", "E"]])
        XCTAssertEqual(table?.headerRows, [0])
    }

    func testZeroAndLargeRowspansStopAtRowGroupBoundary() {
        for span in ["0", "999999999"] {
            let table = HTMLTableParser.parse("<table><tbody><tr><td rowspan='\(span)'>A</td><td>B</td></tr><tr><td>C</td></tr></tbody><tbody><tr><td>D</td><td>E</td></tr></tbody></table>")
            XCTAssertEqual(table?.rows, [["A", "B"], ["", "C"], ["D", "E"]])
        }
    }

    func testColspanCannotOverwriteActiveRowspan() {
        XCTAssertNil(HTMLTableParser.parse("<table><tr><td>A</td><td rowspan='2'>B</td></tr><tr><td colspan='2'>C</td></tr></table>"))
    }
}
