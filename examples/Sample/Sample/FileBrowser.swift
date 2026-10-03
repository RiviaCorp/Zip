//
//  FileBrowser.swift
//
//  Copyright © 2016 Rivia Corp s.r.o.
//

// The legacy sample uses a storyboard and does not generate asset symbols.
// swiftlint:disable prohibited_interface_builder prefer_asset_symbols object_literal

import UIKit
import Zip

final class FileBrowser: UIViewController, UITableViewDataSource, UITableViewDelegate {
    // IBOutlets
    @IBOutlet private var tableView: UITableView!
    @IBOutlet private var selectionCounter: UIBarButtonItem!
    @IBOutlet private var zipButton: UIBarButtonItem!
    @IBOutlet private var unzipButton: UIBarButtonItem!

    let fileManager: FileManager = .default

    var path: URL? = nil {
        didSet {
            self.updateFiles()
        }
    }

    var files: [String] = []

    var selectedFiles: [String] = []

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        if self.path == nil {
            let documentsURL: URL = self.fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0] as URL
            self.path = documentsURL
        }
        self.updateSelection()
    }

    // MARK: File manager

    func updateFiles() {
        if let path {
            var tempFiles: [String] = []
            do {
                self.title = path.lastPathComponent
                tempFiles = try self.fileManager.contentsOfDirectory(atPath: path.path)
            } catch {
                if path.path == "/System" {
                    tempFiles = ["Library"]
                }
                if path.path == "/Library" {
                    tempFiles = ["Preferences"]
                }
                if path.path == "/var" {
                    tempFiles = ["mobile"]
                }
                if path.path == "/usr" {
                    tempFiles = ["lib", "libexec", "bin"]
                }
            }
            self.files = tempFiles.sorted { $0 < $1 }
            self.tableView.reloadData()
        }
    }

    // MARK: UITableView Data Source and Delegate

    func numberOfSections(in _: UITableView) -> Int {
        1
    }

    func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        self.files.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cellIdentifier: String = "FileCell"
        var cell: UITableViewCell = .init(style: .subtitle, reuseIdentifier: cellIdentifier)
        if let reuseCell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier) {
            cell = reuseCell
        }
        guard let path else {
            return cell
        }

        cell.selectionStyle = .none
        let filePath: String = self.files[indexPath.row]
        let newPath: String = path.appendingPathComponent(filePath).path
        var isDirectory: ObjCBool = false
        self.fileManager.fileExists(atPath: newPath, isDirectory: &isDirectory)
        cell.textLabel?.text = self.files[indexPath.row]
        if isDirectory.boolValue {
            cell.imageView?.image = UIImage(named: "Folder")
        } else {
            cell.imageView?.image = UIImage(named: "File")
        }
        cell.backgroundColor = (self.selectedFiles.contains(filePath)) ? UIColor(white: 0.9, alpha: 1.0) : UIColor.white
        return cell
    }

    func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {
        let filePath: String = self.files[indexPath.row]
        if let index = selectedFiles.firstIndex(of: filePath), selectedFiles.contains(filePath) {
            self.selectedFiles.remove(at: index)
        } else {
            self.selectedFiles.append(filePath)
        }
        self.updateSelection()
    }

    func updateSelection() {
        self.tableView.reloadData()
        self.selectionCounter.title = "\(self.selectedFiles.count) Selected"

        self.zipButton.isEnabled = (!self.selectedFiles.isEmpty)
        if self.selectedFiles.count == 1 {
            let filePath: String? = self.selectedFiles.first
            let pathExtension: String = self.path!.appendingPathComponent(filePath!).pathExtension
            if pathExtension == "zip" {
                self.unzipButton.isEnabled = true
            } else {
                self.unzipButton.isEnabled = false
            }
        } else {
            self.unzipButton.isEnabled = false
        }
    }

    // MARK: Actions

    @IBAction
    private func unzipSelection(_: AnyObject) {
        let filePath: String? = self.selectedFiles.first
        let pathURL: URL = self.path!.appendingPathComponent(filePath!)
        do {
            _ = try Zip.quickUnzipFile(pathURL)
            self.selectedFiles.removeAll()
            self.updateSelection()
            self.updateFiles()
        } catch {
            print("ERROR")
        }
    }

    @IBAction
    private func zipSelection(_: AnyObject) {
        var urlPaths: [URL] = []
        for filePath in self.selectedFiles {
            urlPaths.append(self.path!.appendingPathComponent(filePath))
        }
        do {
            _ = try Zip.quickZipFiles(urlPaths, fileName: "Archive")
            self.selectedFiles.removeAll()
            self.updateSelection()
            self.updateFiles()
        } catch {
            print("ERROR")
        }
    }
}

// swiftlint:enable prohibited_interface_builder prefer_asset_symbols object_literal
