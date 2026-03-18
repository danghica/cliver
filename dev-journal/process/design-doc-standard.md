# Design 文档标准

> 每个 feature 的 `design.md` 必须遵循这个标准。
> 这份标准的目标是：design.md 既能被人类开发者读懂，
> 也能被测试 agent 机械地转化为完整的测试用例，不依赖隐含知识。

---

## 为什么需要这个标准

普通的设计文档对人类有效，但对测试 agent 存在两类问题：

**隐含知识**：写"filename 会被安全处理"，人类知道要测路径注入，agent 不一定知道。
**副作用缺失**：写"upload 返回路径"，没有写"文件实际写入磁盘"——测试 agent 不会写不变量测试。

标准模板通过强制 `## Testable Behaviors` 章节解决这两个问题。

---

## 文档 frontmatter（必填）

每个 `design.md` 开头必须有：

```markdown
---
feature: <功能名称>
spec_version: 1.0
date: YYYY-MM-DD
status: draft | final
---
```

**`spec_version` 递增规则**：
- Patch（1.0 → 1.0 不变）：修改措辞、补充说明、修正错别字
- Minor（1.0 → 1.1）：新增可选字段、新增非破坏性行为
- Major（1.0 → 2.0）：修改现有字段含义、改变错误响应格式、移除行为

`spec_version` 一旦测试仓同步后发生 Minor 或 Major 变更，必须重新走 Agent A + Agent B 流程。

---

## 文档章节结构（必填章节标 *）

```
## Problem *          ← 这个 feature 解决什么问题
## Decision *         ← 选择了什么方案，以及为什么不选其他方案
## Scope *            ← 在范围内 / 不在范围内（防 scope creep）
## Protocol *         ← 消息格式（针对协议类 feature）
## Testable Behaviors *  ← 测试 agent 的主要信息来源（见下方格式）
## Security Constraints  ← 安全边界（如果有）
## Known Limitations     ← 已知不支持的情况（测试仓不测这些）
```

---

## `## Testable Behaviors` 章节格式

这是最关键的章节。**每个操作用固定格式描述**，测试 agent 可以机械地把每一个条目转化为一个测试用例。

### 格式模板

````markdown
## Testable Behaviors

### <操作名>

**Input fields:**
| Field | Type | Required | Constraints |
|-------|------|----------|-------------|
| field1 | string | yes | non-empty, max 255 chars |
| field2 | string | yes | valid base64 encoding |

**Success output:**
| Field | Type | Value constraints |
|-------|------|------------------|
| type | string | equals "operation_result" |
| path | string | starts with "/tmp/cliver/uploads/", non-empty |

**Side effects:**（← Type B 不变量测试的来源）
- 文件实际写入 `path` 所指位置
- 文件内容字节等于 base64 解码后的 `data`
- 目录 `/tmp/cliver/uploads/` 在不存在时自动创建

**Invariants:**（← 必须在测试中直接验证的属性，不只信任返回值）
- `fs.existsSync(path) === true`
- `fs.readFileSync(path)` 字节等于 `Buffer.from(data, 'base64')`

**Error conditions:**（← Type C 对抗性测试的来源）
| Condition | Response |
|-----------|----------|
| `filename` 缺失或非 string | `{ type: "upload_error", message: "..." }` |
| `data` 缺失或非 string | `{ type: "upload_error", message: "..." }` |
| 写入失败（磁盘满等） | `{ type: "upload_error", message: <系统错误信息> }` |

**Input boundary cases:**（← 边界值，显式列出）
| Input | Expected behavior |
|-------|------------------|
| `filename` 包含路径分隔符（`../`、`/`） | 路径分隔符被 sanitize，不写入上级目录 |
| `filename` 为空字符串 | [明确说明期望行为，不留空白] |
| `data` 为空字符串 | 写入 0 字节文件 |
| `data` 包含无效 base64 字符 | [明确说明：静默写入 or 报错] |
````

### 关键原则

1. **副作用必须显式写出**，不能用"处理文件"这种模糊描述。Side effects 章节是 Type B 不变量测试的直接来源。

2. **Error conditions 必须穷举**。不能只写"参数无效时报错"，必须列出每种无效情况对应的响应格式。

3. **Input boundary cases 不能留空白**。如果一个边界情况的行为"未定义"，必须明确写"未定义，不测试"，而不是省略。这防止测试 agent 凭空猜测。

4. **Response 格式要精确到字段级别**，不能只写"返回错误对象"。

---

## 示例：upload-download feature 的 Testable Behaviors

这是 `features/2026-03-17-upload-download/design.md` 应该补充的章节（当前版本缺失此结构）：

````markdown
---
feature: upload-download
spec_version: 1.0
date: 2026-03-17
status: final
---

## Testable Behaviors

### upload

**Input fields:**
| Field | Type | Required | Constraints |
|-------|------|----------|-------------|
| type | string | yes | equals "upload" |
| filename | string | yes | non-empty string |
| data | string | yes | string（base64 编码内容） |

