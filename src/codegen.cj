/**
 * Code generator: from a Manifest, emits Cangjie source for the CLI driver.
 * The driver imports the target package (same package when emitted into package src),
 * uses object store (monotonic id, HashMap<Int64, Any>), parses CLI args,
 * and dispatches to explicit calls with first-matching overload resolution.
 */
package pkgcli

import std.collection.ArrayList
import std.collection.HashMap
import std.core.StringBuilder

// Generate full CLI driver source from manifest. Target package is the package being wrapped;
// the generated file is intended to be placed in that package's src/ (same module, no import of package).
public func generateDriver(manifest: Manifest): String {
    let sb: StringBuilder = StringBuilder()
    let pkg: String = manifest.packageQualifiedName

    // Prologue: no import of target package (driver lives in same package)
    sb.append("// Generated CLI driver for package ")
    sb.append(pkg)
    sb.append("\n")
    sb.append("// Do not edit by hand.\n\n")
    sb.append("import std.env.*\n")
    sb.append("import std.io.*\n")
    sb.append("import std.collection.*\n")
    sb.append("import std.convert.*\n\n")

    // Object store and helpers
    sb.append("var _nextId: Int64 = 1\n")
    sb.append("var _store: HashMap<Int64, Any> = HashMap<Int64, Any>()\n\n")
    sb.append("func _storeRef(obj: Any): Int64 {\n")
    sb.append("    let id = _nextId\n")
    sb.append("    _nextId++\n")
    sb.append("    _store.add(id, obj)\n")
    sb.append("    id\n")
    sb.append("}\n\n")
    sb.append("func _getRef(id: Int64): Option<Any> {\n")
    sb.append("    _store.get(id)\n")
    sb.append("}\n\n")
    sb.append("func _parseRefId(s: String): Option<Int64> {\n")
    sb.append("    if (s.startsWith(\"ref:\")) { Int64.tryParse(s.removePrefix(\"ref:\")) } else { Option<Int64>.None }\n")
    sb.append("}\n\n")

    // Group commands by CLI key (class name for constructor, function name for function)
    let keys: ArrayList<String> = ArrayList<String>()
    let overloadsList: ArrayList<ArrayList<CommandInfo>> = ArrayList<ArrayList<CommandInfo>>()
    var i: Int64 = 0
    while (i < manifest.commands.size) {
        let cmd: CommandInfo = manifest.commands.get(i).getOrThrow()
        let key: String = if (cmd.isConstructor) { cmd.className } else { cmd.name }
        var found: Bool = false
        var j: Int64 = 0
        while (j < keys.size) {
            if (keys.get(j).getOrThrow() == key) {
                overloadsList.get(j).getOrThrow().add(all: [cmd])
                found = true
                break
            }
            j++
        }
        if (!found) {
            keys.add(all: [key])
            let list: ArrayList<CommandInfo> = ArrayList<CommandInfo>()
            list.add(all: [cmd])
            overloadsList.add(all: [list])
        }
        i++
    }

    // Emit main(): get args, dispatch by command
    sb.append("main(): Int64 {\n")
    sb.append("    let allArgs: Array<String> = getCommandLine()\n")
    sb.append("    if (allArgs.size < 1) {\n")
    sb.append("        eprintln(\"Usage: <command> [args...]  Use 'help' for commands.\")\n")
    sb.append("        return 64\n")
    sb.append("    }\n")
    sb.append("    let command: String = allArgs[0]\n")
    sb.append("    var argsList: ArrayList<String> = ArrayList<String>()\n")
    sb.append("    for (idx in 1..allArgs.size) { argsList.add(all: [allArgs[idx]]) }\n")
    sb.append("    if (command == \"help\") {\n")
    sb.append("        _printHelp()\n")
    sb.append("        return 0\n")
    sb.append("    }\n")

    // Dispatch: for each key, one block
    var k: Int64 = 0
    while (k < keys.size) {
        let key: String = keys.get(k).getOrThrow()
        let overloads: ArrayList<CommandInfo> = overloadsList.get(k).getOrThrow()
        sb.append("    if (command == \"")
        sb.append(key)
        sb.append("\") {\n")
        sb.append("        return _run")
        _appendSafeName(sb, key)
        sb.append("(argsList)\n")
        sb.append("    }\n")
        k++
    }

    sb.append("    eprintln(\"Unknown command: \" + command)\n")
    sb.append("    return 64\n")
    sb.append("}\n\n")

    // Helper: print help from manifest
    sb.append("func _printHelp(): Unit {\n")
    sb.append("    println(\"Commands:\")\n")
    k = 0
    while (k < keys.size) {
        let key: String = keys.get(k).getOrThrow()
        let overloads: ArrayList<CommandInfo> = overloadsList.get(k).getOrThrow()
        let cmd0: CommandInfo = overloads.get(0).getOrThrow()
        if (cmd0.isConstructor) {
            sb.append("  ")
            sb.append(key)
            sb.append(" new [args...]  (constructor)\n")
        } else {
            sb.append("  ")
            sb.append(key)
            sb.append(" [args...]\n")
        }
        k++
    }
    sb.append("}\n\n")

    // Emit _runKey for each key (tries overloads in order)
    k = 0
    while (k < keys.size) {
        let key: String = keys.get(k).getOrThrow()
        let overloads: ArrayList<CommandInfo> = overloadsList.get(k).getOrThrow()
        _emitRunCommand(sb, key, overloads)
        k++
    }

    sb.toString()
}

