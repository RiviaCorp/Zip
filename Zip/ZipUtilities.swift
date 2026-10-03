//
//  ZipUtilities.swift
//
//  Copyright © 2016 Rivia Corp s.r.o.
//

import Foundation

final class ZipUtilities {
    // Include root directory.
    // Default is true.
    //
    // e.g. The Test directory contains two files A.txt and B.txt.
    //
    // As true:
    // $ zip -r Test.zip Test/
    // $ unzip -l Test.zip
    //    Test/
    //    Test/A.txt
    //    Test/B.txt
    //
    // As false:
    // $ zip -r Test.zip Test/
    // $ unzip -l Test.zip
    //    A.txt
    //    B.txt
    let includeRootDirectory: Bool = true

    // File manager
    let fileManager: FileManager = .default

    ///  ProcessedFilePath struct
    struct ProcessedFilePath {
        let filePathURL: URL
        let fileName: String?

        func filePath() -> String {
            self.filePathURL.path
        }
    }

    // MARK: Path processing

    /// Process zip paths
    ///
    /// - parameter paths: Paths as NSURL.
    ///
    /// - returns: Array of ProcessedFilePath structs.
    func processZipPaths(_ paths: [URL]) -> [ProcessedFilePath] {
        var processedFilePaths: [ProcessedFilePath] = []
        for path in paths {
            let filePath: String = path.path
            var isDirectory: ObjCBool = false
            _ = self.fileManager.fileExists(atPath: filePath, isDirectory: &isDirectory)
            if !isDirectory.boolValue {
                let processedPath: ProcessedFilePath = .init(filePathURL: path, fileName: path.lastPathComponent)
                processedFilePaths.append(processedPath)
            } else {
                let directoryContents: [ProcessedFilePath] = self.expandDirectoryFilePath(path)
                processedFilePaths.append(contentsOf: directoryContents)
            }
        }
        return processedFilePaths
    }

    /// Expand directory contents and parse them into ProcessedFilePath structs.
    ///
    /// - parameter directory: Path of folder as NSURL.
    ///
    /// - returns: Array of ProcessedFilePath structs.
    func expandDirectoryFilePath(_ directory: URL) -> [ProcessedFilePath] {
        var processedFilePaths: [ProcessedFilePath] = []
        let directoryPath: String = directory.path
        if let enumerator = fileManager.enumerator(atPath: directoryPath) {
            while let filePathComponent = enumerator.nextObject() as? String {
                let path: URL = directory.appendingPathComponent(filePathComponent)
                let filePath: String = path.path

                var isDirectory: ObjCBool = false
                _ = self.fileManager.fileExists(atPath: filePath, isDirectory: &isDirectory)
                if !isDirectory.boolValue {
                    var fileName: String = filePathComponent
                    if self.includeRootDirectory {
                        let directoryName: String = directory.lastPathComponent
                        // Preserve the upstream path-joining semantics for archive entry names.
                        // swiftlint:disable:next legacy_objc_type
                        fileName = (directoryName as NSString).appendingPathComponent(filePathComponent)
                    }
                    let processedPath: ProcessedFilePath = .init(filePathURL: path, fileName: fileName)
                    processedFilePaths.append(processedPath)
                }
            }
        }
        return processedFilePaths
    }
}