**Success output:**
| Field | Type | Value constraints |
|-------|------|------------------|
| type | string | equals "upload_result" |
| path | string | starts with "/tmp/cliver/uploads/", 格式为 `<timestamp>_<random>_<sanitized_filename>` |

**Side effects:**
- 目录 `/tmp/cliver/uploads/` 不存在时自动创建
- 文件以 `Buffer.from(data, 'base64')` 写入 `path`
- 操作记录写入 server 日志

**Invariants:**
- `fs.existsSync(path) === true`（文件必须真实存在于磁盘）
- `fs.readFileSync(path)` 字节等于 `Buffer.from(data, 'base64')`

**Error conditions:**
| Condition | Response |
|-----------|----------|
| `filename` 缺失 | `{ type: "upload_error", message: "Invalid upload request: filename and data are required" }` |
| `filename` 非 string | `{ type: "upload_error", message: "Invalid upload request: filename and data are required" }` |
| `data` 缺失 | `{ type: "upload_error", message: "Invalid upload request: filename and data are required" }` |
| `data` 非 string | `{ type: "upload_error", message: "Invalid upload request: filename and data are required" }` |
| 写入失败 | `{ type: "upload_error", message: <e.message> }` |

**Input boundary cases:**
| Input | Expected behavior |
|-------|------------------|
| `filename` 含路径分隔符（如 `"../../evil.sh"`） | `path.basename()` 截断，写入 `evil.sh` 对应的 sanitized 名称，不写入上级目录 |
| `filename` 为空字符串 `""` | `path.basename("")` 返回 `"."`，sanitized 为 `"."`，文件写入成功（spec 未明确禁止） |
| `data` 为空字符串 `""` | 写入 0 字节文件，返回 `upload_result` |
| `data` 含无效 base64 字符 | Node.js Buffer 静默忽略无效字符写入，返回 `upload_result`（已知行为，不报错） |

---

### download

**Input fields:**
| Field | Type | Required | Constraints |
|-------|------|----------|-------------|
| type | string | yes | equals "download" |
| path | string | yes | non-empty string |

**Success output:**
| Field | Type | Value constraints |
|-------|------|------------------|
| type | string | equals "download_result" |
| filename | string | 等于 `path.basename(path)` |
| data | string | 文件内容的 base64 编码 |

**Side effects:**
- 无（只读操作）

**Invariants:**
- `Buffer.from(data, 'base64')` 字节等于请求路径文件的实际内容

**Security constraints:**
- `path.resolve(msg.path)` 必须以 `/tmp/cliver/` 开头，否则拒绝
- 覆盖范围：绝对路径指向其他目录（`/etc/passwd`），含 `..` 的绝对路径（`/tmp/cliver/../../etc/passwd`），相对路径（`../../etc/passwd`）

**Error conditions:**
| Condition | Response |
|-----------|----------|
| `path` 缺失或非 string | `{ type: "download_error", message: "Invalid download request: path is required" }` |
| 路径安全检查失败 | `{ type: "download_error", message: "Access denied: path must be under /tmp/cliver/" }` |
| 文件不存在 | `{ type: "download_error", message: <e.message>（系统错误）}` |
| 文件读取失败 | `{ type: "download_error", message: <e.message> }` |

**Input boundary cases:**
| Input | Expected behavior |
|-------|------------------|
| `path` = `/etc/passwd` | 路径安全检查失败，返回 `download_error` |
| `path` = `../../etc/passwd`（相对路径） | `path.resolve` 后不以 `/tmp/cliver/` 开头，返回 `download_error` |
| `path` = `/tmp/cliver/../etc/passwd` | `path.resolve` 后为 `/tmp/etc/passwd`，不以 `/tmp/cliver/` 开头，返回 `download_error` |
| `path` = `/tmp/cliver_evil/file`（前缀相似但不同）| `path.resolve` 后不以 `/tmp/cliver/` 开头，返回 `download_error` |
| `path` 指向存在的文件 | 正常返回 `download_result` |
| `path` 指向不存在的文件 | 返回 `download_error` |
````

---

## 检查清单：design.md 完成标准

在把 design.md 标记为 `status: final` 之前，用这个清单验证：

```
[ ] frontmatter 有 spec_version、date、status 字段
[ ] ## Testable Behaviors 章节存在
[ ] 每个操作都有 Input fields 表格（含类型和约束）
[ ] 每个操作都有 Side effects 章节（只读操作明确写"无"）
[ ] 每个操作都有 Invariants 章节（副作用可验证的属性）
[ ] 每个操作都有 Error conditions 表格（穷举，不遗漏）
[ ] 每个操作都有 Input boundary cases 表格（无歧义，不留空白）
[ ] Known Limitations 章节列出了不测试的情况
```

---

## Doc Reviewer A：格式与可读性检查

**信息边界：** 只看本文档（`design-doc-standard.md`）+ 草稿 `design.md`。
不看实现代码、impl.md、任何其他文档。

