/**
 * Code generator: from a Manifest, emits Cangjie source for the CLI driver.
 * The driver imports the target package (same package when emitted into package src),
 * uses object store (monotonic id, HashMap<Int64, Any>), parses CLI args,
 * and dispatches to explicit calls with first-matching overload resolution.
 */
package pkgcli

import std.collection.ArrayList
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
    sb.append("package ")
    sb.append(pkg)
    sb.append("\n\n")
    sb.append("import std.env.*\n")
    sb.append("import std.collection.*\n")
    sb.append("import std.convert.*\n")
    sb.append("import std.core.StringBuilder\n\n")

    // Session state for runFromArgs (per-session store + nextId)
    sb.append("class _SessionState {\n")
    sb.append("    var store: HashMap<Int64, Any>\n")
    sb.append("    var nextId: Int64\n")
    sb.append("    init(store: HashMap<Int64, Any>, nextId: Int64) { this.store = store; this.nextId = nextId }\n")
    sb.append("}\n\n")
    sb.append("var _sessionState: Option<_SessionState> = Option<_SessionState>.None\n\n")
    sb.append("var _outBuf: Option<StringBuilder> = Option<StringBuilder>.None\n")
    sb.append("var _errBuf: Option<StringBuilder> = Option<StringBuilder>.None\n\n")
    sb.append("func _out(s: String): Unit {\n")
    sb.append("    if (_outBuf.isSome()) { _outBuf.getOrThrow().append(s); _outBuf.getOrThrow().append(\"\\n\") } else { println(s) }\n")
    sb.append("}\n\n")
    sb.append("func _outNoNewline(s: String): Unit {\n")
    sb.append("    if (_outBuf.isSome()) { _outBuf.getOrThrow().append(s) } else { print(s) }\n")
    sb.append("}\n\n")
    sb.append("func _err(s: String): Unit {\n")
    sb.append("    if (_errBuf.isSome()) { _errBuf.getOrThrow().append(s); _errBuf.getOrThrow().append(\"\\n\") } else { eprintln(s) }\n")
    sb.append("}\n\n")

    // Object store and helpers (use session state when set, else global)
    sb.append("var _nextId: Int64 = 1\n")
    sb.append("var _store: HashMap<Int64, Any> = HashMap<Int64, Any>()\n\n")
    sb.append("var _cwd: String = \"/\"\n\n")
    sb.append("func _storeRef(obj: Any): Int64 {\n")
    sb.append("    if (_sessionState.isSome()) {\n")
    sb.append("        let st = _sessionState.getOrThrow()\n")
    sb.append("        let id = st.nextId\n")
    sb.append("        st.nextId = st.nextId + 1\n")
    sb.append("        st.store.add(id, obj)\n")
    sb.append("        id\n")
    sb.append("    } else {\n")
    sb.append("        let id = _nextId\n")
    sb.append("        _nextId++\n")
    sb.append("        _store.add(id, obj)\n")
    sb.append("        id\n")
    sb.append("    }\n")
    sb.append("}\n\n")
    var hasRefParam: Bool = false
    var ci: Int64 = 0
    while (ci < manifest.commands.size) {
        let cmd: CommandInfo = manifest.commands.get(ci).getOrThrow()
        var pi: Int64 = 0
        while (pi < cmd.params.size) {
            let p: ParamInfo = cmd.params.get(pi).getOrThrow()
            if (isRefType(p.paramType)) { hasRefParam = true }
            pi++
        }
        ci++
    }
    if (hasRefParam) {
        sb.append("func _getRef(id: Int64): Option<Any> {\n")
        sb.append("    if (_sessionState.isSome()) { _sessionState.getOrThrow().store.get(id) } else { _store.get(id) }\n")
        sb.append("}\n\n")
        sb.append("func _parseRefId(s: String): Option<Int64> {\n")
        sb.append("    if (s.startsWith(\"ref:\")) { Int64.tryParse(s.removePrefix(\"ref:\")) } else { Option<Int64>.None }\n")
        sb.append("}\n\n")
    }
    sb.append("func _formatArgTypes(args: ArrayList<String>): String {\n")
    sb.append("    let sb: StringBuilder = StringBuilder()\n")
    sb.append("    sb.append(\"[\")\n")
    sb.append("    var i: Int64 = 0\n")
    sb.append("    while (i < args.size) {\n")
    sb.append("        if (i > 0) { sb.append(\", \") }\n")
    sb.append("        let a: String = args.get(i).getOrThrow()\n")
    sb.append("        if (a.startsWith(\"ref:\") && Int64.tryParse(a.removePrefix(\"ref:\")).isSome()) { sb.append(\"ref\") }\n")
    sb.append("        else if (Int64.tryParse(a).isSome()) { sb.append(\"Int64\") }\n")
    sb.append("        else { sb.append(\"String\") }\n")
    sb.append("        i++\n")
    sb.append("    }\n")
    sb.append("    sb.append(\"]\")\n")
    sb.append("    sb.toString()\n")
    sb.append("}\n\n")
    sb.append("// Split argv[1..] by \";\" so multiple commands in one run get ref:1, ref:2, ...\n")
    sb.append("func _splitArgsBySemicolon(allArgs: Array<String>): ArrayList<ArrayList<String>> {\n")
    sb.append("    let result: ArrayList<ArrayList<String>> = ArrayList<ArrayList<String>>()\n")
    sb.append("    var current: ArrayList<String> = ArrayList<String>()\n")
    sb.append("    var i: Int64 = 1\n")
    sb.append("    while (i < allArgs.size) {\n")
    sb.append("        let a: String = allArgs[i]\n")
    sb.append("        if (a == \";\") {\n")
    sb.append("            if (current.size > 0) { result.add(all: [current]); current = ArrayList<String>() }\n")
    sb.append("        } else {\n")
    sb.append("            current.add(all: [a])\n")
    sb.append("        }\n")
    sb.append("        i++\n")
    sb.append("    }\n")
    sb.append("    if (current.size > 0) { result.add(all: [current]) }\n")
    sb.append("    result\n")
    sb.append("}\n\n")
    sb.append("// Split normalized line by \" ; \" so each segment can be parsed (assignment + tokenize with env) separately.\n")
    sb.append("func _splitStringBySemicolon(s: String): ArrayList<String> {\n")
    sb.append("    let result: ArrayList<String> = ArrayList<String>()\n")
    sb.append("    var start: Int64 = 0\n")
    sb.append("    var i: Int64 = 0\n")
    sb.append("    while (i + 3 <= s.size) {\n")
    sb.append("        if (_substring(s, i, i + 3) == \" ; \") {\n")
    sb.append("            result.add(all: [_substring(s, start, i)])\n")
    sb.append("            start = i + 3\n")
    sb.append("            i = i + 3\n")
    sb.append("        } else { i++ }\n")
    sb.append("    }\n")
    sb.append("    result.add(all: [_substring(s, start, s.size)])\n")
    sb.append("    result\n")
    sb.append("}\n\n")
    sb.append("// Split token list by \";\" so stdin/web lines behave like argv (multiple commands per line).\n")
    sb.append("func _splitTokensBySemicolon(tokens: ArrayList<String>): ArrayList<ArrayList<String>> {\n")
    sb.append("    let result: ArrayList<ArrayList<String>> = ArrayList<ArrayList<String>>()\n")
    sb.append("    var current: ArrayList<String> = ArrayList<String>()\n")
    sb.append("    var i: Int64 = 0\n")
    sb.append("    while (i < tokens.size) {\n")
    sb.append("        let t: String = tokens.get(i).getOrThrow()\n")
    sb.append("        if (t == \";\") {\n")
    sb.append("            if (current.size > 0) { result.add(all: [current]); current = ArrayList<String>() }\n")
    sb.append("        } else {\n")
    sb.append("            current.add(all: [t])\n")
    sb.append("        }\n")
    sb.append("        i++\n")
    sb.append("    }\n")
    sb.append("    if (current.size > 0) { result.add(all: [current]) }\n")
    sb.append("    result\n")
    sb.append("}\n\n")

    // Group commands by (packagePath, CLI key); class methods by (packagePath, className, methodName)
    let commandPackagePaths: ArrayList<String> = ArrayList<String>()
    let keys: ArrayList<String> = ArrayList<String>()
    let overloadsList: ArrayList<ArrayList<CommandInfo>> = ArrayList<ArrayList<CommandInfo>>()
    let cmPackagePaths: ArrayList<String> = ArrayList<String>()
    let classMethodClassNames: ArrayList<String> = ArrayList<String>()
    let classMethodNames: ArrayList<String> = ArrayList<String>()
    let classMethodIsInstance: ArrayList<Bool> = ArrayList<Bool>()
    let classMethodOverloadsList: ArrayList<ArrayList<CommandInfo>> = ArrayList<ArrayList<CommandInfo>>()
    var i: Int64 = 0
    while (i < manifest.commands.size) {
        let cmd: CommandInfo = manifest.commands.get(i).getOrThrow()
        if (cmd.isInstanceMethod || cmd.isStaticMethod) {
            var found: Bool = false
            var j: Int64 = 0
            while (j < classMethodClassNames.size) {
                if (cmPackagePaths.get(j).getOrThrow() == cmd.packagePath && classMethodClassNames.get(j).getOrThrow() == cmd.className && classMethodNames.get(j).getOrThrow() == cmd.name) {
                    classMethodOverloadsList.get(j).getOrThrow().add(all: [cmd])
                    found = true
                    break
                }
                j++
            }
            if (!found) {
                cmPackagePaths.add(all: [cmd.packagePath])
                classMethodClassNames.add(all: [cmd.className])
                classMethodNames.add(all: [cmd.name])
                classMethodIsInstance.add(all: [cmd.isInstanceMethod])
                let list: ArrayList<CommandInfo> = ArrayList<CommandInfo>()
                list.add(all: [cmd])
                classMethodOverloadsList.add(all: [list])
            }
        } else {
            let key: String = if (cmd.isConstructor) { cmd.className } else { cmd.name }
            var found: Bool = false
            var j: Int64 = 0
            while (j < keys.size) {
                if (commandPackagePaths.get(j).getOrThrow() == cmd.packagePath && keys.get(j).getOrThrow() == key) {
                    overloadsList.get(j).getOrThrow().add(all: [cmd])
                    found = true
                    break
                }
                j++
            }
            if (!found) {
                commandPackagePaths.add(all: [cmd.packagePath])
                keys.add(all: [key])
                let list: ArrayList<CommandInfo> = ArrayList<CommandInfo>()
                list.add(all: [cmd])
                overloadsList.add(all: [list])
            }
        }
        i++
    }

    let knownPaths: ArrayList<String> = _buildKnownPaths(manifest)
    _emitPathHelpers(sb, knownPaths)

    // _runSegments(segments): run each segment, return first non-zero exit code or 0
    sb.append("func _runSegments(segments: ArrayList<ArrayList<String>>): Int64 {\n")
    sb.append("    var segIdx: Int64 = 0\n")
    sb.append("    while (segIdx < segments.size) {\n")
    sb.append("        let seg: ArrayList<String> = segments.get(segIdx).getOrThrow()\n")
    sb.append("        segIdx++\n")
    sb.append("        if (seg.size < 1) { continue }\n")
    sb.append("        let firstToken: String = seg.get(0).getOrThrow()\n")
    sb.append("        var argsList: ArrayList<String> = ArrayList<String>()\n")
    sb.append("        var ai: Int64 = 1\n")
    sb.append("        while (ai < seg.size) { argsList.add(all: [seg.get(ai).getOrThrow()]); ai++ }\n")
    sb.append("        var resolvedDir: String = _cwd\n")
    sb.append("        var command: String = firstToken\n")
    sb.append("        var slashIdx: Int64 = firstToken.size - 1\n")
    sb.append("        while (slashIdx >= 0 && Int64(firstToken.get(slashIdx).getOrThrow()) != 47) { slashIdx-- }\n")
    sb.append("        if (slashIdx >= 0) {\n")
    sb.append("            let dirPart: String = _substring(firstToken, 0, slashIdx)\n")
    sb.append("            let commandPart: String = _substring(firstToken, slashIdx + 1, firstToken.size)\n")
    sb.append("            if (commandPart.size > 0) {\n")
    sb.append("                match (_normalizePath(dirPart, _cwd)) {\n")
    sb.append("                    case Option<String>.None => _err(\"Invalid path\"); return 64\n")
    sb.append("                    case Option<String>.Some(rd) => resolvedDir = rd; command = commandPart\n")
    sb.append("                }\n")
    sb.append("            }\n")
    sb.append("        }\n")
    sb.append("        if (command == \"cd\") {\n")
    sb.append("            if (argsList.size < 1) { _err(\"Usage: cd <path>\"); return 64 }\n")
    sb.append("            match (_normalizePath(argsList.get(0).getOrThrow(), _cwd)) {\n")
    sb.append("                case Option<String>.None => _err(\"Invalid path\"); return 64\n")
    sb.append("                case Option<String>.Some(np) =>\n")
    sb.append("                    if (!_isKnownPath(np)) { _err(\"No such directory: \" + np); return 64 }\n")
    sb.append("                    _cwd = np\n")
    sb.append("            }\n")
    sb.append("            continue\n")
    sb.append("        }\n")
    sb.append("        if (command == \"help\") {\n")
    sb.append("            _printHelp()\n")
    sb.append("            continue\n")
    sb.append("        }\n")
    sb.append("        if (command == \"echo\") {\n")
    sb.append("            let sb: StringBuilder = StringBuilder()\n")
    sb.append("            var ei: Int64 = 0\n")
    sb.append("            while (ei < argsList.size) {\n")
    sb.append("                if (ei > 0) { sb.append(\" \") }\n")
    sb.append("                sb.append(argsList.get(ei).getOrThrow())\n")
    sb.append("                ei++\n")
    sb.append("            }\n")
    sb.append("            _out(sb.toString())\n")
    sb.append("            continue\n")
    sb.append("        }\n")

    var cmIdx: Int64 = 0
    while (cmIdx < classMethodClassNames.size) {
        let cmPkg: String = cmPackagePaths.get(cmIdx).getOrThrow()
        let cmClass: String = classMethodClassNames.get(cmIdx).getOrThrow()
        let cmMethod: String = classMethodNames.get(cmIdx).getOrThrow()
        let cmInstance: Bool = classMethodIsInstance.get(cmIdx).getOrThrow()
        sb.append("        if (resolvedDir == \"")
        _appendEscapedForHelp(sb, cmPkg)
        sb.append("\" && command == \"")
        sb.append(cmClass)
        sb.append("\" && argsList.size >= 1 && argsList.get(0).getOrThrow() == \"")
        sb.append(cmMethod)
        sb.append("\") {\n")
        if (cmInstance) {
            sb.append("            var instArgs: ArrayList<String> = ArrayList<String>()\n")
            sb.append("            var ia: Int64 = 1\n")
            sb.append("            while (ia < argsList.size) { instArgs.add(all: [argsList.get(ia).getOrThrow()]); ia++ }\n")
        } else {
            sb.append("            var instArgs: ArrayList<String> = ArrayList<String>()\n")
            sb.append("            var ia: Int64 = 2\n")
            sb.append("            while (ia < argsList.size) { instArgs.add(all: [argsList.get(ia).getOrThrow()]); ia++ }\n")
        }
        sb.append("            let _code = _run")
        _appendSafeName(sb, cmClass + "_" + cmMethod)
        sb.append("(instArgs)\n")
        sb.append("            if (_code != 0) { return _code }\n")
        sb.append("            continue\n")
        sb.append("        }\n")
        cmIdx++
    }

    var k: Int64 = 0
    while (k < keys.size) {
        let pkgPath: String = commandPackagePaths.get(k).getOrThrow()
        let key: String = keys.get(k).getOrThrow()
        let _: ArrayList<CommandInfo> = overloadsList.get(k).getOrThrow()
        sb.append("        if (resolvedDir == \"")
        _appendEscapedForHelp(sb, pkgPath)
        sb.append("\" && command == \"")
        sb.append(key)
        sb.append("\") {\n")
        sb.append("            let _code = _run")
        _appendSafeName(sb, key)
        sb.append("(argsList)\n")
        sb.append("            if (_code != 0) { return _code }\n")
        sb.append("            continue\n")
        sb.append("        }\n")
        k++
    }

    sb.append("        _err(\"Unknown command: \" + command + \" (in \" + resolvedDir + \")\")\n")
    sb.append("        return 64\n")
    sb.append("    }\n")
    sb.append("    return 0\n")
    sb.append("}\n\n")

    sb.append("func _escapeNewlines(s: String): String {\n")
    sb.append("    let sb: StringBuilder = StringBuilder()\n")
    sb.append("    var i: Int64 = 0\n")
    sb.append("    while (i < s.size) {\n")
    sb.append("        let code: Int64 = Int64(s.get(i).getOrThrow())\n")
    sb.append("        if (code == 10) { sb.append(\" <NL> \") } else { sb.append(Rune(UInt32(code))) }\n")
    sb.append("        i++\n")
    sb.append("    }\n")
    sb.append("    sb.toString()\n")
    sb.append("}\n\n")
    sb.append("// Normalize: replace newline/\\\\r with space, insert spaces before and after every semicolon.\n")
    sb.append("func _normalizeCommandLine(s: String): String {\n")
    sb.append("    let sb: StringBuilder = StringBuilder()\n")
    sb.append("    var i: Int64 = 0\n")
    sb.append("    while (i < s.size) {\n")
    sb.append("        let c: Int64 = Int64(s.get(i).getOrThrow())\n")
    sb.append("        if (c == 10 || c == 13) { sb.append(\" \"); i++; continue }\n")
    sb.append("        if (c == 59) { sb.append(\" ; \"); i++; continue }\n")
    sb.append("        sb.append(Rune(UInt32(c)))\n")
    sb.append("        i++\n")
    sb.append("    }\n")
    sb.append("    sb.toString()\n")
    sb.append("}\n\n")
    sb.append("func _tokenizeStdinLine(line: String, env: HashMap<String, String>): ArrayList<String> {\n")
    sb.append("    let result: ArrayList<String> = ArrayList<String>()\n")
    sb.append("    var i: Int64 = 0\n")
    sb.append("    while (i < line.size) {\n")
    sb.append("        let c: Int64 = Int64(line.get(i).getOrThrow())\n")
    sb.append("        if (c != 32 && c != 9) {\n")
    sb.append("            let start: Int64 = i\n")
    sb.append("            while (i < line.size && Int64(line.get(i).getOrThrow()) != 32 && Int64(line.get(i).getOrThrow()) != 9) { i++ }\n")
    sb.append("            var tok: String = _substring(line, start, i)\n")
    sb.append("            if (tok.startsWith(\"$\")) {\n")
    sb.append("                let name: String = tok.removePrefix(\"$\")\n")
    sb.append("                match (env.get(name)) {\n")
    sb.append("                    case Option<String>.Some(id) => tok = \"ref:\" + id\n")
    sb.append("                    case _ => tok = \"\"\n")
    sb.append("                }\n")
    sb.append("            }\n")
    sb.append("            if (tok.size > 0) { result.add(all: [tok]) }\n")
    sb.append("        } else { i++ }\n")
    sb.append("    }\n")
    sb.append("    result\n")
    sb.append("}\n\n")
    sb.append("// Read one line from stdin; keeps process alive for one session per connection (web terminal).\n")
    sb.append("func _readLineStdin(): String {\n")
    sb.append("    match (getStdIn().readln()) {\n")
    sb.append("        case Option<String>.Some(s) => s\n")
    sb.append("        case _ => \"\"\n")
    sb.append("    }\n")
    sb.append("}\n\n")
    sb.append("func _findLastRefInStdout(s: String): String {\n")
    sb.append("    var last: String = \"\"\n")
    sb.append("    var i: Int64 = 0\n")
    sb.append("    while (i + 4 <= s.size) {\n")
    sb.append("        if (_substring(s, i, i + 4) == \"ref:\") {\n")
    sb.append("            var j: Int64 = i + 4\n")
    sb.append("            while (j < s.size) {\n")
    sb.append("                let code: Int64 = Int64(s.get(j).getOrThrow())\n")
    sb.append("                if (code >= 48 && code <= 57) { j++ } else { break }\n")
    sb.append("            }\n")
    sb.append("            last = _substring(s, i + 4, j)\n")
    sb.append("            i = j\n")
    sb.append("        } else { i++ }\n")
    sb.append("    }\n")
    sb.append("    last\n")
    sb.append("}\n\n")
    sb.append("func _serveStdin(): Int64 {\n")
    sb.append("    let store: HashMap<Int64, Any> = HashMap<Int64, Any>()\n")
    sb.append("    let state: _SessionState = _SessionState(store, 1)\n")
    sb.append("    _sessionState = Option<_SessionState>.Some(state)\n")
    sb.append("    let env: HashMap<String, String> = HashMap<String, String>()\n")
    sb.append("    while (true) {\n")
    sb.append("        let line: String = _readLineStdin()\n")
    sb.append("        let trimmed: String = line.trimStart(\" \\t\").trimEnd(\" \\t\")\n")
    sb.append("        if (trimmed.size == 0) { break }\n")
    sb.append("        if (trimmed == \"exit\" || trimmed == \"quit\") { break }\n")
    sb.append("        let normalized: String = _normalizeCommandLine(trimmed)\n")
    sb.append("        let segmentStrings: ArrayList<String> = _splitStringBySemicolon(normalized)\n")
    sb.append("        let outBuf: StringBuilder = StringBuilder()\n")
    sb.append("        let errBuf: StringBuilder = StringBuilder()\n")
    sb.append("        _outBuf = Option<StringBuilder>.Some(outBuf)\n")
    sb.append("        _errBuf = Option<StringBuilder>.Some(errBuf)\n")
    sb.append("        var segIdx: Int64 = 0\n")
    sb.append("        while (segIdx < segmentStrings.size) {\n")
    sb.append("            let segStr: String = segmentStrings.get(segIdx).getOrThrow()\n")
    sb.append("            segIdx++\n")
    sb.append("            let segTrimmed: String = segStr.trimStart(\" \\t\").trimEnd(\" \\t\")\n")
    sb.append("            if (segTrimmed.size == 0) { continue }\n")
    sb.append("            match (segTrimmed.indexOf(\" = \")) {\n")
    sb.append("                case Option<Int64>.Some(idx) =>\n")
    sb.append("                    let envName: String = _substring(segTrimmed, 0, idx).trimStart(\" \\t\").trimEnd(\" \\t\")\n")
    sb.append("                    let commandLine: String = _substring(segTrimmed, idx + 3, segTrimmed.size).trimStart(\" \\t\").trimEnd(\" \\t\")\n")
    sb.append("                    let tokens: ArrayList<String> = _tokenizeStdinLine(commandLine, env)\n")
    sb.append("                    if (tokens.size > 0) {\n")
    sb.append("                        let oneSeg: ArrayList<ArrayList<String>> = ArrayList<ArrayList<String>>()\n")
    sb.append("                        oneSeg.add(all: [tokens])\n")
    sb.append("                        let _ = _runSegments(oneSeg)\n")
    sb.append("                        let lastRef: String = _findLastRefInStdout(outBuf.toString())\n")
    sb.append("                        if (envName.size > 0 && lastRef.size > 0) { env.add(envName, lastRef) }\n")
    sb.append("                    }\n")
    sb.append("                case _ =>\n")
    sb.append("                    let tokens: ArrayList<String> = _tokenizeStdinLine(segTrimmed, env)\n")
    sb.append("                    if (tokens.size > 0) {\n")
    sb.append("                        let oneSeg: ArrayList<ArrayList<String>> = ArrayList<ArrayList<String>>()\n")
    sb.append("                        oneSeg.add(all: [tokens])\n")
    sb.append("                        let _ = _runSegments(oneSeg)\n")
    sb.append("                    }\n")
    sb.append("            }\n")
    sb.append("        }\n")
    sb.append("        _outNoNewline(\"")
    _appendPkgSanitized(sb, pkg)
    sb.append(" session finished\")\n")
    sb.append("        let outStr: String = outBuf.toString()\n")
    sb.append("        let errStr: String = errBuf.toString()\n")
    sb.append("        _outBuf = Option<StringBuilder>.None\n")
    sb.append("        _errBuf = Option<StringBuilder>.None\n")
    sb.append("        println(_escapeNewlines(outStr) + \"\\t\" + _escapeNewlines(errStr))\n")
    sb.append("    }\n")
    sb.append("    _sessionState = Option<_SessionState>.None\n")
    sb.append("    return 0\n")
    sb.append("}\n\n")
    sb.append("main(): Int64 {\n")
    sb.append("    let allArgs: Array<String> = getCommandLine()\n")
    sb.append("    if (allArgs.size == 2 && allArgs[1] == \"--serve-stdin\") { return _serveStdin() }\n")
    sb.append("    if (allArgs.size == 2 && allArgs[1] != \"--serve-stdin\") {\n")
    sb.append("        let line: String = allArgs[1]\n")
    sb.append("        let trimmed: String = line.trimStart(\" \\t\").trimEnd(\" \\t\")\n")
    sb.append("        let normalized: String = _normalizeCommandLine(trimmed)\n")
    sb.append("        let segmentStrings: ArrayList<String> = _splitStringBySemicolon(normalized)\n")
    sb.append("        let env: HashMap<String, String> = HashMap<String, String>()\n")
    sb.append("        let outBuf: StringBuilder = StringBuilder()\n")
    sb.append("        let errBuf: StringBuilder = StringBuilder()\n")
    sb.append("        _outBuf = Option<StringBuilder>.Some(outBuf)\n")
    sb.append("        _errBuf = Option<StringBuilder>.Some(errBuf)\n")
    sb.append("        var segIdx: Int64 = 0\n")
    sb.append("        while (segIdx < segmentStrings.size) {\n")
    sb.append("            let segStr: String = segmentStrings.get(segIdx).getOrThrow()\n")
    sb.append("            segIdx++\n")
    sb.append("            let segTrimmed: String = segStr.trimStart(\" \\t\").trimEnd(\" \\t\")\n")
    sb.append("            if (segTrimmed.size == 0) { continue }\n")
    sb.append("            match (segTrimmed.indexOf(\" = \")) {\n")
    sb.append("                case Option<Int64>.Some(idx) =>\n")
    sb.append("                    let envName: String = _substring(segTrimmed, 0, idx).trimStart(\" \\t\").trimEnd(\" \\t\")\n")
    sb.append("                    let commandLine: String = _substring(segTrimmed, idx + 3, segTrimmed.size).trimStart(\" \\t\").trimEnd(\" \\t\")\n")
    sb.append("                    let tokens: ArrayList<String> = _tokenizeStdinLine(commandLine, env)\n")
    sb.append("                    if (tokens.size > 0) {\n")
    sb.append("                        let oneSeg: ArrayList<ArrayList<String>> = ArrayList<ArrayList<String>>()\n")
    sb.append("                        oneSeg.add(all: [tokens])\n")
    sb.append("                        let _ = _runSegments(oneSeg)\n")
    sb.append("                        let lastRef: String = _findLastRefInStdout(outBuf.toString())\n")
    sb.append("                        if (envName.size > 0 && lastRef.size > 0) { env.add(envName, lastRef) }\n")
    sb.append("                    }\n")
    sb.append("                case _ =>\n")
    sb.append("                    let tokens: ArrayList<String> = _tokenizeStdinLine(segTrimmed, env)\n")
    sb.append("                    if (tokens.size > 0) {\n")
    sb.append("                        let oneSeg: ArrayList<ArrayList<String>> = ArrayList<ArrayList<String>>()\n")
    sb.append("                        oneSeg.add(all: [tokens])\n")
    sb.append("                        let _ = _runSegments(oneSeg)\n")
    sb.append("                    }\n")
    sb.append("            }\n")
    sb.append("        }\n")
    sb.append("        _outNoNewline(\"")
    _appendPkgSanitized(sb, pkg)
    sb.append(" session finished\")\n")
    sb.append("        let outStr: String = outBuf.toString()\n")
    sb.append("        let errStr: String = errBuf.toString()\n")
    sb.append("        _outBuf = Option<StringBuilder>.None\n")
    sb.append("        _errBuf = Option<StringBuilder>.None\n")
    sb.append("        println(_escapeNewlines(outStr) + \"\\t\" + _escapeNewlines(errStr))\n")
    sb.append("        return 0\n")
    sb.append("    }\n")
    sb.append("    if (allArgs.size >= 2) {\n")
    sb.append("        var runArgsLine: String = \"\"\n")
    sb.append("        var ai: Int64 = 1\n")
    sb.append("        while (ai < allArgs.size) {\n")
    sb.append("            let a: String = allArgs[ai]\n")
    sb.append("            if (a == \"--run-args\" && ai + 1 < allArgs.size) {\n")
    sb.append("                runArgsLine = allArgs[ai + 1]\n")
    sb.append("                break\n")
    sb.append("            }\n")
    sb.append("            if (a.size >= 11 && _substring(a, 0, 11) == \"--run-args=\") {\n")
    sb.append("                runArgsLine = _substring(a, 11, a.size)\n")
    sb.append("                ai++\n")
    sb.append("                while (ai < allArgs.size) { runArgsLine = runArgsLine + \" \" + allArgs[ai]; ai++ }\n")
    sb.append("                break\n")
    sb.append("            }\n")
    sb.append("            ai++\n")
    sb.append("        }\n")
    sb.append("        if (runArgsLine.size > 0) {\n")
    sb.append("            let line: String = runArgsLine\n")
    sb.append("            let trimmed: String = line.trimStart(\" \\t\").trimEnd(\" \\t\")\n")
    sb.append("            let normalized: String = _normalizeCommandLine(trimmed)\n")
    sb.append("            let segmentStrings: ArrayList<String> = _splitStringBySemicolon(normalized)\n")
    sb.append("            let env: HashMap<String, String> = HashMap<String, String>()\n")
    sb.append("            let outBuf: StringBuilder = StringBuilder()\n")
    sb.append("            let errBuf: StringBuilder = StringBuilder()\n")
    sb.append("            _outBuf = Option<StringBuilder>.Some(outBuf)\n")
    sb.append("            _errBuf = Option<StringBuilder>.Some(errBuf)\n")
    sb.append("            var segIdx: Int64 = 0\n")
    sb.append("            while (segIdx < segmentStrings.size) {\n")
    sb.append("                let segStr: String = segmentStrings.get(segIdx).getOrThrow()\n")
    sb.append("                segIdx++\n")
    sb.append("                let segTrimmed: String = segStr.trimStart(\" \\t\").trimEnd(\" \\t\")\n")
    sb.append("                if (segTrimmed.size == 0) { continue }\n")
    sb.append("                match (segTrimmed.indexOf(\" = \")) {\n")
    sb.append("                    case Option<Int64>.Some(idx) =>\n")
    sb.append("                        let envName: String = _substring(segTrimmed, 0, idx).trimStart(\" \\t\").trimEnd(\" \\t\")\n")
    sb.append("                        let commandLine: String = _substring(segTrimmed, idx + 3, segTrimmed.size).trimStart(\" \\t\").trimEnd(\" \\t\")\n")
    sb.append("                        let tokens: ArrayList<String> = _tokenizeStdinLine(commandLine, env)\n")
    sb.append("                        if (tokens.size > 0) {\n")
    sb.append("                            let oneSeg: ArrayList<ArrayList<String>> = ArrayList<ArrayList<String>>()\n")
    sb.append("                            oneSeg.add(all: [tokens])\n")
    sb.append("                            let _ = _runSegments(oneSeg)\n")
    sb.append("                            let lastRef: String = _findLastRefInStdout(outBuf.toString())\n")
    sb.append("                            if (envName.size > 0 && lastRef.size > 0) { env.add(envName, lastRef) }\n")
    sb.append("                        }\n")
    sb.append("                    case _ =>\n")
    sb.append("                        let tokens: ArrayList<String> = _tokenizeStdinLine(segTrimmed, env)\n")
    sb.append("                        if (tokens.size > 0) {\n")
    sb.append("                            let oneSeg: ArrayList<ArrayList<String>> = ArrayList<ArrayList<String>>()\n")
    sb.append("                            oneSeg.add(all: [tokens])\n")
    sb.append("                            let _ = _runSegments(oneSeg)\n")
    sb.append("                        }\n")
    sb.append("                }\n")
    sb.append("            }\n")
    sb.append("            _outNoNewline(\"")
    _appendPkgSanitized(sb, pkg)
    sb.append(" session finished\")\n")
    sb.append("            let outStr: String = outBuf.toString()\n")
    sb.append("            let errStr: String = errBuf.toString()\n")
    sb.append("            _outBuf = Option<StringBuilder>.None\n")
    sb.append("            _errBuf = Option<StringBuilder>.None\n")
    sb.append("            println(_escapeNewlines(outStr) + \"\\t\" + _escapeNewlines(errStr))\n")
    sb.append("            return 0\n")
    sb.append("        }\n")
    sb.append("    }\n")
    sb.append("    if (allArgs.size < 2) {\n")
    sb.append("        _out(\"Usage: <command> [args...]  Separate commands with ; for ref:1, ref:2, ...\")\n")
    sb.append("        _printHelp()\n")
    sb.append("        return 0\n")
    sb.append("    }\n")
    sb.append("    var argvLine: String = \"\"\n")
    sb.append("    var joinIdx: Int64 = 1\n")
    sb.append("    while (joinIdx < allArgs.size) {\n")
    sb.append("        if (joinIdx > 1) { argvLine = argvLine + \" \" }\n")
    sb.append("        argvLine = argvLine + allArgs[joinIdx]\n")
    sb.append("        joinIdx++\n")
    sb.append("    }\n")
    sb.append("    let trimmed: String = argvLine.trimStart(\" \\t\").trimEnd(\" \\t\")\n")
    sb.append("    let normalized: String = _normalizeCommandLine(trimmed)\n")
    sb.append("    let segmentStrings: ArrayList<String> = _splitStringBySemicolon(normalized)\n")
    sb.append("    let env: HashMap<String, String> = HashMap<String, String>()\n")
    sb.append("    let outBuf: StringBuilder = StringBuilder()\n")
    sb.append("    let errBuf: StringBuilder = StringBuilder()\n")
    sb.append("    _outBuf = Option<StringBuilder>.Some(outBuf)\n")
    sb.append("    _errBuf = Option<StringBuilder>.Some(errBuf)\n")
    sb.append("    var segIdx: Int64 = 0\n")
    sb.append("    while (segIdx < segmentStrings.size) {\n")
    sb.append("        let segStr: String = segmentStrings.get(segIdx).getOrThrow()\n")
    sb.append("        segIdx++\n")
    sb.append("        let segTrimmed: String = segStr.trimStart(\" \\t\").trimEnd(\" \\t\")\n")
    sb.append("        if (segTrimmed.size == 0) { continue }\n")
    sb.append("        match (segTrimmed.indexOf(\" = \")) {\n")
    sb.append("            case Option<Int64>.Some(idx) =>\n")
    sb.append("                let envName: String = _substring(segTrimmed, 0, idx).trimStart(\" \\t\").trimEnd(\" \\t\")\n")
    sb.append("                let commandLine: String = _substring(segTrimmed, idx + 3, segTrimmed.size).trimStart(\" \\t\").trimEnd(\" \\t\")\n")
    sb.append("                let tokens: ArrayList<String> = _tokenizeStdinLine(commandLine, env)\n")
    sb.append("                if (tokens.size > 0) {\n")
    sb.append("                    let oneSeg: ArrayList<ArrayList<String>> = ArrayList<ArrayList<String>>()\n")
    sb.append("                    oneSeg.add(all: [tokens])\n")
    sb.append("                    let _ = _runSegments(oneSeg)\n")
    sb.append("                    let lastRef: String = _findLastRefInStdout(outBuf.toString())\n")
    sb.append("                    if (envName.size > 0 && lastRef.size > 0) { env.add(envName, lastRef) }\n")
    sb.append("                }\n")
    sb.append("            case _ =>\n")
    sb.append("                let tokens: ArrayList<String> = _tokenizeStdinLine(segTrimmed, env)\n")
    sb.append("                if (tokens.size > 0) {\n")
    sb.append("                    let oneSeg: ArrayList<ArrayList<String>> = ArrayList<ArrayList<String>>()\n")
    sb.append("                    oneSeg.add(all: [tokens])\n")
    sb.append("                    let _ = _runSegments(oneSeg)\n")
    sb.append("                }\n")
    sb.append("        }\n")
    sb.append("    }\n")
    sb.append("    _outNoNewline(\"")
    _appendPkgSanitized(sb, pkg)
    sb.append(" session finished\")\n")
    sb.append("    let outStr: String = outBuf.toString()\n")
    sb.append("    let errStr: String = errBuf.toString()\n")
    sb.append("    _outBuf = Option<StringBuilder>.None\n")
    sb.append("    _errBuf = Option<StringBuilder>.None\n")
    sb.append("    println(_escapeNewlines(outStr) + \"\\t\" + _escapeNewlines(errStr))\n")
    sb.append("    return 0\n")
    sb.append("}\n\n")

    // Public library entrypoint for session actors (browser terminal backend)
    sb.append("public class RunFromArgsResult {\n")
    sb.append("    var nextId: Int64\n")
    sb.append("    var exitCode: Int64\n")
    sb.append("    var stdout: String\n")
    sb.append("    var stderr: String\n")
    sb.append("    init(nextId: Int64, exitCode: Int64, stdout: String, stderr: String) { this.nextId = nextId; this.exitCode = exitCode; this.stdout = stdout; this.stderr = stderr }\n")
    sb.append("}\n\n")
    sb.append("public func runFromArgs(args: Array<String>, store: HashMap<Int64, Any>, nextId: Int64): RunFromArgsResult {\n")
    sb.append("    let seg: ArrayList<String> = ArrayList<String>()\n")
    sb.append("    var ai: Int64 = 0\n")
    sb.append("    while (ai < args.size) { seg.add(all: [args[ai]]); ai++ }\n")
    sb.append("    let segments: ArrayList<ArrayList<String>> = ArrayList<ArrayList<String>>()\n")
    sb.append("    segments.add(all: [seg])\n")
    sb.append("    let state = _SessionState(store, nextId)\n")
    sb.append("    _sessionState = Option<_SessionState>.Some(state)\n")
    sb.append("    let outBuf = StringBuilder()\n")
    sb.append("    let errBuf = StringBuilder()\n")
    sb.append("    _outBuf = Option<StringBuilder>.Some(outBuf)\n")
    sb.append("    _errBuf = Option<StringBuilder>.Some(errBuf)\n")
    sb.append("    let exitCode = _runSegments(segments)\n")
    sb.append("    let newNextId = state.nextId\n")
    sb.append("    let outStr = outBuf.toString()\n")
    sb.append("    let errStr = errBuf.toString()\n")
    sb.append("    _sessionState = Option<_SessionState>.None\n")
    sb.append("    _outBuf = Option<StringBuilder>.None\n")
    sb.append("    _errBuf = Option<StringBuilder>.None\n")
    sb.append("    RunFromArgsResult(newNextId, exitCode, outStr, errStr)\n")
    sb.append("}\n\n")

    // Helper: print help from manifest (one _out per command, newline-separated; arg names in _underscores_ for italics; no "constructor")
    sb.append("func _printHelp(): Unit {\n")
    sb.append("    _out(\"Commands:\")\n")
    sb.append("    _out(\"`echo` [args...]  (built-in)\")\n")
    k = 0
    while (k < keys.size) {
        let pkgPath: String = commandPackagePaths.get(k).getOrThrow()
        let key: String = keys.get(k).getOrThrow()
        let overloads: ArrayList<CommandInfo> = overloadsList.get(k).getOrThrow()
        let cmd0: CommandInfo = overloads.get(0).getOrThrow()
        let displayKey: String = if (pkgPath == "/") { key } else { pkgPath + "/" + key }
        let line: String = _buildHelpLine(displayKey, cmd0)
        sb.append("    _out(\"")
        _appendEscapedForHelp(sb, line)
        sb.append("\")\n")
        k++
    }
    cmIdx = 0
    while (cmIdx < classMethodClassNames.size) {
        let cmPkg: String = cmPackagePaths.get(cmIdx).getOrThrow()
        let cmClass: String = classMethodClassNames.get(cmIdx).getOrThrow()
        let cmMethod: String = classMethodNames.get(cmIdx).getOrThrow()
        let cmOverloads: ArrayList<CommandInfo> = classMethodOverloadsList.get(cmIdx).getOrThrow()
        let cmd0: CommandInfo = cmOverloads.get(0).getOrThrow()
        let cmKey: String = if (cmPkg == "/") { cmClass + " " + cmMethod } else { cmPkg + "/" + cmClass + " " + cmMethod }
        let line: String = _buildHelpLine(cmKey, cmd0)
        sb.append("    _out(\"")
        _appendEscapedForHelp(sb, line)
        sb.append("\")\n")
        cmIdx++
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
    // Emit _runClassName_methodName for each class method
    cmIdx = 0
    while (cmIdx < classMethodClassNames.size) {
        let cmClass: String = classMethodClassNames.get(cmIdx).getOrThrow()
        let cmMethod: String = classMethodNames.get(cmIdx).getOrThrow()
        let cmOverloads: ArrayList<CommandInfo> = classMethodOverloadsList.get(cmIdx).getOrThrow()
        _emitRunCommand(sb, cmClass + "_" + cmMethod, cmOverloads)
        cmIdx++
    }

    sb.toString()
}

