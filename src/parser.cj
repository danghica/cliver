/**
 * Source parser for Cangjie package: extracts package name, public functions, and public constructors.
 * Uses std.ast (cangjieLex, parseProgram) for parsing; outputs a manifest for the code generator.
 */
package pkgcli

import std.fs.*
import std.collection.ArrayList
import std.ast.*

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

    public init(name: String, isConstructor: Bool, className: String, params: ArrayList<ParamInfo>, returnType: String, returnIsRef: Bool, isInstanceMethod: Bool, isStaticMethod: Bool) {
        this.name = name
        this.isConstructor = isConstructor
        this.className = className
        this.params = params
        this.returnType = returnType
        this.returnIsRef = returnIsRef
        this.isInstanceMethod = isInstanceMethod
        this.isStaticMethod = isStaticMethod
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

// Return true if name is an operator (e.g. ==, +); such methods are not exposed as CLI commands
func isOperatorMethodName(name: String): Bool {
    if (name.size < 1) { return true }
    let first: Byte = name.get(0).getOrThrow()
    let code: Int64 = Int64(first)
    if ((code >= 97 && code <= 122) || (code >= 65 && code <= 90) || code == 95) { return false }
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
func collectClassBodyDecl(className: String, decl: Decl, commands: ArrayList<CommandInfo>): Unit {
    match (decl) {
        case fd: FuncDecl =>
            if (fd.keyword.kind == TokenKind.INIT && isPublic(fd)) {
                let params: ArrayList<ParamInfo> = getParamList(fd)
                commands.add(all: [CommandInfo("init", true, className, params, className, true, false, false)])
            } else if (fd.keyword.kind == TokenKind.FUNC && isPublic(fd) && !isOperatorMethodName(fd.identifier.value)) {
                let returnType: String = getReturnTypeStr(fd)
                let methodParams: ArrayList<ParamInfo> = getParamList(fd)
                if (isStatic(fd)) {
                    commands.add(all: [CommandInfo(fd.identifier.value, false, className, methodParams, returnType, isRefType(returnType), false, true)])
                } else {
                    let paramsWithThis: ArrayList<ParamInfo> = ArrayList<ParamInfo>()
                    paramsWithThis.add(all: [ParamInfo("this", className)])
                    var mi: Int64 = 0
                    while (mi < methodParams.size) {
                        paramsWithThis.add(all: [methodParams.get(mi).getOrThrow()])
                        mi++
                    }
                    commands.add(all: [CommandInfo(fd.identifier.value, false, className, paramsWithThis, returnType, isRefType(returnType), true, false)])
                }
            }
        case _ => ()
    }
}

// Collect public init commands from a class body into commands list
func collectPublicInits(className: String, body: Body, commands: ArrayList<CommandInfo>): Unit {
    var i: Int64 = 0
    while (i < body.decls.size) {
        collectClassBodyDecl(className, body.decls.get(i).getOrThrow(), commands)
        i++
    }
}

// Process one parsed Program: update packageName (if not set), append public commands
func processProgram(program: Program, packageName: ArrayList<String>, commands: ArrayList<CommandInfo>): Unit {
    let header: PackageHeader = program.packageHeader
    let pkgStr: String = packageNameFromHeader(header)
    if (pkgStr.size > 0 && packageName.size == 0) {
        packageName.add(all: [pkgStr])
    }
    var i: Int64 = 0
    while (i < program.decls.size) {
        collectTopLevelDecl(program.decls.get(i).getOrThrow(), commands)
        i++
    }
}

// Handle one top-level decl: add public class inits or public func to commands
func collectTopLevelDecl(decl: Decl, commands: ArrayList<CommandInfo>): Unit {
    match (decl) {
        case cd: ClassDecl =>
            if (isPublic(cd)) {
                collectPublicInits(cd.identifier.value, cd.body, commands)
            }
        case fd: FuncDecl =>
            if (isPublic(fd) && fd.keyword.kind == TokenKind.FUNC) {
                let params: ArrayList<ParamInfo> = getParamList(fd)
                let returnType: String = getReturnTypeStr(fd)
                commands.add(all: [CommandInfo(fd.identifier.value, false, "", params, returnType, isRefType(returnType), false, false)])
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

        for (entry in entries) {
            let path: Path = entry.path
            let name: String = path.fileName
            if (name == "cli_driver.cj") { continue }
            if (name.endsWith(".cj") && !entry.isDirectory()) {
                let contentOpt: Option<String> = readFileAsString(path)
                if (let Option<String>.Some(content) <- contentOpt) {
                    let tokens: Tokens = cangjieLex(content)
                    let program: Program = parseProgram(tokens)
                    processProgram(program, packageName, commands)
                }
            }
        }

        let pkgName: String = if (packageName.size > 0) { packageName.get(0).getOrThrow() } else { "default" }
        return Option<Manifest>.Some(Manifest(pkgName, commands))
    } catch (_) {
        return Option<Manifest>.None
    }
}