func _appendSafeName(sb: StringBuilder, name: String): Unit {
    var i: Int64 = 0
    while (i < name.size) {
        let c: Byte = name.get(i).getOrThrow()
        let code: Int64 = Int64(c)
        if ((code >= 97 && code <= 122) || (code >= 65 && code <= 90) || (code >= 48 && code <= 57) || code == 95) {
            sb.append(Rune(UInt32(code)))
        } else if (code == 46) {
            sb.append(Rune(UInt32(95)))
        }
        i++
    }
}

func _emitRunCommand(sb: StringBuilder, key: String, overloads: ArrayList<CommandInfo>): Unit {
    sb.append("func _run")
    _appendSafeName(sb, key)
    sb.append("(args: ArrayList<String>): Int64 {\n")

    let needNew: Bool = overloads.get(0).getOrThrow().isConstructor
    if (needNew) {
        sb.append("    if (args.size < 1 || args.get(0).getOrThrow() != \"new\") {\n")
        sb.append("        eprintln(\"Usage: ")
        sb.append(key)
        sb.append(" new [args...]\")\n")
        sb.append("        return 64\n")
        sb.append("    }\n")
        sb.append("    var actualArgs: ArrayList<String> = ArrayList<String>()\n")
        sb.append("    for (idx in 1..args.size) { actualArgs.add(all: [args.get(idx).getOrThrow()]) }\n")
    }

    var ov: Int64 = 0
    while (ov < overloads.size) {
        let cmd: CommandInfo = overloads.get(ov).getOrThrow()
        let argsVar: String = if (needNew) { "actualArgs" } else { "args" }
        _emitOverload(sb, cmd, argsVar, needNew)
        ov++
    }

    sb.append("    eprintln(\"No matching overload for ")
    sb.append(key)
    sb.append("\")\n")
    sb.append("    return 64\n")
    sb.append("}\n\n")
}

func _emitOverload(sb: StringBuilder, cmd: CommandInfo, argsVar: String, isConstructor: Bool): Unit {
    let n: Int64 = cmd.params.size
    sb.append("    if (")
    sb.append(argsVar)
    sb.append(".size >= ")
    sb.append(n)
    sb.append(") {\n")
    _emitConvertAndCall(sb, cmd, argsVar, isConstructor, 0, n, "        ")
    sb.append("    }\n")
}

func _emitConvertAndCall(sb: StringBuilder, cmd: CommandInfo, argsVar: String, isConstructor: Bool, index: Int64, n: Int64, indent: String): Unit {
    if (index >= n) {
        sb.append(indent)
        _emitCall(sb, cmd, isConstructor, n)
        sb.append("\n")
        return
    }
    let p: ParamInfo = cmd.params.get(index).getOrThrow()
    let convVar: String = "_v" + index.toString()
    let argExpr: String = argsVar + ".get(" + index.toString() + ").getOrThrow()"
    _emitConvert(sb, p.paramType, argExpr, convVar, indent)
    sb.append(indent)
    sb.append("if (")
    sb.append(convVar)
    sb.append(".isSome()) {\n")
    _emitConvertAndCall(sb, cmd, argsVar, isConstructor, index + 1, n, indent + "    ")
    sb.append(indent)
    sb.append("}\n")
}

