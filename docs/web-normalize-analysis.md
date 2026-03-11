# Analysis: Why Web Line Normalization Still Fails (Multi-line Input)

## What the log shows

- **Input logged (after `normalizeWebLine(line)`):**  
  `"Student new Alice 100 ; \nStudent new Alicea 1001"`  
  So the string still contains a literal newline character when written to the log.

- **Stderr:**  
  `"Unknown command: \nStudent"`  
  So the runner still sees a newline and the second “command” is `\nStudent`.

So `normalizeWebLine` is not replacing newline characters with spaces. The comparison that should detect `\n` and `\r` is never matching.

---

## Root cause: escaping in the generated JavaScript

The backend template lives in **Cangjie** (`src/main.cj`). The template is a Cangjie string that gets written as the contents of `web/cli_ws_server.js`.

The template contains:

```text
"      if (c === '\\\\n' || c === '\\\\r') out += ' ';\n"
```

So in the **Cangjie** string we have the substring `'\\\\n'` (and `'\\\\r'`).

- In Cangjie, `\\` is likely one backslash in the string value.
- So `\\\\n` is interpreted as: `\\` → one `\`, then `\\` → one `\`, then `n` → **three characters** in the template value: `\`, `\`, `n`.

When that template string is written to `cli_ws_server.js`, the generated file therefore contains the **two** characters backslash and `n` inside the quotes:

```js
if (c === '\n' || c === '\r') out += ' ';
```

Here, in the **generated** file, the source is literally: quote, backslash, backslash, `n`, quote. In JavaScript that string literal is **not** the newline character; it is the **two-character** string consisting of backslash (code 92) and `n` (code 110).

So at runtime:

- `c = s.charAt(i)` is the **actual** newline character (code 10) when the user input contains a newline.
- The condition compares it to the string `'\n'` as emitted, which in the generated file is the two-character string `(92, 110)`.
- So `c === '\n'` is **always false** for a real newline. The same holds for `'\r'`.
- So the loop never replaces newlines with spaces; they stay in the string.
- The normalized line is then passed to the process and logged; the log still shows `\n` in the JSON, and the runner still sees a newline and produces "Unknown command: \nStudent".

So the bug is: **the way the template is escaped in Cangjie causes the generated JavaScript to compare against the wrong value (two-character `\` + `n` instead of the newline character).**

---

## Fix (conceptual; do not implement here)

Avoid using the escape sequences `\n` and `\r` in the **generated** JavaScript at all. Then no backslash escaping in the template can break the check.

In the generated `normalizeWebLine`, detect newline and carriage return by **numeric character code**:

- Replace the condition  
  `if (c === '\n' || c === '\r')`  
  with something that does not depend on string escapes, for example:  
  `if (c.charCodeAt(0) === 10 || c.charCodeAt(0) === 13)`  
  (10 = LF, 13 = CR).

In the Cangjie template, emit that condition as a fixed string with digits only (e.g. `"      if (c.charCodeAt(0) === 10 || c.charCodeAt(0) === 13) out += ' ';\n"`). No `\n` or `\r` in the generated code, so the behaviour is correct regardless of how Cangjie or the file write step handle backslashes.

No other change to the normalization logic is required; only the way newline/CR are detected in the generated JS needs to use character codes instead of literal `'\n'`/`'\r'`.
