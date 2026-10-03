//
//  ZipTests.swift
//
//  Copyright © 2015 Rivia Corp s.r.o.
//

import XCTest
@testable import Zip

final class ZipTests: XCTestCase {
    private func url(forResource resource: String, withExtension ext: String? = nil) -> URL? {
        #if Xcode
            return Bundle(for: ZipTests.self).url(forResource: resource, withExtension: ext)
        #else
            let testDirPath: URL = .init(fileURLWithPath: String(#file)).deletingLastPathComponent()
            let resourcePath: URL = testDirPath.appendingPathComponent("Resources").appendingPathComponent(resource)
            return ext.map { resourcePath.appendingPathExtension($0) } ?? resourcePath
        #endif
    }

    private func temporaryDirectory() -> URL {
        if #available(macOS 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
            FileManager.default.temporaryDirectory
        } else {
            URL(fileURLWithPath: NSTemporaryDirectory())
        }
    }

    private func autoRemovingSandbox() throws -> URL {
        let sandbox: URL = self.temporaryDirectory().appendingPathComponent(
            "ZipTests_" + UUID().uuidString,
            isDirectory: true,
        )
        // We can always create it. UUID should be unique.
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true, attributes: nil)
        // Schedule the teardown block _after_ creating the directory has been created (so that if it fails, no teardown
        // block is registered).
        self.addTeardownBlock {
            do {
                try FileManager.default.removeItem(at: sandbox)
            } catch {
                print("Could not remove test sandbox at '\(sandbox.path)': \(error)")
            }
        }
        return sandbox
    }

