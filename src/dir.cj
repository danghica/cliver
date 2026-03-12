/**
 * Directory structure module for Clive: recursive .cj collection,
 * package path derivation from file path, path normalization, known-path set.
 * Used by parser and codegen so path logic lives in one place.
 *
 * Public helpers normalizePath and isKnownPackagePath are the single source of truth
 * for Clive (parser, tests). The generated driver inlines its own _normalizePath so
 * the executable stays self-contained; behavior is intended to match this module.
 */
package pkgcli

import std.fs.*
import std.collection.ArrayList
import std.core.StringBuilder

// Root package path is always "/"
public let rootPackagePath: String = "/"

// Character code for path segment separator (used in _splitPathSegments).
let _CHAR_SLASH: Int64 = 47

// Recursively collect all .cj file paths under scanDir (excluding cli_driver.cj).
// Returns paths in stable sorted order (by path string).
public func collectCjFilesUnder(scanDir: String): ArrayList<Path> {
    let raw: ArrayList<Path> = _collectCjFilesRec(scanDir, scanDir)
    _sortPathsByString(raw)
    raw
}

func _collectCjFilesRec(scanDir: String, currentDir: String): ArrayList<Path> {
    let result: ArrayList<Path> = ArrayList<Path>()
    try {
        let entries: Array<FileInfo> = Directory.readFrom(currentDir)
        var i: Int64 = 0
        while (i < entries.size) {
            let entry: FileInfo = entries[i]
            let name: String = entry.name
            if (entry.isDirectory()) {
                if (name != "." && name != "..") {
                    let subPath: String = currentDir + "/" + name
                    let subList: ArrayList<Path> = _collectCjFilesRec(scanDir, subPath)
                    var j: Int64 = 0
                    while (j < subList.size) {
                        result.add(all: [subList.get(j).getOrThrow()])
                        j++
                    }
                }
            } else {
                if (name.endsWith(".cj") && name != "cli_driver.cj") {
                    result.add(all: [Path(currentDir + "/" + name)])
                }
            }
            i++
        }
    } catch (_) { }
    result
}

func _sortPathsByString(list: ArrayList<Path>): Unit {
    var i: Int64 = 1
    while (i < list.size) {
        let p: Path = list.get(i).getOrThrow()
        let ps: String = p.toString()
        var j: Int64 = i - 1
        while (j >= 0) {
            let q: Path = list.get(j).getOrThrow()
            if (q.toString() <= ps) { break }
            list[j + 1] = q
            j--
        }
        list[j + 1] = p
        i++
    }
}

// Strip trailing slash for consistent path comparison (avoids "/a/b" vs "/a/b/" mismatch).
func _normalizePathForComparison(p: String): String {
    if (p.size > 1 && p.endsWith("/")) {
        p.removeSuffix("/")
    } else {
        p
    }
}

// Compute packagePath for a file: "/" if file is directly under scanDir, else relative dir (e.g. "demo_sub").
// Paths are compared after normalizing (trailing slash stripped) so logical equality is consistent.
public func packagePathFromFile(filePath: Path, scanDir: String): String {
    let parentPath: Path = filePath.parent
    let parentStr: String = parentPath.toString()
    let scanNorm: String = _normalizePathForComparison(scanDir)
    let parentNorm: String = _normalizePathForComparison(parentStr)
    if (parentStr.size == 0 || parentNorm == scanNorm) {
        rootPackagePath
    } else {
        let suffix: String = parentStr.removePrefix(scanDir)
        let stripped: String = if (suffix.startsWith("/")) { suffix.removePrefix("/") } else { suffix }
        stripped
    }
}