**Prompt 模板（verbatim，替换 `[DRAFT]`）：**

```
你是一个设计文档格式审查员。你的任务是找出格式和可读性问题，不评估内容正确性。

## 你的信息来源

1. 格式规范（见下方 STANDARD）
2. 待审查的草稿文档（见下方 DRAFT）

## 检查维度

对草稿文档的每个章节，检查：

**结构完整性：**
- frontmatter 是否有 spec_version、date、status 字段？
- 所有必填章节是否存在（Problem、Decision、Scope、Testable Behaviors、Known Limitations）？
- 每个操作是否有完整的子章节（Input fields、Side effects、Invariants、Error conditions、Input boundary cases）？

**表格格式：**
- Input fields 表格是否有 Field、Type、Required、Constraints 四列？
- Error conditions 表格是否有 Condition、Response 两列？
- Input boundary cases 表格是否有 Input、Expected behavior 两列？

**可读性：**
- 是否存在模糊描述（如"处理错误"、"安全处理"，而没有具体说明是什么错误/什么安全措施）？
- Side effects 章节是否只写了"返回结果"（返回值不是 side effect），而遗漏了真正的副作用（文件写入、状态变更等）？
- Input boundary cases 是否有空白行（某行的 Expected behavior 是空的或"未定义"但没有明确说明）？

**一致性：**
- 文档中是否有相互矛盾的描述（如 Protocol 章节和 Testable Behaviors 章节的字段定义不一致）？

## 输出格式

只输出格式问题，不输出内容建议。格式：

### 格式问题（需修复）
- [章节/位置] 问题描述 → 应该是什么

### 可读性问题（建议修复）
- [章节/位置] 问题描述 → 建议改为什么

### 通过
- [章节] 符合规范

---

STANDARD:
[粘贴 design-doc-standard.md 的"文档 frontmatter"到"检查清单"章节]

DRAFT:
[粘贴草稿 design.md 的完整内容]
```

**输出处理：** 作者按"格式问题"逐条修复，"可读性问题"酌情修复，然后进入 Doc Reviewer B。

---

## Doc Reviewer B：内容与可测试性检查

**信息边界：** 只看格式修复后的 `design.md`。
不看 `design-doc-standard.md`（避免被格式规范锚定而忽略内容问题）、不看实现代码、不看 impl.md。

**Prompt 模板（verbatim，替换 `[DESIGN]`）：**

```
你是一个设计文档内容审查员。你的任务是从"测试工程师"的视角审查这份设计文档，
找出内容上的问题——不是格式问题，而是让这份文档难以据此写出可靠测试的内容问题。

## 你的信息来源

只有待审查的设计文档（见下方 DESIGN）。
你不知道这个功能的实现方式，也不应该猜测。

## 检查维度

**内部一致性：**
- Protocol 章节描述的消息格式，是否与 Testable Behaviors 里的字段定义一致？
- 如果文档里同一个字段在不同地方有不同的描述，哪个是准确的？

**行为的可测试性：**
- 每个 Error condition 的触发条件，是否精确到可以直接构造一个测试输入？
  （"参数无效"不够精确；"filename 字段类型不是 string"足够精确）
- 每个 Invariant，是否描述了一个可以用代码验证的属性？
  （"文件被安全存储"不可测；"fs.existsSync(path) === true"可测）
- 每个 Input boundary case 的 Expected behavior，是否无歧义？
  （"行为未定义"是歧义；"写入 0 字节文件，返回 upload_result"是无歧义）

**边界的完整性：**
- Error conditions 表格，是否覆盖了 Input fields 里每个 Required 字段的缺失情况？
- Input boundary cases，是否覆盖了每个字段的类型边界（空字符串、null、错误类型）？
- 如果存在安全约束，边界情况是否覆盖了常见绕过方式（路径穿越、类型混淆等）？

**Side effects 的完整性：**
- 对于会修改系统状态的操作，Side effects 章节是否列出了所有状态变更？
- 是否有隐含的副作用没有被写出来（如日志写入、目录创建、缓存更新）？

**Known Limitations 的诚实性：**
- 文档中是否有"期望行为"实际上是"已知缺陷"？
  （如"静默忽略无效输入"是一个设计决策，还是一个未处理的情况？）

## 输出格式

### 内容问题（需在实现前修复）
- [操作/章节] 问题描述 → 建议如何修改

### 可测试性问题（测试 agent 会遇到困难的地方）
- [操作/Invariant 或 Error condition] 问题描述 → 建议更精确的描述

### 内容疑问（需要作者澄清，不是明确错误）
- [操作/章节] 疑问描述

### 通过
- [章节] 无内容问题

---

DESIGN:
[粘贴格式修复后的 design.md 完整内容]
```

**输出处理：** 作者按"内容问题"和"可测试性问题"修复，"内容疑问"做出明确决策并写入文档，然后标记 `status: final`。