    func testQuickUnzip() throws {
        let filePath: URL = try XCTUnwrap(self.url(forResource: "bb8", withExtension: "zip"))
        let destinationURL: URL = try Zip.quickUnzipFile(filePath)
        self.addTeardownBlock {
            try? FileManager.default.removeItem(at: destinationURL)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))
    }

    func testQuickUnzipNonExistingPath() {
        let filePath: URL = .init(fileURLWithPath: "/some/path/to/nowhere/bb9.zip")
        XCTAssertThrowsError(try Zip.quickUnzipFile(filePath))
    }

    func testQuickUnzipNonZipPath() throws {
        let filePath: URL = try XCTUnwrap(self.url(forResource: "3crBXeO", withExtension: "gif"))
        XCTAssertThrowsError(try Zip.quickUnzipFile(filePath))
    }

    func testQuickUnzipProgress() throws {
        let filePath: URL = try XCTUnwrap(self.url(forResource: "bb8", withExtension: "zip"))
        let destinationURL: URL = try Zip.quickUnzipFile(filePath) { progress in
            XCTAssertFalse(progress.isNaN)
        }
        self.addTeardownBlock {
            try? FileManager.default.removeItem(at: destinationURL)
        }
    }

    func testQuickUnzipOnlineURL() throws {
        let filePath: URL = try XCTUnwrap(URL(string: "http://www.google.com/google.zip"))
        XCTAssertThrowsError(try Zip.quickUnzipFile(filePath))
    }

    func testUnzip() throws {
        let filePath: URL = try XCTUnwrap(self.url(forResource: "bb8", withExtension: "zip"))
        let destinationPath: URL = try autoRemovingSandbox()

        try Zip.unzipFile(filePath, destination: destinationPath, overwrite: true, password: "password", progress: nil)

        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationPath.path))
    }

    func testImplicitProgressUnzip() throws {
        let progress: Progress = .init(totalUnitCount: 1)

        let filePath: URL = try XCTUnwrap(self.url(forResource: "bb8", withExtension: "zip"))
        let destinationPath: URL = try autoRemovingSandbox()

        progress.becomeCurrent(withPendingUnitCount: 1)
        try Zip.unzipFile(filePath, destination: destinationPath, overwrite: true, password: "password", progress: nil)
        progress.resignCurrent()

        XCTAssertEqual(progress.totalUnitCount, progress.completedUnitCount)
    }

    func testImplicitProgressZip() throws {
        let progress: Progress = .init(totalUnitCount: 1)

        let imageURL1: URL = try XCTUnwrap(self.url(forResource: "3crBXeO", withExtension: "gif"))
        let imageURL2: URL = try XCTUnwrap(self.url(forResource: "kYkLkPf", withExtension: "gif"))
        let sandboxFolder: URL = try autoRemovingSandbox()
        let zipFilePath: URL = sandboxFolder.appendingPathComponent("archive.zip")

        progress.becomeCurrent(withPendingUnitCount: 1)
        try Zip.zipFiles(paths: [imageURL1, imageURL2], zipFilePath: zipFilePath, password: nil, progress: nil)
        progress.resignCurrent()

        XCTAssertEqual(progress.totalUnitCount, progress.completedUnitCount)
    }

    func testQuickZip() throws {
        let imageURL1: URL = try XCTUnwrap(self.url(forResource: "3crBXeO", withExtension: "gif"))
        let imageURL2: URL = try XCTUnwrap(self.url(forResource: "kYkLkPf", withExtension: "gif"))
        let destinationURL: URL = try Zip.quickZipFiles([imageURL1, imageURL2], fileName: "archive")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))
        self.addTeardownBlock {
            try? FileManager.default.removeItem(at: destinationURL)
        }
    }

    func testQuickZipFolder() throws {
        let fileManager: FileManager = .default
        let imageURL1: URL = try XCTUnwrap(self.url(forResource: "3crBXeO", withExtension: "gif"))
        let imageURL2: URL = try XCTUnwrap(self.url(forResource: "kYkLkPf", withExtension: "gif"))
        let folderURL: URL = try autoRemovingSandbox()
        let targetImageURL1: URL = folderURL.appendingPathComponent("3crBXeO.gif")
        let targetImageURL2: URL = folderURL.appendingPathComponent("kYkLkPf.gif")
        try fileManager.copyItem(at: imageURL1, to: targetImageURL1)
        try fileManager.copyItem(at: imageURL2, to: targetImageURL2)
        let destinationURL: URL = try Zip.quickZipFiles([folderURL], fileName: "directory")
        XCTAssertTrue(fileManager.fileExists(atPath: destinationURL.path))
        self.addTeardownBlock {
            try? FileManager.default.removeItem(at: destinationURL)
        }
    }

    func testZip() throws {
        let imageURL1: URL = try XCTUnwrap(self.url(forResource: "3crBXeO", withExtension: "gif"))
        let imageURL2: URL = try XCTUnwrap(self.url(forResource: "kYkLkPf", withExtension: "gif"))
        let sandboxFolder: URL = try autoRemovingSandbox()
        let zipFilePath: URL = sandboxFolder.appendingPathComponent("archive.zip")
        try Zip.zipFiles(paths: [imageURL1, imageURL2], zipFilePath: zipFilePath, password: nil, progress: nil)
        XCTAssertTrue(FileManager.default.fileExists(atPath: zipFilePath.path))
    }

    func testZipUnzipPassword() throws {
        let imageURL1: URL = try XCTUnwrap(self.url(forResource: "3crBXeO", withExtension: "gif"))
        let imageURL2: URL = try XCTUnwrap(self.url(forResource: "kYkLkPf", withExtension: "gif"))
        let zipFilePath: URL = try autoRemovingSandbox().appendingPathComponent("archive.zip")
        try Zip.zipFiles(paths: [imageURL1, imageURL2], zipFilePath: zipFilePath, password: "password", progress: nil)
        let fileManager: FileManager = .default
        XCTAssertTrue(fileManager.fileExists(atPath: zipFilePath.path))
        let directoryName: String = zipFilePath.lastPathComponent.replacingOccurrences(
            of: ".\(zipFilePath.pathExtension)",
            with: "",
        )
        let destinationURL: URL = try autoRemovingSandbox().appendingPathComponent(directoryName, isDirectory: true)
        try Zip.unzipFile(
            zipFilePath,
            destination: destinationURL,
            overwrite: true,
            password: "password",
            progress: nil,
        )
        XCTAssertTrue(fileManager.fileExists(atPath: destinationURL.path))
    }

    func testUnzipWithUnsupportedPermissions() throws {
        let permissionsURL: URL = try XCTUnwrap(self.url(forResource: "unsupported_permissions", withExtension: "zip"))
        let unzipDestination: URL = try Zip.quickUnzipFile(permissionsURL)
        let permission644: URL = unzipDestination.appendingPathComponent("unsupported_permission")
            .appendingPathExtension("txt")
        let foundPermissions: Int? = try FileManager.default
            .attributesOfItem(atPath: permission644.path)[.posixPermissions] as? Int
        #if os(Linux)
            let expectedPermissions: Int = 0o664
        #else
            let expectedPermissions: Int = 0o644
        #endif
        XCTAssertNotNil(foundPermissions)
        XCTAssertEqual(
            foundPermissions,
            expectedPermissions,
            "\(foundPermissions.map { String($0, radix: 8) } ?? "nil") is not equal to \(String(expectedPermissions, radix: 8))",
        )
    }

    func testUnzipPermissions() throws {
        let permissionsURL: URL = try XCTUnwrap(self.url(forResource: "permissions", withExtension: "zip"))
        let unzipDestination: URL = try Zip.quickUnzipFile(permissionsURL)
        self.addTeardownBlock {
            try? FileManager.default.removeItem(at: unzipDestination)
        }
        let fileManager: FileManager = .default
        let permission777: URL = unzipDestination.appendingPathComponent("permission_777").appendingPathExtension("txt")
        let permission600: URL = unzipDestination.appendingPathComponent("permission_600").appendingPathExtension("txt")
        let permission604: URL = unzipDestination.appendingPathComponent("permission_604").appendingPathExtension("txt")

        let attributes777: [FileAttributeKey: Any] = try fileManager.attributesOfItem(atPath: permission777.path)
        let attributes600: [FileAttributeKey: Any] = try fileManager.attributesOfItem(atPath: permission600.path)
        let attributes604: [FileAttributeKey: Any] = try fileManager.attributesOfItem(atPath: permission604.path)
        XCTAssertEqual(attributes777[.posixPermissions] as? Int, 0o777)
        XCTAssertEqual(attributes600[.posixPermissions] as? Int, 0o600)
        XCTAssertEqual(attributes604[.posixPermissions] as? Int, 0o604)
    }

    // Tests if https://github.com/marmelroy/Zip/issues/245 does not uccor anymore.
    func testUnzipProtectsAgainstPathTraversal() throws {
        let filePath: URL = try XCTUnwrap(self.url(forResource: "pathTraversal", withExtension: "zip"))
        let destinationPath: URL = try autoRemovingSandbox()

        do {
            try Zip.unzipFile(
                filePath,
                destination: destinationPath,
                overwrite: true,
                password: "password",
                progress: nil,
            )
            XCTFail("ZipError.unzipFail expected.")
        } catch {
            // The malicious archive is expected to throw during extraction.
        }

        let fileManager: FileManager = .default
        XCTAssertFalse(fileManager
            .fileExists(atPath: destinationPath.appendingPathComponent("../naughtyFile.txt").path))
    }

    func testQuickUnzipSubDir() throws {
        let bookURL: URL = try XCTUnwrap(self.url(forResource: "bb8", withExtension: "zip"))
        let unzipDestination: URL = try Zip.quickUnzipFile(bookURL)
        self.addTeardownBlock {
            try? FileManager.default.removeItem(at: unzipDestination)
        }
        let fileManager: FileManager = .default
        let subDir: URL = unzipDestination.appendingPathComponent("subDir")
        let imageURL: URL = subDir.appendingPathComponent("r2W9yu9").appendingPathExtension("gif")

        XCTAssertTrue(fileManager.fileExists(atPath: unzipDestination.path))
        XCTAssertTrue(fileManager.fileExists(atPath: subDir.path))
        XCTAssertTrue(fileManager.fileExists(atPath: imageURL.path))
    }

    func testFileExtensionIsNotInvalidForValidURL() {
        let fileURL: URL? = .init(string: "file.cbz")
        let result: Bool = Zip.fileExtensionIsInvalid(fileURL?.pathExtension)
        XCTAssertFalse(result)
    }

    func testFileExtensionIsInvalidForInvalidURL() {
        let fileURL: URL? = .init(string: "file.xyz")
        let result: Bool = Zip.fileExtensionIsInvalid(fileURL?.pathExtension)
        XCTAssertTrue(result)
    }

    func testAddedCustomFileExtensionIsValid() {
        let fileExtension: String = "cstm"
        Zip.addCustomFileExtension(fileExtension)
        let result: Bool = Zip.isValidFileExtension(fileExtension)
        XCTAssertTrue(result)
        Zip.removeCustomFileExtension(fileExtension)
    }

    func testRemovedCustomFileExtensionIsInvalid() {
        let fileExtension: String = "cstm"
        Zip.addCustomFileExtension(fileExtension)
        Zip.removeCustomFileExtension(fileExtension)
        let result: Bool = Zip.isValidFileExtension(fileExtension)
        XCTAssertFalse(result)
    }

    func testDefaultFileExtensionsIsValid() {
        XCTAssertTrue(Zip.isValidFileExtension("zip"))
        XCTAssertTrue(Zip.isValidFileExtension("cbz"))
    }

    func testDefaultFileExtensionsIsNotRemoved() {
        Zip.removeCustomFileExtension("zip")
        Zip.removeCustomFileExtension("cbz")
        XCTAssertTrue(Zip.isValidFileExtension("zip"))
        XCTAssertTrue(Zip.isValidFileExtension("cbz"))
    }
}
