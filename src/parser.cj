/**
 * Source parser for Cangjie package: extracts package name, public functions, and public constructors.
 * Outputs a manifest (in-memory) for the code generator.
 * Parsing is line-based and pattern-based; handles a subset of Cangjie syntax.
 */
package pkgcli

import std.fs.*
import std.io.*
import std.collection.ArrayList

// Manifest: package name + list of commands (functions and constructors)
public class Manifest {
    public let packageQualifiedName: String
    public let commands: ArrayList<CommandInfo>

    public init(packageQualifiedName: String, commands: ArrayList<CommandInfo>) {
        this.packageQualifiedName = packageQualifiedName
        this.commands = commands
    }
}

// One command: either a top-level function or a constructor (ClassName new args)
public class CommandInfo {
    public let name: String
    public let isConstructor: Bool
    public let className: String  // if isConstructor, the class name
    public let params: ArrayList<ParamInfo>
    public let returnType: String  // simple type name; "Unit" or class name etc.
    public let returnIsRef: Bool   // true if return type is a class (store in object store)

    public init(name: String, isConstructor: Bool, className: String, params: ArrayList<ParamInfo>, returnType: String, returnIsRef: Bool) {
        this.name = name
        this.isConstructor = isConstructor
        this.className = className
        this.params = params
        this.returnType = returnType
        this.returnIsRef = returnIsRef
    }
}

public class ParamInfo {
    public let paramName: String
    public let paramType: String

    public init(paramName: String, paramType: String) {
        this.paramName = paramName
        this.paramType = paramType
    }
}

// Trim leading/trailing whitespace from a string
func trimSpace(s: String): String {
    s.trimStart(" \t\n\r").trimEnd(" \t\n\r")
}

// Check if type string looks like a reference type (class) for our purposes
func isRefType(typeStr: String): Bool {
    // Simple heuristic: not a primitive, not Unit, not Option<...> value part
    if (typeStr == "Unit" || typeStr == "Int64" || typeStr == "Int32" || typeStr == "Float64" || typeStr == "Float32" || typeStr == "Bool" || typeStr == "String") {
        return false
    }
    // Option<T> return: we don't store Option as ref; the inner T might be
    if (typeStr.startsWith("Option<")) {
        return false
    }
    // Assume class types are non-primitive identifiers (e.g. Student, Lesson)
    true
}

