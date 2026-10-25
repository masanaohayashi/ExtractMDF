import XCTest
@testable import LZMCore

final class MDFArchiveTests: XCTestCase {
    func testWritableDirectoryProbe() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        try Extraction.checkWritableDirectory(directory)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        XCTAssertThrowsError(try Extraction.checkWritableDirectory(directory)) {
            XCTAssertTrue(Extraction.isWriteAccessError($0))
        }
        XCTAssertFalse(Extraction.isWriteAccessError(NSError(domain: NSCocoaErrorDomain, code: NSFileWriteFileExistsError)))
        XCTAssertTrue(Extraction.isWriteAccessError(NSError(domain: NSCocoaErrorDomain, code: NSFileWriteVolumeReadOnlyError)))
    }

    func testExactSaveRequiresOverwriteAndReplacesSymlinkSafely() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = try Extraction.saveExact(Data([1]), name: "TEST.MID", directory: directory)
        XCTAssertThrowsError(try Extraction.saveExact(Data([2]), name: "TEST.MID", directory: directory))
        XCTAssertEqual(try Data(contentsOf: target), Data([1]))
        _ = try Extraction.saveExact(Data([2]), name: "TEST.MID", directory: directory, overwrite: true)
        XCTAssertEqual(try Data(contentsOf: target), Data([2]))
        let link = directory.appendingPathComponent("LINK.MID")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        _ = try Extraction.saveExact(Data([3]), name: "LINK.MID", directory: directory, overwrite: true)
        XCTAssertEqual(try Data(contentsOf: link), Data([3]))
        XCTAssertEqual(try Data(contentsOf: target), Data([2]))
    }

    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")))
    }

    func testOriginalLZMTinyMIDI() throws {
        let archive = try MDFArchive(data: fixture("tiny.mdf"))
        XCTAssertEqual(archive.entries.count, 1)
        XCTAssertEqual(archive.entries[0].name, "TEST.MID")
        XCTAssertEqual(archive.entries[0].typeName, "MIDI")
        XCTAssertEqual(try archive.extract(archive.entries[0]), try fixture("tiny.mid"))
    }

    func testOriginalLZMLongAndOverlappingReferences() throws {
        let archive = try MDFArchive(data: fixture("mixed.mdf"))
        XCTAssertEqual(try archive.extract(archive.entries[0]), try fixture("mixed.mid"))
    }

    func testMultipleEntries() throws {
        // Assemble two entries from original LZM streams; no recompression.
        var data = try fixture("tiny.mdf")
        data[79] = 2
        data.append(try fixture("mixed.mdf").dropFirst(160))
        let archive = try MDFArchive(data: data)
        XCTAssertEqual(archive.entries.count, 2)
        XCTAssertEqual(try archive.extract(archive.entries[1]), try fixture("mixed.mid"))
    }

    func testDamagedShiftJISCommentPreservesReadableCharacters() throws {
        var data = try fixture("tiny.mdf")
        // あ + an invalid lead byte + ASCII. The rest of the title must survive.
        data.replaceSubrange(6..<10, with: [0x82, 0xa0, 0x82, 0x20])
        let archive = try MDFArchive(data: data)
        XCTAssertTrue(archive.title.hasPrefix("あ�"))
    }

    func testRejectsTruncatedHeadersAndPayloads() throws {
        let original = try fixture("tiny.mdf")
        for count in 0..<original.count {
            XCTAssertThrowsError(try MDFArchive(data: original.prefix(count)), "length \(count)")
        }
    }

    func testRejectsWrongSignatureCountAndHugeOutput() throws {
        var data = try fixture("tiny.mdf")
        data[0] = 0
        XCTAssertThrowsError(try MDFArchive(data: data))
        data = try fixture("tiny.mdf")
        data[76] = 0xff
        XCTAssertThrowsError(try MDFArchive(data: data))
        data = try fixture("tiny.mdf")
        data[204] = 0xff
        XCTAssertThrowsError(try MDFArchive(data: data))
    }

    func testRejectsInvalidReferenceSizeAndMissingEnd() throws {
        var data = try fixture("tiny.mdf")
        data[208] = 0 // short reference before any output
        let badReference = try MDFArchive(data: data)
        XCTAssertThrowsError(try badReference.extract(badReference.entries[0]))
        data = try fixture("tiny.mdf")
        data[207] = 25 // actual output is 26
        let badSize = try MDFArchive(data: data)
        XCTAssertThrowsError(try badSize.extract(badSize.entries[0]))
        data = try fixture("tiny.mdf")
        data[data.count - 1] = 255 // replace end marker's extra length
        let badEnd = try MDFArchive(data: data)
        XCTAssertThrowsError(try badEnd.extract(badEnd.entries[0]))
    }

    func testNoOverwriteAndSafeNames() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try Extraction.save(Data([1]), name: "TEST.MID", directory: directory)
        let second = try Extraction.save(Data([2]), name: "TEST.MID", directory: directory)
        XCTAssertEqual(first.lastPathComponent, "TEST.MID")
        XCTAssertEqual(second.lastPathComponent, "TEST (2).MID")
        XCTAssertEqual(try Data(contentsOf: first), Data([1]))
        XCTAssertEqual(Extraction.safeName("../../evil"), ".._.._evil")
        XCTAssertEqual(Extraction.safeName(".."), "untitled")
        // Existing symlinks must never overwrite their targets.
        let link = directory.appendingPathComponent("LINK.MID")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: first)
        let third = try Extraction.save(Data([3]), name: "LINK.MID", directory: directory)
        XCTAssertNotEqual(third, link)
        XCTAssertEqual(try Data(contentsOf: first), Data([1]))
    }
}
