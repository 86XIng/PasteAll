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
}
