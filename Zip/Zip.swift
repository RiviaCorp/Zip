//
//  Zip.swift
//
//  Copyright © 2015 Rivia Corp s.r.o.
//

public import Foundation
@_implementationOnly import Minizip

// MARK: - ZipError

/// Zip error type
public enum ZipError: Error {
    /// File not found
    case fileNotFound
    /// Unzip fail
    case unzipFail
    /// Zip fail
    case zipFail

    /// User readable description
    public var description: String {
        switch self {
            case .fileNotFound:
                NSLocalizedString("File not found.", bundle: .main, comment: "")

            case .unzipFail:
                NSLocalizedString("Failed to unzip file.", bundle: .main, comment: "")

            case .zipFail:
                NSLocalizedString("Failed to zip file.", bundle: .main, comment: "")
        }
    }
}

// MARK: - ZipCompression

public enum ZipCompression: Int {
    case NoCompression
    case BestSpeed
    case DefaultCompression
    case BestCompression

    var minizipCompression: Int32 {
        switch self {
            case .NoCompression:
                Z_NO_COMPRESSION

            case .BestSpeed:
                Z_BEST_SPEED

            case .DefaultCompression:
                Z_DEFAULT_COMPRESSION

            case .BestCompression:
                Z_BEST_COMPRESSION
        }
    }
}

// MARK: - ArchiveFile

// NSData is part of the upstream initializer signature and must remain source compatible.
// swiftlint:disable legacy_objc_type
/// Data in memory that will be archived as a file.
public struct ArchiveFile {
    var filename: String
    var data: NSData
    var modifiedTime: Date? = nil

    public init(filename: String, data: NSData, modifiedTime: Date?) {
        self.filename = filename
        self.data = data
        self.modifiedTime = modifiedTime
    }
}

// swiftlint:enable legacy_objc_type

// MARK: - Zip

/// Zip class
public class Zip {
    private static let customFileExtensions: CustomFileExtensions = .init()

    // All access to the set takes the same lock, keeping the synchronous API safe to share.
    private final class CustomFileExtensions: @unchecked Sendable {
        private let lock: NSLock = .init()
        private var values: Set<String> = []

        func withLock<Result>(_ body: (inout Set<String>) -> Result) -> Result {
            self.lock.lock()
            defer { self.lock.unlock() }
            return body(&self.values)
        }
    }

    // MARK: Lifecycle

    /// Init
    ///
    /// - returns: Zip object
    public init() {
        // Instances carry no state; archive operations are class methods.
    }

    // MARK: Unzip

    /// Unzip file
    ///
    /// - parameter zipFilePath: Local file path of zipped file. NSURL.
    /// - parameter destination: Local file path to unzip to. NSURL.
    /// - parameter overwrite:   Overwrite bool.
    /// - parameter password:    Optional password if file is protected.
    /// - parameter progress: A progress closure called after unzipping each file in the archive. Double value betweem 0
    /// and 1.
    ///
    /// - throws: Error if unzipping fails or if fail is not found. Can be printed with a description variable.
    ///
    /// - notes: Supports implicit progress composition