// Append package name without newlines (so generated source is one line)
func _appendPkgSanitized(sb: StringBuilder, pkg: String): Unit {
    var i: Int64 = 0
    while (i < pkg.size) {
        let c: Int64 = Int64(pkg.get(i).getOrThrow())
        if (c != 10 && c != 13) { sb.append(Rune(UInt32(c))) }
        i++
    }
}

// Append string content escaped for use inside a Cangjie double-quoted string literal
func _appendEscapedForHelp(sb: StringBuilder, s: String): Unit {
    var i: Int64 = 0
    while (i < s.size) {
        let c: Byte = s.get(i).getOrThrow()
        if (c == 34) { sb.append("\\"); sb.append(Rune(UInt32(34))) }
        else if (c == 92) { sb.append("\\"); sb.append(Rune(UInt32(92))) }
        else { sb.append(Rune(UInt32(c))) }
        i++
    }
}

// Build one help line: "`key` new _name_ _id_ where _name_ : `String`, _id_ : `Int64`" (backticks = monospace, underscores = italics)
func _buildHelpLine(key: String, cmd: CommandInfo): String {
    let lineSb: StringBuilder = StringBuilder()
    lineSb.append("`")
    lineSb.append(key)
    lineSb.append("`")
    if (cmd.isConstructor) {
        lineSb.append(" new")
    }
    if (cmd.isInstanceMethod || cmd.isStaticMethod) {
        // no " new" for class methods
    }
    if (cmd.params.size > 0) {
        var pi: Int64 = 0
        while (pi < cmd.params.size) {
            let p: ParamInfo = cmd.params.get(pi).getOrThrow()
            lineSb.append(" _")
            lineSb.append(p.paramName)
            lineSb.append("_")
            pi++
        }
        lineSb.append(" where")
        var first: Bool = true
        pi = 0
        while (pi < cmd.params.size) {
            let p: ParamInfo = cmd.params.get(pi).getOrThrow()
            if (!first) { lineSb.append(",") }
            lineSb.append(" _")
            lineSb.append(p.paramName)
            lineSb.append("_ : `")
            lineSb.append(p.paramType)
            lineSb.append("`")
            first = false
            pi++
        }
    }
    lineSb.toString()
}

