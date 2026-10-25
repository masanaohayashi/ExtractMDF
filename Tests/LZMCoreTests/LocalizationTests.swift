import XCTest
@testable import LZMCore

final class LocalizationTests: XCTestCase {
    private func bundle(_ language: String) throws -> Bundle {
        let url = try XCTUnwrap(L10n.bundle.url(forResource: language, withExtension: "lproj"))
        return try XCTUnwrap(Bundle(url: url))
    }

    func testEnglishAndJapaneseResourcesHaveMatchingKeys() throws {
        func keys(_ language: String, extension ext: String) throws -> Set<String> {
            let url = try XCTUnwrap(bundle(language).url(forResource: "Localizable", withExtension: ext))
            let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
            return Set(try XCTUnwrap(plist as? [String: Any]).keys)
        }
        for ext in ["strings", "stringsdict"] {
            XCTAssertEqual(try keys("en", extension: ext), try keys("ja", extension: ext))
        }
    }

    func testPluralFormsAndJapaneseCounts() throws {
        let en = try bundle("en")
        let ja = try bundle("ja")
        func count(_ key: String, _ value: Int, _ bundle: Bundle) -> String {
            String.localizedStringWithFormat(bundle.localizedString(forKey: key, value: nil, table: nil), value)
        }
        XCTAssertEqual(count("files.extract", 1, en), "Extract 1 File")
        XCTAssertEqual(count("files.extract", 2, en), "Extract 2 Files")
        XCTAssertEqual(count("files.extract", 0, en), "Extract 0 Files")
        XCTAssertEqual(count("files.extract", 2, ja), "2ファイルを解凍")
        XCTAssertEqual(count("files.completed", 1, en), "Extracted 1 file.")
        XCTAssertEqual(count("files.completed", 2, en), "Extracted 2 files.")
    }

    func testControlsAndErrorsAreTranslated() throws {
        let en = try bundle("en")
        let key = "元のMDFと同じフォルダに保存"
        XCTAssertEqual(en.localizedString(forKey: key, value: nil, table: nil),
            "Save in the same folder as each MDF file")
        let error = "格納ファイル数が不正です。"
        XCTAssertEqual(en.localizedString(forKey: error, value: nil, table: nil),
            "The archive contains an invalid file count.")
    }
}