    public class func unzipFile(
        _ zipFilePath: URL,
        destination: URL,
        overwrite: Bool,
        password: String?,
        progress: ((_ progress: Double) -> Void)? = nil,
        fileOutputHandler: ((_ unzippedFile: URL) -> Void)? = nil,
    )
        throws
    {
        // File manager
        let fileManager: FileManager = .default

        // Check whether a zip file exists at path.
        let path: String = zipFilePath.path

        if fileManager.fileExists(atPath: path) == false || self.fileExtensionIsInvalid(zipFilePath.pathExtension) {
            throw ZipError.fileNotFound
        }

        // Unzip set up
        var ret: Int32 = 0
        var crc_ret: Int32 = 0
        let bufferSize: UInt32 = 4096
        var buffer: [CUnsignedChar] = .init(repeating: 0, count: Int(bufferSize))

        // Progress handler set up
        var totalSize: Double = 0.0
        var currentPosition: Double = 0.0
        let fileAttributes: [FileAttributeKey: Any] = try fileManager.attributesOfItem(atPath: path)
        if let attributeFileSize = fileAttributes[FileAttributeKey.size] as? Double {
            totalSize += attributeFileSize
        }

        let progressTracker: Progress = .init(totalUnitCount: Int64(totalSize))
        progressTracker.isCancellable = false
        progressTracker.isPausable = false
        progressTracker.kind = ProgressKind.file

        // Begin unzipping
        let zip: unzFile? = unzOpen64(path)
        defer {
            unzClose(zip)
        }
        if unzGoToFirstFile(zip) != UNZ_OK {
            throw ZipError.unzipFail
        }
        repeat {
            if let cPassword = password?.cString(using: String.Encoding.ascii) {
                ret = unzOpenCurrentFilePassword(zip, cPassword)
            } else {
                ret = unzOpenCurrentFile(zip)
            }
            if ret != UNZ_OK {
                throw ZipError.unzipFail
            }
            var fileInfo: unz_file_info64 = .init()
            memset(&fileInfo, 0, MemoryLayout<unz_file_info>.size)
            ret = unzGetCurrentFileInfo64(zip, &fileInfo, nil, 0, nil, 0, nil, 0)
            if ret != UNZ_OK {
                unzCloseCurrentFile(zip)
                throw ZipError.unzipFail
            }
            currentPosition += Double(fileInfo.compressed_size)
            let fileNameSize: Int = .init(fileInfo.size_filename) + 1
            // let fileName = UnsafeMutablePointer<CChar>(allocatingCapacity: fileNameSize)
            let fileName: UnsafeMutablePointer<CChar> = .allocate(capacity: fileNameSize)

            unzGetCurrentFileInfo64(zip, &fileInfo, fileName, UInt(fileNameSize), nil, 0, nil, 0)
            fileName[Int(fileInfo.size_filename)] = 0

            var pathString: String = .init(cString: fileName)

            guard !pathString.isEmpty else {
                throw ZipError.unzipFail
            }

            var isDirectory: Bool = false
            let fileInfoSizeFileName: Int = .init(fileInfo.size_filename - 1)
            if
                fileName[fileInfoSizeFileName] == "/".cString(using: String.Encoding.utf8)?
                    .first || fileName[fileInfoSizeFileName] == "\\".cString(using: String.Encoding.utf8)?.first
            {
                isDirectory = true
            }
            free(fileName)
            if pathString.rangeOfCharacter(from: CharacterSet(charactersIn: "/\\")) != nil {
                pathString = pathString.replacingOccurrences(of: "\\", with: "/")
            }

            let fullPath: String = destination.appendingPathComponent(pathString).standardized.path
            // .standardized removes any ".. to move a level up".
            // If we then check that the fullPath starts with the destination directory we know we are not extracting
            // "outside" te destination.
            guard fullPath.starts(with: destination.standardized.path) else {
                throw ZipError.unzipFail
            }

            let creationDate: Date = .init()

            let directoryAttributes: [FileAttributeKey: Any]?
            #if os(Linux)
                // On Linux, setting attributes is not yet really implemented.
                // In Swift 4.2, the only settable attribute is `.posixPermissions`.
                // See https://github.com/apple/swift-corelibs-foundation/blob/swift-4.2-branch/Foundation/FileManager.swift#L182-L196
                directoryAttributes = nil
            #else
                directoryAttributes = [
                    .creationDate: creationDate,
                    .modificationDate: creationDate,
                ]
            #endif

            do {
                if isDirectory {
                    try fileManager.createDirectory(
                        atPath: fullPath,
                        withIntermediateDirectories: true,
                        attributes: directoryAttributes,
                    )
                } else {
                    let parentDirectory: String = URL(fileURLWithPath: fullPath).deletingLastPathComponent().path
                    try fileManager.createDirectory(
                        atPath: parentDirectory,
                        withIntermediateDirectories: true,
                        attributes: directoryAttributes,
                    )
                }
            } catch {
                // Retain the upstream behavior of continuing if directory creation fails.
            }
            if fileManager.fileExists(atPath: fullPath) && !isDirectory && !overwrite {
                unzCloseCurrentFile(zip)
                ret = unzGoToNextFile(zip)
            }

            var writeBytes: UInt64 = 0
            var filePointer: UnsafeMutablePointer<FILE>?
            filePointer = fopen(fullPath, "wb")
            while filePointer != nil {
                let readBytes: Int32 = unzReadCurrentFile(zip, &buffer, bufferSize)
                if readBytes > 0 {
                    guard fwrite(buffer, Int(readBytes), 1, filePointer) == 1 else {
                        throw ZipError.unzipFail
                    }

                    writeBytes += UInt64(readBytes)
                } else {
                    break
                }
            }

            if let filePointer {
                fclose(filePointer)
            }

            crc_ret = unzCloseCurrentFile(zip)
            if crc_ret == UNZ_CRCERROR {
                throw ZipError.unzipFail
            }
            guard writeBytes == fileInfo.uncompressed_size else {
                throw ZipError.unzipFail
            }

            // Set file permissions from current fileInfo
            if fileInfo.external_fa != 0 {
                let permissions: UInt = (fileInfo.external_fa >> 16) & 0x1FF
                // We will devifne a valid permission range between Owner read only to full access
                if permissions >= 0o400 && permissions <= 0o777 {
                    do {
                        try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: fullPath)
                    } catch {
                        print("Failed to set permissions to file \(fullPath), error: \(error)")
                    }
                }
            }

            ret = unzGoToNextFile(zip)

            // Update progress handler
            if let progress {
                progress(currentPosition / totalSize)
            }

            if
                let fileOutputHandler,
                let encodedString = fullPath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                let fileURL = URL(string: encodedString)
            {
                fileOutputHandler(fileURL)
            }

            progressTracker.completedUnitCount = Int64(currentPosition)
        } while
            ret == UNZ_OK && ret != UNZ_END_OF_LIST_OF_FILE

