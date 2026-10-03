//
//  QuickZip.swift
//
//  Copyright © 2016 Rivia Corp s.r.o.
//

public import Foundation

public extension Zip {
    /// Get search path directory. For tvOS Documents directory doesn't exist.
    ///
    /// - returns: Search path directory
    private static func searchPathDirectory() -> FileManager.SearchPathDirectory {
        var searchPathDirectory: FileManager.SearchPathDirectory = .documentDirectory

        #if os(tvOS)
            searchPathDirectory = .cachesDirectory
        #endif

        return searchPathDirectory
    }

    // MARK: Quick Unzip

    /// Quick unzip a file. Unzips to a new folder inside the app's documents folder with the zip file's name.
    ///
    /// - parameter path: Path of zipped file. NSURL.
    ///
    /// - throws: Error if unzipping fails or if file is not found. Can be printed with a description variable.
    ///
    /// - returns: NSURL of the destination folder.
    class func quickUnzipFile(_ path: URL) throws -> URL {
        try self.quickUnzipFile(path, progress: nil)
    }

    /// Quick unzip a file. Unzips to a new folder inside the app's documents folder with the zip file's name.
    ///
    /// - parameter path: Path of zipped file. NSURL.
    /// - parameter progress: A progress closure called after unzipping each file in the archive. Double value betweem 0
    /// and 1.
    ///
    /// - throws: Error if unzipping fails or if file is not found. Can be printed with a description variable.
    ///
    /// - notes: Supports implicit progress composition
    ///
    /// - returns: NSURL of the destination folder.
    class func quickUnzipFile(_ path: URL, progress: ((_ progress: Double) -> Void)?) throws -> URL {
        let fileManager: FileManager = .default

        let fileExtension: String = path.pathExtension
        let fileName: String = path.lastPathComponent

        let directoryName: String = fileName.replacingOccurrences(of: ".\(fileExtension)", with: "")

        #if os(Linux)
            // urls(for:in:) is not yet implemented on Linux
            // See https://github.com/apple/swift-corelibs-foundation/blob/swift-4.2-branch/Foundation/FileManager.swift#L125
            let documentsURL: URL = fileManager.temporaryDirectory
        #else
            let documentsURL: URL = fileManager.urls(for: self.searchPathDirectory(), in: .userDomainMask)[0]
        #endif
        do {
            let destinationURL: URL = documentsURL.appendingPathComponent(directoryName, isDirectory: true)
            try self.unzipFile(path, destination: destinationURL, overwrite: true, password: nil, progress: progress)
            return destinationURL
        } catch {
            throw (ZipError.unzipFail)
        }
    }

    // MARK: Quick Zip

    /// Quick zip files.
    ///
    /// - parameter paths: Array of NSURL filepaths.
    /// - parameter fileName: File name for the resulting zip file.
    ///
    /// - throws: Error if zipping fails.
    ///
    /// - notes: Supports implicit progress composition
    ///
    /// - returns: NSURL of the destination folder.
    class func quickZipFiles(_ paths: [URL], fileName: String) throws -> URL {
        try self.quickZipFiles(paths, fileName: fileName, progress: nil)
    }

    /// Quick zip files.
    ///
    /// - parameter paths: Array of NSURL filepaths.
    /// - parameter fileName: File name for the resulting zip file.
    /// - parameter progress: A progress closure called after unzipping each file in the archive. Double value betweem 0
    /// and 1.
    ///
    /// - throws: Error if zipping fails.
    ///
    /// - notes: Supports implicit progress composition
    ///
    /// - returns: NSURL of the destination folder.
    class func quickZipFiles(
        _ paths: [URL],
        fileName: String,
        progress: ((_ progress: Double) -> Void)?,
    )
        throws -> URL
    {
        let fileManager: FileManager = .default
        #if os(Linux)
            // urls(for:in:) is not yet implemented on Linux
            // See https://github.com/apple/swift-corelibs-foundation/blob/swift-4.2-branch/Foundation/FileManager.swift#L125
            let documentsURL: URL = fileManager.temporaryDirectory
        #else
            let documentsURL: URL = fileManager.urls(for: self.searchPathDirectory(), in: .userDomainMask)[0] as URL
        #endif
        let destinationURL: URL = documentsURL.appendingPathComponent("\(fileName).zip")
        try self.zipFiles(paths: paths, zipFilePath: destinationURL, password: nil, progress: progress)
        return destinationURL
    }
}