// Parse a single .cj file content; append commands to the list; return package name if found (else empty)
func parseFileContent(content: String, path: String, commands: ArrayList<CommandInfo>, packageName: ArrayList<String>, currentClass: ArrayList<String>): Unit {
    let lines: Array<String> = content.split("\n", removeEmpty: false)
    var i: Int64 = 0
    while (i < lines.size) {
        let line: String = trimSpace(lines[i])
        // package declaration
        if (line.startsWith("package ")) {
            let rest: String = trimSpace(line.removePrefix("package "))
            // take until comment or end of line (simplified: rest is the name, may have comment)
            let idx: Option<Int64> = rest.indexOf("//")
            let name: String = if (let Option<Int64>.Some(k) <- idx) { trimSpace(rest[0..k]) } else { rest }
            if (name.size > 0) {
                packageName.add(all: [name])
            }
        }
        // public func Name(
        if (line.startsWith("public func ")) {
            let rest: String = line.removePrefix("public func ")
            let openParen: Option<Int64> = rest.indexOf("(")
            if (let Option<Int64>.Some(op) <- openParen) {
                let funcName: String = trimSpace(rest[0..op])
                let afterParen: String = rest[(op + 1)..rest.size]
                let closeParen: Option<Int64> = afterParen.indexOf(")")
                if (let Option<Int64>.Some(cp) <- closeParen) {
                    let paramsStr: String = trimSpace(afterParen[0..cp])
                    let afterClose: String = trimSpace(afterParen[(cp + 1)..afterParen.size])
                    var returnType: String = "Unit"
                    if (afterClose.startsWith(":")) {
                        let typePart: String = trimSpace(afterClose.removePrefix(":"))
                        let endType: Option<Int64> = typePart.indexOf(" ")
                        let endType2: Option<Int64> = typePart.indexOf("{")
                        var endIdx: Int64 = typePart.size
                        if (let Option<Int64>.Some(e) <- endType) { endIdx = e }
                        if (let Option<Int64>.Some(e2) <- endType2) { if (e2 < endIdx) { endIdx = e2 } }
                        returnType = trimSpace(typePart[0..endIdx])
                    }
                    let params: ArrayList<ParamInfo> = ArrayList<ParamInfo>()
                    if (paramsStr.size > 0) {
                        let paramList: Array<String> = paramsStr.split(",", removeEmpty: false)
                        for (p in paramList) {
                            let pt: String = trimSpace(p)
                            let colon: Option<Int64> = pt.indexOf(":")
                            if (let Option<Int64>.Some(ci) <- colon) {
                                let pname: String = trimSpace(pt[0..ci])
                                let ptype: String = trimSpace(pt[(ci + 1)..pt.size])
                                params.add(all: [ParamInfo(pname, ptype)])
                            }
                        }
                    }
                    commands.add(all: [CommandInfo(funcName, false, "", params, returnType, isRefType(returnType))])
                }
            }
        }
        // public class ClassName
        if (line.startsWith("public class ")) {
            let rest: String = trimSpace(line.removePrefix("public class "))
            let spaceOrBrace: Option<Int64> = rest.indexOf(" ")
            let brace: Option<Int64> = rest.indexOf("{")
            var endIdx: Int64 = rest.size
            if (let Option<Int64>.Some(b) <- brace) { endIdx = b }
            if (let Option<Int64>.Some(s) <- spaceOrBrace) { if (s < endIdx) { endIdx = s } }
            let className: String = trimSpace(rest[0..endIdx])
            currentClass.clear()
            currentClass.add(all: [className])
        }
        // public init(
        if (line.startsWith("public init(")) {
            let rest: String = line.removePrefix("public init(")
            let closeParen: Option<Int64> = rest.indexOf(")")
            if (let Option<Int64>.Some(cp) <- closeParen) {
                let paramsStr: String = trimSpace(rest[0..cp])
                let params: ArrayList<ParamInfo> = ArrayList<ParamInfo>()
                if (paramsStr.size > 0) {
                    let paramList: Array<String> = paramsStr.split(",", removeEmpty: false)
                    for (p in paramList) {
                        let pt: String = trimSpace(p)
                        let colon: Option<Int64> = pt.indexOf(":")
                        if (let Option<Int64>.Some(ci) <- colon) {
                            let pname: String = trimSpace(pt[0..ci])
                            let ptype: String = trimSpace(pt[(ci + 1)..pt.size])
                            params.add(all: [ParamInfo(pname, ptype)])
                        }
                    }
                }
                let cname: String = if (currentClass.size > 0) { currentClass.get(0).getOrThrow() } else { "" }
                commands.add(all: [CommandInfo("init", true, cname, params, cname, true)])
            }
        }
        i++
    }
}

// Read file content as String
func readFileAsString(path: Path): Option<String> {
    try {
        let bytes: Array<Byte> = File.readFrom(path)
        let s: String = String.fromUtf8(bytes)
        return Option<String>.Some(s)
    } catch (_) {
        return Option<String>.None
    }
}

// Resolve directory to scan: if package root has src/ subdir, use it; else use path as-is.
func _resolveSourceDir(sourcePath: String): String {
    try {
        let entries: Array<FileInfo> = Directory.readFrom(sourcePath)
        for (entry in entries) {
            if (entry.path.fileName == "src" && entry.isDirectory()) {
                return sourcePath + "/src"
            }
        }
    } catch (_) { }
    sourcePath
}

// Parse package at given path (directory containing .cj files, or package root with src/); return manifest
public func parsePackage(sourcePath: String): Option<Manifest> {
    try {
        let scanDir: String = _resolveSourceDir(sourcePath)
        let entries: Array<FileInfo> = Directory.readFrom(scanDir)
        let packageName: ArrayList<String> = ArrayList<String>()
        let commands: ArrayList<CommandInfo> = ArrayList<CommandInfo>()
        let currentClass: ArrayList<String> = ArrayList<String>()

        for (entry in entries) {
            let path: Path = entry.path
            let name: String = path.fileName
            if (name.endsWith(".cj")) {
                if (!entry.isDirectory()) {
                    let contentOpt: Option<String> = readFileAsString(path)
                    if (let Option<String>.Some(content) <- contentOpt) {
                        parseFileContent(content, path.toString(), commands, packageName, currentClass)
                    }
                }
            }
        }

        let pkgName: String = if (packageName.size > 0) { packageName.get(0).getOrThrow() } else { "default" }
        return Option<Manifest>.Some(Manifest(pkgName, commands))
    } catch (_) {
        return Option<Manifest>.None
    }
}