func _emitPathHelpers(sb: StringBuilder, knownPaths: ArrayList<String>): Unit {
    sb.append("func _substring(s: String, start: Int64, end: Int64): String {\n")
    sb.append("    let sb: StringBuilder = StringBuilder()\n")
    sb.append("    var i: Int64 = start\n")
    sb.append("    while (i < end && i < s.size) {\n")
    sb.append("        sb.append(Rune(UInt32(s.get(i).getOrThrow())))\n")
    sb.append("        i++\n")
    sb.append("    }\n")
    sb.append("    sb.toString()\n")
    sb.append("}\n\n")
    sb.append("func _pathSegments(pathStr: String): ArrayList<String> {\n")
    sb.append("    let result: ArrayList<String> = ArrayList<String>()\n")
    sb.append("    var start: Int64 = 0\n")
    sb.append("    var i: Int64 = 0\n")
    sb.append("    while (i <= pathStr.size) {\n")
    sb.append("        if (i == pathStr.size || Int64(pathStr.get(i).getOrThrow()) == 47) {\n")
    sb.append("            if (i > start) { result.add(all: [_substring(pathStr, start, i)]) }\n")
    sb.append("            start = i + 1\n")
    sb.append("        }\n")
    sb.append("        i++\n")
    sb.append("    }\n")
    sb.append("    if (start < pathStr.size) { result.add(all: [_substring(pathStr, start, pathStr.size)]) }\n")
    sb.append("    result\n")
    sb.append("}\n\n")
    sb.append("func _normalizePath(pathToken: String, cwd: String): Option<String> {\n")
    sb.append("    let segs: ArrayList<String> = _pathSegments(pathToken)\n")
    sb.append("    if (segs.size == 0) { return Option<String>.Some(cwd) }\n")
    sb.append("    let fromRoot: Bool = pathToken.size > 0 && pathToken.get(0).getOrThrow() == 47\n")
    sb.append("    var list: ArrayList<String> = ArrayList<String>()\n")
    sb.append("    if (fromRoot) {\n")
    sb.append("        var i: Int64 = 0\n")
    sb.append("        while (i < segs.size) {\n")
    sb.append("            let s: String = segs.get(i).getOrThrow()\n")
    sb.append("            if (s == \".\") { }\n")
    sb.append("            else if (s == \"..\") {\n")
    sb.append("                if (list.size > 0) {\n")
    sb.append("                    let newList: ArrayList<String> = ArrayList<String>()\n")
    sb.append("                    var idx: Int64 = 0\n")
    sb.append("                    while (idx < list.size - 1) { newList.add(all: [list.get(idx).getOrThrow()]); idx++ }\n")
    sb.append("                    list = newList\n")
    sb.append("                } else { return Option<String>.None }\n")
    sb.append("            }\n")
    sb.append("            else if (s.size > 0) { list.add(all: [s]) }\n")
    sb.append("            i++\n")
    sb.append("        }\n")
    sb.append("    } else {\n")
    sb.append("        let cwdSegs: ArrayList<String> = _pathSegments(cwd)\n")
    sb.append("        var ci: Int64 = 0\n")
    sb.append("        while (ci < cwdSegs.size) { list.add(all: [cwdSegs.get(ci).getOrThrow()]); ci++ }\n")
    sb.append("        var i: Int64 = 0\n")
    sb.append("        while (i < segs.size) {\n")
    sb.append("            let s: String = segs.get(i).getOrThrow()\n")
    sb.append("            if (s == \".\") { }\n")
    sb.append("            else if (s == \"..\") {\n")
    sb.append("                if (list.size > 0) {\n")
    sb.append("                    let newList: ArrayList<String> = ArrayList<String>()\n")
    sb.append("                    var idx: Int64 = 0\n")
    sb.append("                    while (idx < list.size - 1) { newList.add(all: [list.get(idx).getOrThrow()]); idx++ }\n")
    sb.append("                    list = newList\n")
    sb.append("                } else { return Option<String>.None }\n")
    sb.append("            }\n")
    sb.append("            else if (s.size > 0) { list.add(all: [s]) }\n")
    sb.append("            i++\n")
    sb.append("        }\n")
    sb.append("    }\n")
    sb.append("    if (list.size == 0) { return Option<String>.Some(\"/\") }\n")
    sb.append("    var joined: String = list.get(0).getOrThrow()\n")
    sb.append("    var j: Int64 = 1\n")
    sb.append("    while (j < list.size) { joined = joined + \"/\" + list.get(j).getOrThrow(); j++ }\n")
    sb.append("    Option<String>.Some(joined)\n")
    sb.append("}\n\n")
    sb.append("func _isKnownPath(p: String): Bool {\n")
    var pi: Int64 = 0
    while (pi < knownPaths.size) {
        let kp: String = knownPaths.get(pi).getOrThrow()
        sb.append("    if (p == \"")
        _appendEscapedForHelp(sb, kp)
        sb.append("\") { return true }\n")
        pi++
    }
    sb.append("    false\n")
    sb.append("}\n\n")
}