// Normalize a path token relative to cwd. Root is "/". Returns Option.Some(normalized) or None if path escapes root.
public func normalizePath(pathToken: String, cwd: String): Option<String> {
    let segments: ArrayList<String> = _splitPathSegments(pathToken)
    if (segments.size == 0) { return Option<String>.Some(cwd) }
    let fromRoot: Bool = pathToken.startsWith("/")
    var segList: ArrayList<String> = ArrayList<String>()
    if (fromRoot) {
        var i: Int64 = 0
        while (i < segments.size) {
            let s: String = segments.get(i).getOrThrow()
            if (s == ".") { }
            else if (s == "..") {
                if (segList.size > 0) {
                    // ArrayList has no pop; rebuild without last element (intended pattern in this codebase).
                    let newList: ArrayList<String> = ArrayList<String>()
                    var idx: Int64 = 0
                    while (idx < segList.size - 1) {
                        newList.add(all: [segList.get(idx).getOrThrow()])
                        idx++
                    }
                    segList = newList
                } else { return Option<String>.None }
            } else if (s.size > 0) {
                segList.add(all: [s])
            }
            i++
        }
        if (segList.size == 0) { return Option<String>.Some(rootPackagePath) }
        var joined: String = segList.get(0).getOrThrow()
        var j: Int64 = 1
        while (j < segList.size) {
            joined = joined + "/" + segList.get(j).getOrThrow()
            j++
        }
        return Option<String>.Some(joined)
    } else {
        var baseSegs: ArrayList<String> = ArrayList<String>()
        if (cwd != rootPackagePath && cwd.size > 0) {
            let cwdSegs: ArrayList<String> = _splitPathSegments(cwd)
            var ci: Int64 = 0
            while (ci < cwdSegs.size) {
                baseSegs.add(all: [cwdSegs.get(ci).getOrThrow()])
                ci++
            }
        }
        var i: Int64 = 0
        while (i < segments.size) {
            let s: String = segments.get(i).getOrThrow()
            if (s == ".") { }
            else if (s == "..") {
                if (baseSegs.size > 0) {
                    // ArrayList has no pop; rebuild without last element (intended pattern in this codebase).
                    let newBase: ArrayList<String> = ArrayList<String>()
                    var idx: Int64 = 0
                    while (idx < baseSegs.size - 1) {
                        newBase.add(all: [baseSegs.get(idx).getOrThrow()])
                        idx++
                    }
                    baseSegs = newBase
                } else { return Option<String>.None }
            } else if (s.size > 0) {
                baseSegs.add(all: [s])
            }
            i++
        }
        if (baseSegs.size == 0) { return Option<String>.Some(rootPackagePath) }
        var joined: String = baseSegs.get(0).getOrThrow()
        var j: Int64 = 1
        while (j < baseSegs.size) {
            joined = joined + "/" + baseSegs.get(j).getOrThrow()
            j++
        }
        return Option<String>.Some(joined)
    }
}

func _substring(s: String, start: Int64, end: Int64): String {
    let sb: StringBuilder = StringBuilder()
    var i: Int64 = start
    while (i < end && i < s.size) {
        sb.append(Rune(UInt32(s.get(i).getOrThrow())))
        i++
    }
    sb.toString()
}

func _splitPathSegments(pathStr: String): ArrayList<String> {
    let result: ArrayList<String> = ArrayList<String>()
    var start: Int64 = 0
    var i: Int64 = 0
    while (i <= pathStr.size) {
        if (i == pathStr.size || (Int64(pathStr.get(i).getOrThrow()) == _CHAR_SLASH)) {
            if (i > start) {
                result.add(all: [_substring(pathStr, start, i)])
            }
            start = i + 1
        }
        i++
    }
    if (start < pathStr.size) {
        result.add(all: [_substring(pathStr, start, pathStr.size)])
    }
    result
}

// Check if path is in knownPaths or is a prefix of any known path (for cd to intermediate dirs).
public func isKnownPackagePath(path: String, knownPaths: ArrayList<String>): Bool {
    if (path == rootPackagePath) { return true }
    var i: Int64 = 0
    while (i < knownPaths.size) {
        let k: String = knownPaths.get(i).getOrThrow()
        if (k == path) { return true }
        if (k.startsWith(path + "/")) { return true }
        i++
    }
    false
}
