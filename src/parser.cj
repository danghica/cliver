/**
 * Source parser for Cangjie package: extracts package name, public functions, and public constructors.
 * Uses std.ast (cangjieLex, parseProgram) for parsing; outputs a manifest for the code generator.
 */
package pkgcli

import std.fs.*
import std.collection.ArrayList
import std.ast.*

// Result of parsing a package: either success (manifest present) or failure (errorMessage set).
public class ParseOutcome {
    public let manifest: Option<Manifest>
    public let errorMessage: String

    public init(manifest: Option<Manifest>, errorMessage: String) {
        this.manifest = manifest
        this.errorMessage = errorMessage
    }
}

// Manifest: package name + list of commands (functions and constructors)
public class Manifest {
    public let packageQualifiedName: String
    public let commands: ArrayList<CommandInfo>

    public init(packageQualifiedName: String, commands: ArrayList<CommandInfo>) {
        this.packageQualifiedName = packageQualifiedName
        this.commands = commands
    }
}

// One command: top-level function, constructor (ClassName new args), or class method (instance or static)
public class CommandInfo {
    public let name: String
    public let isConstructor: Bool
    public let className: String  // if isConstructor or class method, the class name
    public let params: ArrayList<ParamInfo>
    public let returnType: String  // simple type name; "Unit" or class name etc.
    public let returnIsRef: Bool   // true if return type is a class (store in object store)
    public let isInstanceMethod: Bool  // true for non-static instance methods (needs THIS)
    public let isStaticMethod: Bool    // true for static methods (no THIS)
    public let packagePath: String     // CLI directory path: "/" for root, or e.g. "demo_sub"

