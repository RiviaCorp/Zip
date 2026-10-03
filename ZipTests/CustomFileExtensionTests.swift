//
//  CustomFileExtensionTests.swift
//
//  Copyright © 2026 Rivia Corp s.r.o.
//

import Foundation
import XCTest
import Zip

final class CustomFileExtensionTests: XCTestCase {
    func testConcurrentRegistrationPreservesEachExtension() {
        let prefix: String = UUID().uuidString
        DispatchQueue.concurrentPerform(iterations: 128) { index in
            let fileExtension: String = "\(prefix)-\(index)"
            for _ in 0 ..< 50 {
                Zip.addCustomFileExtension(fileExtension)
                XCTAssertTrue(Zip.isValidFileExtension(fileExtension))
                Zip.removeCustomFileExtension(fileExtension)
                XCTAssertFalse(Zip.isValidFileExtension(fileExtension))
            }
        }
    }

    func testConcurrentChangesKeepDefaultExtensionsValid() {
        let fileExtension: String = UUID().uuidString
        defer { Zip.removeCustomFileExtension(fileExtension) }

        DispatchQueue.concurrentPerform(iterations: 128) { _ in
            for _ in 0 ..< 50 {
                Zip.addCustomFileExtension(fileExtension)
                _ = Zip.isValidFileExtension(fileExtension)
                Zip.removeCustomFileExtension(fileExtension)
                XCTAssertTrue(Zip.isValidFileExtension("zip"))
                XCTAssertTrue(Zip.isValidFileExtension("cbz"))
            }
        }
        Zip.removeCustomFileExtension(fileExtension)
        XCTAssertFalse(Zip.isValidFileExtension(fileExtension))
    }

    func testRegisteredArchiveExtensionRoundTripsAndCanBeRemoved() throws {
        let directory: URL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("ZipExtensionTests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let fileExtension: String = UUID().uuidString
        Zip.addCustomFileExtension(fileExtension)
        defer {
            Zip.removeCustomFileExtension(fileExtension)
            do {
                try FileManager.default.removeItem(at: directory)
            } catch {
                XCTFail("Could not remove the test directory: \(error)")
            }
        }

        let source: URL = directory.appendingPathComponent("photo-data.bin")
        let data: Data = .init(0 ... 255)
        try data.write(to: source)
        let archive: URL = directory.appendingPathComponent("archive").appendingPathExtension(fileExtension)
        let destination: URL = directory.appendingPathComponent("extracted", isDirectory: true)
        try Zip.zipFiles(paths: [source], zipFilePath: archive, password: nil, progress: nil)
        try Zip.unzipFile(archive, destination: destination, overwrite: true, password: nil, progress: nil)
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent(source.lastPathComponent)), data)

        Zip.removeCustomFileExtension(fileExtension)
        XCTAssertThrowsError(try Zip.unzipFile(
            archive,
            destination: directory.appendingPathComponent("after-removal", isDirectory: true),
            overwrite: true,
            password: nil,
            progress: nil,
        )) { error in
            guard let zipError: ZipError = error as? ZipError, case .fileNotFound = zipError else {
                XCTFail("Expected an unregistered-extension error, received \(error)")
                return
            }
        }
    }
}