func _emitConvert(sb: StringBuilder, paramType: String, argExpr: String, resultVar: String, indent: String): Unit {
    sb.append(indent)
    sb.append("let ")
    sb.append(resultVar)
    sb.append(": ")
    _appendConvertedType(sb, paramType)
    sb.append(" = ")
    if (paramType == "Int64") {
        sb.append("Int64.tryParse(")
        sb.append(argExpr)
        sb.append(")")
    } else if (paramType == "Float64") {
        sb.append("Float64.tryParse(")
        sb.append(argExpr)
        sb.append(")")
    } else if (paramType == "Bool") {
        sb.append("Bool.tryParse(")
        sb.append(argExpr)
        sb.append(")")
    } else if (paramType == "String") {
        sb.append("Option<String>.Some(")
        sb.append(argExpr)
        sb.append(")")
    } else if (paramType.startsWith("Option<")) {
        let inner: String = paramType.removePrefix("Option<").removeSuffix(">")
        sb.append("(")
        sb.append(argExpr)
        sb.append(".isEmpty() ? Option<Option<")
        sb.append(inner)
        sb.append(">>.Some(Option<")
        sb.append(inner)
        sb.append(">.None) : ")
        if (inner == "Int64") {
            sb.append("(match (Int64.tryParse(")
            sb.append(argExpr)
            sb.append(")) { Option<Int64>.Some(x) => Option<Option<Int64>>.Some(Option<Int64>.Some(x)); _ => Option<Option<Int64>>.None })")
        } else if (inner == "Float64") {
            sb.append("(match (Float64.tryParse(")
            sb.append(argExpr)
            sb.append(")) { Option<Float64>.Some(x) => Option<Option<Float64>>.Some(Option<Float64>.Some(x)); _ => Option<Option<Float64>>.None })")
        } else if (inner == "Bool") {
            sb.append("(match (Bool.tryParse(")
            sb.append(argExpr)
            sb.append(")) { Option<Bool>.Some(x) => Option<Option<Bool>>.Some(Option<Bool>.Some(x)); _ => Option<Option<Bool>>.None })")
        } else if (inner == "String") {
            sb.append("(")
            sb.append(argExpr)
            sb.append(".isEmpty() ? Option<Option<String>>.Some(Option<String>.None) : Option<Option<String>>.Some(Option<String>.Some(")
            sb.append(argExpr)
            sb.append(")))")
        } else {
            sb.append("Option<Option<")
            sb.append(inner)
            sb.append(">>.None")
        }
        sb.append(")")
    } else {
        // Class type: ref:id lookup and cast
        sb.append("(match (_parseRefId(")
        sb.append(argExpr)
        sb.append(")) { Option<Int64>.Some(id) => match (_getRef(id)) { Option<Any>.Some(o) => o as ")
        sb.append(paramType)
        sb.append(" ; _ => Option<")
        sb.append(paramType)
        sb.append(">.None } ; _ => Option<")
        sb.append(paramType)
        sb.append(">.None })")
    }
    sb.append("\n")
}

func _appendConvertedType(sb: StringBuilder, paramType: String): Unit {
    if (paramType.startsWith("Option<")) {
        let inner: String = paramType.removePrefix("Option<").removeSuffix(">")
        sb.append("Option<Option<")
        sb.append(inner)
        sb.append(">>")
    } else {
        sb.append("Option<")
        sb.append(paramType)
        sb.append(">")
    }
}

func _emitCall(sb: StringBuilder, cmd: CommandInfo, isConstructor: Bool, n: Int64): Unit {
    if (isConstructor) {
        sb.append("let _result = ")
        sb.append(cmd.className)
        sb.append("(")
        var first: Bool = true
        var pi: Int64 = 0
        while (pi < n) {
            if (!first) { sb.append(", ") }
            sb.append("_v")
            sb.append(pi.toString())
            sb.append(".getOrThrow()")
            first = false
            pi++
        }
        sb.append(")\n            ")
    } else {
        sb.append("let _result = ")
        sb.append(cmd.name)
        sb.append("(")
        var first: Bool = true
        var pi: Int64 = 0
        while (pi < n) {
            if (!first) { sb.append(", ") }
            sb.append("_v")
            sb.append(pi.toString())
            sb.append(".getOrThrow()")
            first = false
            pi++
        }
        sb.append(")\n            ")
    }
    if (cmd.returnIsRef) {
        sb.append("let _id = _storeRef(_result)\n            println(\"ref:\" + _id.toString())\n            return 0\n")
    } else if (cmd.returnType == "Unit") {
        sb.append("return 0\n")
    } else {
        sb.append("println(_result.toString())\n            return 0\n")
    }
}