func _buildKnownPaths(manifest: Manifest): ArrayList<String> {
    let result: ArrayList<String> = ArrayList<String>()
    result.add(all: ["/"])
    var ci: Int64 = 0
    while (ci < manifest.commands.size) {
        let p: String = manifest.commands.get(ci).getOrThrow().packagePath
        var found: Bool = false
        var r: Int64 = 0
        while (r < result.size) {
            if (result.get(r).getOrThrow() == p) { found = true; break }
            r++
        }
        if (!found && p.size > 0) { result.add(all: [p]) }
        ci++
    }
    result
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
        sb.append("        _err(\"Usage: ")
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

    sb.append("    _err(\"No matching overload for ")
    sb.append(key)
    sb.append(" with \" + _formatArgTypes(")
    if (needNew) { sb.append("actualArgs") } else { sb.append("args") }
    sb.append("))\n")
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
            sb.append(")) { case Option<Int64>.Some(x) => Option<Option<Int64>>.Some(Option<Int64>.Some(x)); case _ => Option<Option<Int64>>.None })")
        } else if (inner == "Float64") {
            sb.append("(match (Float64.tryParse(")
            sb.append(argExpr)
            sb.append(")) { case Option<Float64>.Some(x) => Option<Option<Float64>>.Some(Option<Float64>.Some(x)); case _ => Option<Option<Float64>>.None })")
        } else if (inner == "Bool") {
            sb.append("(match (Bool.tryParse(")
            sb.append(argExpr)
            sb.append(")) { case Option<Bool>.Some(x) => Option<Option<Bool>>.Some(Option<Bool>.Some(x)); case _ => Option<Option<Bool>>.None })")
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
        sb.append(")) { case Option<Int64>.Some(id) => match (_getRef(id)) { case Option<Any>.Some(o) => o as ")
        sb.append(paramType)
        sb.append(" ; case _ => Option<")
        sb.append(paramType)
        sb.append(">.None } ; case _ => Option<")
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
    let needResult: Bool = cmd.returnIsRef || (cmd.returnType != "Unit")
    if (isConstructor) {
        if (needResult) { sb.append("let _result = ") }
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
    } else if (cmd.isInstanceMethod) {
        if (needResult) { sb.append("let _result = ") }
        sb.append("((_v0.getOrThrow() as ")
        sb.append(cmd.className)
        sb.append(").getOrThrow()).")
        sb.append(cmd.name)
        sb.append("(")
        var first: Bool = true
        var pi: Int64 = 1
        while (pi < n) {
            if (!first) { sb.append(", ") }
            sb.append("_v")
            sb.append(pi.toString())
            sb.append(".getOrThrow()")
            first = false
            pi++
        }
        sb.append(")\n            ")
    } else if (cmd.isStaticMethod) {
        if (needResult) { sb.append("let _result = ") }
        sb.append(cmd.className)
        sb.append(".")
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
    } else {
        if (needResult) { sb.append("let _result = ") }
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
        sb.append("let _id = _storeRef(_result)\n            _out(\"ref:\" + _id.toString())\n            return 0\n")
    } else if (cmd.returnType == "Unit") {
        sb.append("return 0\n")
    } else {
        sb.append("_out(_result.toString())\n            return 0\n")
    }
}