        // Completed. Update progress handler.
        if let progress {
            progress(1.0)
        }

        progressTracker.completedUnitCount = Int64(totalSize)
    }

    // MARK: Zip

    /// Zip files.
    ///
    /// - parameter paths:       Array of NSURL filepaths.
    /// - parameter zipFilePath: Destination NSURL, should lead to a .zip filepath.
    /// - parameter password:    Password string. Optional.
    /// - parameter compression: Compression strategy
    /// - parameter progress: A progress closure called after unzipping each file in the archive. Double value betweem 0
    /// and 1.
    ///
    /// - throws: Error if zipping fails.
    ///
    /// - notes: Supports implicit progress composition
    public class func zipFiles(
        paths: [URL],
        zipFilePath: URL,
        password: String?,
        compression: ZipCompression = .DefaultCompression,
        progress: ((_ progress: Double) -> Void)?,
    )
        throws
    {
        // File manager
        let fileManager: FileManager = .default

        // Check whether a zip file exists at path.
        let destinationPath: String = zipFilePath.path

        // Process zip paths
        let processedPaths: [ZipUtilities.ProcessedFilePath] = ZipUtilities().processZipPaths(paths)

        // Zip set up
        let chunkSize: Int = 16384

        // Progress handler set up
        var currentPosition: Double = 0.0
        var totalSize: Double = 0.0
        // Get totalSize for progress handler
        for path in processedPaths {
            do {
                let filePath: String = path.filePath()
                let fileAttributes: [FileAttributeKey: Any] = try fileManager.attributesOfItem(atPath: filePath)
                let fileSize: Double? = fileAttributes[FileAttributeKey.size] as? Double
                if let fileSize {
                    totalSize += fileSize
                }
            } catch {
                // Progress is best effort when a file size cannot be read.
            }
        }

        let progressTracker: Progress = .init(totalUnitCount: Int64(totalSize))
        progressTracker.isCancellable = false
        progressTracker.isPausable = false
        progressTracker.kind = ProgressKind.file

        // Begin Zipping
        let zip: zipFile? = zipOpen(destinationPath, APPEND_STATUS_CREATE)
        for path in processedPaths {
            let filePath: String = path.filePath()
            var isDirectory: ObjCBool = false
            _ = fileManager.fileExists(atPath: filePath, isDirectory: &isDirectory)
            if !isDirectory.boolValue {
                guard let input = fopen(filePath, "r") else {
                    throw ZipError.zipFail
                }

                defer { fclose(input) }
                let fileName: String? = path.fileName
                var zipInfo: zip_fileinfo = .init(
                    tmz_date: tm_zip(tm_sec: 0, tm_min: 0, tm_hour: 0, tm_mday: 0, tm_mon: 0, tm_year: 0),
                    dosDate: 0,
                    internal_fa: 0,
                    external_fa: 0,
                )
                do {
                    let fileAttributes: [FileAttributeKey: Any] = try fileManager.attributesOfItem(atPath: filePath)
                    if let fileDate = fileAttributes[FileAttributeKey.modificationDate] as? Date {
                        let components: DateComponents = Calendar.current.dateComponents(
                            [.year, .month, .day, .hour, .minute, .second],
                            from: fileDate,
                        )
                        zipInfo.tmz_date.tm_sec = UInt32(components.second!)
                        zipInfo.tmz_date.tm_min = UInt32(components.minute!)
                        zipInfo.tmz_date.tm_hour = UInt32(components.hour!)
                        zipInfo.tmz_date.tm_mday = UInt32(components.day!)
                        zipInfo.tmz_date.tm_mon = UInt32(components.month!) - 1
                        zipInfo.tmz_date.tm_year = UInt32(components.year!)
                    }
                    if let fileSize = fileAttributes[FileAttributeKey.size] as? Double {
                        currentPosition += fileSize
                    }
                } catch {
                    // Files without readable timestamps retain the zeroed ZIP metadata.
                }
                guard let buffer = malloc(chunkSize) else {
                    throw ZipError.zipFail
                }

                if let password, let fileName {
                    zipOpenNewFileInZip3(
                        zip,
                        fileName,
                        &zipInfo,
                        nil,
                        0,
                        nil,
                        0,
                        nil,
                        Z_DEFLATED,
                        compression.minizipCompression,
                        0,
                        -MAX_WBITS,
                        DEF_MEM_LEVEL,
                        Z_DEFAULT_STRATEGY,
                        password,
                        0,
                    )
                } else if let fileName {
                    zipOpenNewFileInZip3(
                        zip,
                        fileName,
                        &zipInfo,
                        nil,
                        0,
                        nil,
                        0,
                        nil,
                        Z_DEFLATED,
                        compression.minizipCompression,
                        0,
                        -MAX_WBITS,
                        DEF_MEM_LEVEL,
                        Z_DEFAULT_STRATEGY,
                        nil,
                        0,
                    )
                } else {
                    throw ZipError.zipFail
                }
                var length: Int = 0
                while feof(input) == 0 {
                    length = fread(buffer, 1, chunkSize, input)
                    zipWriteInFileInZip(zip, buffer, UInt32(length))
                }

                // Update progress handler, only if progress is not 1, because
                // if we call it when progress == 1, the user will receive
                // a progress handler call with value 1.0 twice.
                if let progress, currentPosition / totalSize != 1 {
                    progress(currentPosition / totalSize)
                }

                progressTracker.completedUnitCount = Int64(currentPosition)

                zipCloseFileInZip(zip)
                free(buffer)
            }
        }
        zipClose(zip, nil)

        // Completed. Update progress handler.
        if let progress {
            progress(1.0)
        }

        progressTracker.completedUnitCount = Int64(totalSize)
    }

    // Keep throws in the public signature for compatibility with the upstream API.
    // swiftlint:disable unneeded_throws_rethrows
    /// Zip data in memory.
    ///
    /// - parameter archiveFiles:Array of Archive Files.
    /// - parameter zipFilePath: Destination NSURL, should lead to a .zip filepath.
    /// - parameter password:    Password string. Optional.
    /// - parameter compression: Compression strategy
    /// - parameter progress: A progress closure called after unzipping each file in the archive. Double value betweem 0
    /// and 1.
    ///
    /// - throws: Error if zipping fails.
    ///
    /// - notes: Supports implicit progress composition
    public class func zipData(
        archiveFiles: [ArchiveFile],
        zipFilePath: URL,
        password: String?,
        compression: ZipCompression = .DefaultCompression,
        progress: ((_ progress: Double) -> Void)?,
    )
        throws
    {
        let destinationPath: String = zipFilePath.path

        // Progress handler set up
        var currentPosition: Int = 0
        var totalSize: Int = 0

        for archiveFile in archiveFiles {
            totalSize += archiveFile.data.length
        }

        let progressTracker: Progress = .init(totalUnitCount: Int64(totalSize))
        progressTracker.isCancellable = false
        progressTracker.isPausable = false
        progressTracker.kind = ProgressKind.file

        // Begin Zipping
        let zip: zipFile? = zipOpen(destinationPath, APPEND_STATUS_CREATE)

        for archiveFile in archiveFiles {
            // Skip empty data
            if archiveFile.data.length == 0 {
                continue
            }

            // Setup the zip file info
            var zipInfo: zip_fileinfo = .init(
                tmz_date: tm_zip(tm_sec: 0, tm_min: 0, tm_hour: 0, tm_mday: 0, tm_mon: 0, tm_year: 0),
                dosDate: 0,
                internal_fa: 0,
                external_fa: 0,
            )

            if let modifiedTime = archiveFile.modifiedTime {
                let calendar: Calendar = .current
                zipInfo.tmz_date.tm_sec = UInt32(calendar.component(.second, from: modifiedTime))
                zipInfo.tmz_date.tm_min = UInt32(calendar.component(.minute, from: modifiedTime))
                zipInfo.tmz_date.tm_hour = UInt32(calendar.component(.hour, from: modifiedTime))
                zipInfo.tmz_date.tm_mday = UInt32(calendar.component(.day, from: modifiedTime))
                zipInfo.tmz_date.tm_mon = UInt32(calendar.component(.month, from: modifiedTime))
                zipInfo.tmz_date.tm_year = UInt32(calendar.component(.year, from: modifiedTime))
            }

            // Write the data as a file to zip
            zipOpenNewFileInZip3(
                zip,
                archiveFile.filename,
                &zipInfo,
                nil,
                0,
                nil,
                0,
                nil,
                Z_DEFLATED,
                compression.minizipCompression,
                0,
                -MAX_WBITS,
                DEF_MEM_LEVEL,
                Z_DEFAULT_STRATEGY,
                password,
                0,
            )
            zipWriteInFileInZip(zip, archiveFile.data.bytes, UInt32(archiveFile.data.length))
            zipCloseFileInZip(zip)

            // Update progress handler
            currentPosition += archiveFile.data.length

            if let progress {
                progress(Double(currentPosition / totalSize))
            }

            progressTracker.completedUnitCount = Int64(currentPosition)
        }

        zipClose(zip, nil)

        // Completed. Update progress handler.
        if let progress {
            progress(1.0)
        }

        progressTracker.completedUnitCount = Int64(totalSize)
    }

    // swiftlint:enable unneeded_throws_rethrows

    /// Check if file extension is invalid.
    ///
    /// - parameter fileExtension: A file extension.
    ///
    /// - returns: false if the extension is a valid file extension, otherwise true.
    class func fileExtensionIsInvalid(_ fileExtension: String?) -> Bool {
        guard let fileExtension else {
            return true
        }

        return !self.isValidFileExtension(fileExtension)
    }

    /// Add a file extension to the set of custom file extensions
    ///
    /// - parameter fileExtension: A file extension.
    public class func addCustomFileExtension(_ fileExtension: String) {
        self.customFileExtensions.withLock { extensions in
            _ = extensions.insert(fileExtension)
        }
    }

    /// Remove a file extension from the set of custom file extensions
    ///
    /// - parameter fileExtension: A file extension.
    public class func removeCustomFileExtension(_ fileExtension: String) {
        self.customFileExtensions.withLock { extensions in
            _ = extensions.remove(fileExtension)
        }
    }

    /// Check if a specific file extension is valid
    ///
    /// - parameter fileExtension: A file extension.
    ///
    /// - returns: true if the extension valid, otherwise false.
    public class func isValidFileExtension(_ fileExtension: String) -> Bool {
        self.customFileExtensions.withLock { extensions in
            let validFileExtensions: Set<String> = extensions.union(["zip", "cbz"])
            return validFileExtensions.contains(fileExtension)
        }
    }
}
