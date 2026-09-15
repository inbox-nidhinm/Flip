import SwiftUI
import AppKit

/// One drawing on the home screen.
struct Project: Identifiable, Equatable {
    let url: URL
    let modified: Date

    var id: URL { url }
    var name: String { url.deletingPathExtension().lastPathComponent }

    /// The folder it sits in, or nil at the top level. Folders *are* directories
    /// inside `Flip Creations` — nothing is tracked in a sidecar file, so moving
    /// a drawing in the Finder moves it here too, and the app has nothing to get
    /// out of step with.
    var folder: String? {
        let parent = url.deletingLastPathComponent()
        let root = AppModel.creationsFolder
        return parent.standardizedFileURL == root.standardizedFileURL
            ? nil : parent.lastPathComponent
    }
}

/// What the home screen shows: every drawing in `Flip Creations`, and the
/// folders they are filed under.
@MainActor
final class Library: ObservableObject {
    @Published private(set) var projects: [Project] = []
    @Published private(set) var folders: [String] = []
    /// Which folder is being shown. Nil means all of them at once, which is the
    /// view you want when you are looking for something rather than filing it.
    @Published var folder: String?
    @Published var note: String?

    private var thumbs: [URL: CGImage] = [:]

    var visible: [Project] {
        guard let folder else { return projects }
        return projects.filter { $0.folder == folder }
    }

    // MARK: Scanning

    func refresh() {
        let fm = FileManager.default
        let root = AppModel.creationsFolder
        guard let top = try? fm.contentsOfDirectory(at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]) else {
            projects = []; folders = []
            return
        }

        var found: [Project] = []
        var dirs: [String] = []
        for url in top {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                dirs.append(url.lastPathComponent)
                // One level deep only. A folder inside a folder is a filing
                // system, and this is a shelf.
                let inside = (try? fm.contentsOfDirectory(at: url,
                    includingPropertiesForKeys: [.contentModificationDateKey],
                    options: [.skipsHiddenFiles])) ?? []
                found += inside.compactMap(project)
            } else if let p = project(url) {
                found.append(p)
            }
        }
        // Most recently touched first: the thing you were last working on is the
        // thing you are most likely coming back for.
        projects = found.sorted { $0.modified > $1.modified }
        folders = dirs.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        if let folder, !folders.contains(folder) { self.folder = nil }
    }

    private func project(_ url: URL) -> Project? {
        guard url.pathExtension == "flip" else { return nil }
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast
        return Project(url: url, modified: date)
    }

    // MARK: Thumbnails

    /// Rendered from the file's first frame, off the main actor — reading and
    /// rasterising every drawing in the folder is far too much to do while the
    /// window is trying to appear. Cached by URL, and dropped when the file
    /// changes underneath it.
    func thumbnail(for p: Project) async -> CGImage? {
        if let hit = thumbs[p.url] { return hit }
        let url = p.url
        let image = await Task.detached(priority: .utility) {
            Library.render(url)
        }.value
        if let image { thumbs[p.url] = image }
        return image
    }

    nonisolated private static func render(_ url: URL) -> CGImage? {
        guard let data = try? Data(contentsOf: url),
              let doc = try? JSONDecoder().decode(Document.self, from: data),
              let first = doc.frames.first else { return nil }
        return Render.image(of: first, doc: doc, height: 240)
    }

    private func forget(_ url: URL) { thumbs[url] = nil }

    // MARK: Filing

    func rename(_ p: Project, to raw: String) {
        // Same scrubbing the document title takes: `/` is the path separator and
        // `:` is what the Finder shows in its place.
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        guard !name.isEmpty, name != p.name else { return }
        let target = p.url.deletingLastPathComponent()
            .appendingPathComponent(name).appendingPathExtension("flip")
        move(p, to: target, failure: "Could not rename \(p.name)")
    }

    /// To the Trash, not deleted. A drawing is the only copy of itself and this
    /// is one menu item away from a right click.
    func delete(_ p: Project) {
        do {
            try FileManager.default.trashItem(at: p.url, resultingItemURL: nil)
            forget(p.url)
            refresh()
        } catch {
            note = "Could not move \(p.name) to the Trash"
        }
    }

    func move(_ p: Project, toFolder folder: String?) {
        let root = AppModel.creationsFolder
        let dir = folder.map { root.appendingPathComponent($0, isDirectory: true) } ?? root
        guard dir.standardizedFileURL != p.url.deletingLastPathComponent().standardizedFileURL else { return }
        move(p, to: dir.appendingPathComponent(p.url.lastPathComponent),
             failure: "Could not move \(p.name)")
    }

    private func move(_ p: Project, to target: URL, failure: String) {
        guard !FileManager.default.fileExists(atPath: target.path) else {
            note = "There is already something called \(target.deletingPathExtension().lastPathComponent) there"
            return
        }
        do {
            try FileManager.default.moveItem(at: p.url, to: target)
            // The thumbnail is keyed on the URL, and the URL has just changed.
            forget(p.url)
            thumbs[target] = nil
            refresh()
        } catch {
            note = failure
        }
    }

    /// How many drawings a folder holds. Read when its menu opens, so a folder
    /// about to be trashed can say what is going with it.
    func count(inFolder name: String) -> Int {
        projects.filter { $0.folder == name }.count
    }

    /// To the Trash, with everything filed under it.
    ///
    /// A folder here *is* a directory, so this is the directory going — and the
    /// drawings inside it are the only copies of themselves, which is why it
    /// goes the way a drawing does rather than being deleted outright. The
    /// count is in the menu item rather than behind a confirmation sheet: the
    /// number is the warning, and the Trash is the undo.
    func deleteFolder(_ name: String) {
        let dir = AppModel.creationsFolder.appendingPathComponent(name, isDirectory: true)
        do {
            try FileManager.default.trashItem(at: dir, resultingItemURL: nil)
            // The thumbnails are keyed on URLs that have just stopped existing.
            for p in projects where p.folder == name { forget(p.url) }
            // `refresh` clears this on its own when the folder is gone, but
            // doing it here means the shelf never draws a frame filtered to a
            // folder that is not there.
            if folder == name { folder = nil }
            refresh()
        } catch {
            note = "Could not move the folder \(name) to the Trash"
        }
    }

    @discardableResult
    func newFolder(named raw: String) -> Bool {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        guard !name.isEmpty else { return false }
        let dir = AppModel.creationsFolder.appendingPathComponent(name, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            refresh()
            folder = name
            return true
        } catch {
            note = "Could not make the folder \(name)"
            return false
        }
    }
}