    public init(name: String, isConstructor: Bool, className: String, params: ArrayList<ParamInfo>, returnType: String, returnIsRef: Bool, isInstanceMethod: Bool, isStaticMethod: Bool, packagePath: String) {
        this.name = name
        this.isConstructor = isConstructor
        this.className = className
        this.params = params
        this.returnType = returnType
        this.returnIsRef = returnIsRef
        this.isInstanceMethod = isInstanceMethod
        this.isStaticMethod = isStaticMethod
        this.packagePath = packagePath
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

// Check if type string looks like a reference type (class) for our purposes
func isRefType(typeStr: String): Bool {
    if (typeStr == "Unit" || typeStr == "Int64" || typeStr == "Int32" || typeStr == "Float64" || typeStr == "Float32" || typeStr == "Bool" || typeStr == "String") {
        return false
    }
    if (typeStr.startsWith("Option<")) {
        return false
    }
    true
}

// Return true if decl has public modifier
func isPublic(decl: Decl): Bool {
    var i: Int64 = 0
    while (i < decl.modifiers.size) {
        let m: Modifier = decl.modifiers.get(i).getOrThrow()
        if (m.keyword.value == "public") {
            return true
        }
        i++
    }
    false
}

// Return true if decl has static modifier
func isStatic(decl: Decl): Bool {
    var i: Int64 = 0
    while (i < decl.modifiers.size) {
        let m: Modifier = decl.modifiers.get(i).getOrThrow()
        if (m.keyword.value == "static") {
            return true
        }
        i++
    }
    false
}

// Character codes for identifier check (a-z, A-Z, _)
let _CODE_LOWER_A: Int64 = 97
let _CODE_LOWER_Z: Int64 = 122
let _CODE_UPPER_A: Int64 = 65
let _CODE_UPPER_Z: Int64 = 90
let _CODE_UNDERSCORE: Int64 = 95

// Return true if name is an operator (e.g. ==, +); such methods are not exposed as CLI commands
func isOperatorMethodName(name: String): Bool {
    if (name.size < 1) { return true }
    let first: Byte = name.get(0).getOrThrow()
    let code: Int64 = Int64(first)
    if ((code >= _CODE_LOWER_A && code <= _CODE_LOWER_Z) || (code >= _CODE_UPPER_A && code <= _CODE_UPPER_Z) || code == _CODE_UNDERSCORE) { return false }
    true
}

// Build package name string from PackageHeader (e.g. "a.b.c" or "lesson_demo")
func packageNameFromHeader(header: PackageHeader): String {
    let raw: String = header.toTokens().toString()
    if (raw.startsWith("package ")) {
        return raw.removePrefix("package ").trimStart(" \t").trimEnd(" \t")
    }
    raw
}

// Extract return type string from FuncDecl; "Unit" if missing or on error
func getReturnTypeStr(fd: FuncDecl): String {
    try {
        fd.declType.toTokens().toString()
    } catch (_) {
        "Unit"
    }
}

// Build ParamInfo list from FuncDecl.funcParams
func getParamList(fd: FuncDecl): ArrayList<ParamInfo> {
    let list: ArrayList<ParamInfo> = ArrayList<ParamInfo>()
    var i: Int64 = 0
    while (i < fd.funcParams.size) {
        let fp: FuncParam = fd.funcParams.get(i).getOrThrow()
        let pname: String = fp.identifier.value
        let ptype: String = fp.paramType.toTokens().toString()
        list.add(all: [ParamInfo(pname, ptype)])
        i++
    }
    list
}

// Collect one decl from class body: public init, or public instance/static func
func collectClassBodyDecl(className: String, decl: Decl, commands: ArrayList<CommandInfo>, packagePath: String): Unit {
    match (decl) {
        case fd: FuncDecl =>
            if (fd.keyword.kind == TokenKind.INIT && isPublic(fd)) {
                let params: ArrayList<ParamInfo> = getParamList(fd)
                commands.add(all: [CommandInfo("init", true, className, params, className, true, false, false, packagePath)])
            } else if (fd.keyword.kind == TokenKind.FUNC && isPublic(fd) && !isOperatorMethodName(fd.identifier.value)) {
                let returnType: String = getReturnTypeStr(fd)
                let methodParams: ArrayList<ParamInfo> = getParamList(fd)
                if (isStatic(fd)) {
                    commands.add(all: [CommandInfo(fd.identifier.value, false, className, methodParams, returnType, isRefType(returnType), false, true, packagePath)])
                } else {
                    let paramsWithThis: ArrayList<ParamInfo> = ArrayList<ParamInfo>()
                    paramsWithThis.add(all: [ParamInfo("this", className)])
                    var mi: Int64 = 0
                    while (mi < methodParams.size) {
                        paramsWithThis.add(all: [methodParams.get(mi).getOrThrow()])
                        mi++
                    }
                    commands.add(all: [CommandInfo(fd.identifier.value, false, className, paramsWithThis, returnType, isRefType(returnType), true, false, packagePath)])
                }
            }
        case _ => ()
    }
}

// Collect public init commands from a class body into commands list
func collectPublicInits(className: String, body: Body, commands: ArrayList<CommandInfo>, packagePath: String): Unit {
    var i: Int64 = 0
    while (i < body.decls.size) {
        collectClassBodyDecl(className, body.decls.get(i).getOrThrow(), commands, packagePath)
        i++
    }
}

// Process one parsed Program: mutates packageName (first file at root sets it) and appends to commands.
// Contract: first file with packagePath == "/" and non-empty package declaration sets package name; order is from collectCjFilesUnder (sorted paths).
func processProgram(program: Program, packageName: ArrayList<String>, commands: ArrayList<CommandInfo>, packagePath: String): Unit {
    let header: PackageHeader = program.packageHeader
    let pkgStr: String = packageNameFromHeader(header)
    if (pkgStr.size > 0 && packageName.size == 0 && packagePath == rootPackagePath) {
        packageName.add(all: [pkgStr])
    }
    var i: Int64 = 0
    while (i < program.decls.size) {
        collectTopLevelDecl(program.decls.get(i).getOrThrow(), commands, packagePath)
        i++
    }
}

// Handle one top-level decl: add public class inits or public func to commands
func collectTopLevelDecl(decl: Decl, commands: ArrayList<CommandInfo>, packagePath: String): Unit {
    match (decl) {
        case cd: ClassDecl =>
            if (isPublic(cd)) {
                collectPublicInits(cd.identifier.value, cd.body, commands, packagePath)
            }
        case fd: FuncDecl =>
            if (isPublic(fd) && fd.keyword.kind == TokenKind.FUNC) {
                let params: ArrayList<ParamInfo> = getParamList(fd)
                let returnType: String = getReturnTypeStr(fd)
                commands.add(all: [CommandInfo(fd.identifier.value, false, "", params, returnType, isRefType(returnType), false, false, packagePath)])
            }
        case _ => ()
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
// Relies on std.fs FileInfo.path.fileName being the directory entry name (e.g. "src").
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

// Parse package at given path (directory containing .cj files, or package root with src/).
// Returns ParseOutcome with manifest on success, or errorMessage on failure (invalid path, read error, or parse failure).
public func parsePackage(sourcePath: String): ParseOutcome {
    try {
        let scanDir: String = _resolveSourceDir(sourcePath)
        let cjPaths: ArrayList<Path> = collectCjFilesUnder(scanDir)
        let packageName: ArrayList<String> = ArrayList<String>()
        let commands: ArrayList<CommandInfo> = ArrayList<CommandInfo>()

        var fi: Int64 = 0
        while (fi < cjPaths.size) {
            let path: Path = cjPaths.get(fi).getOrThrow()
            let pkgPath: String = packagePathFromFile(path, scanDir)
            let contentOpt: Option<String> = readFileAsString(path)
            if (let Option<String>.Some(content) <- contentOpt) {
                try {
                    let tokens: Tokens = cangjieLex(content)
                    let program: Program = parseProgram(tokens)
                    processProgram(program, packageName, commands, pkgPath)
                } catch (_) {
                    return ParseOutcome(Option<Manifest>.None, "failed to parse file: " + path.toString())
                }
            }
            fi++
        }

        let pkgName: String = if (packageName.size > 0) { packageName.get(0).getOrThrow() } else { "default" }
        return ParseOutcome(Option<Manifest>.Some(Manifest(pkgName, commands)), "")
    } catch (_) {
        return ParseOutcome(Option<Manifest>.None, "invalid package path or cannot read directory: " + sourcePath)
    }
}
