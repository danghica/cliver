# 测试仓搭建落地方案

> 本文档说明如何搭建 `cliver-tests` 独立测试仓，以及两个 agent 的运行方式。
> 策略背景见 [`testing-strategy.md`](testing-strategy.md)。
> design 文档写作规范见 [`design-doc-standard.md`](design-doc-standard.md)。

---

## 仓库位置（固定记录，不依赖历史记录）

```
实现仓：/home/gloria/tianyue/cliver/
测试仓：/home/gloria/tianyue/cliver-tests/
```

两仓始终在同一父目录 `/home/gloria/tianyue/` 下，相对路径 `../cliver` / `../cliver-tests` 在任何脚本中都有效。

---

## 整体结构

```
~/tianyue/
├── cliver/              ← 实现仓
│   └── dev-journal/features/*/design.md  ← spec 来源（只读方向）
└── cliver-tests/        ← 测试仓
    ├── specs/           ← 同步来的 design.md（只读，不在这里修改）
    ├── backend/         ← WebSocket 协议测试
    ├── fixtures/        ← Parser fixture 库
    ├── gap-reports/     ← Agent B 的输出
    ├── mutation-log.md  ← Mutation verification 记录
    ├── sync-specs.sh    ← spec 同步（含完整性校验）
    └── run_tests.sh     ← 统一测试入口（含 spec 新鲜度检查）
```

两仓通信机制：
- **规格同步**（单向，手动触发）：`cliver/dev-journal/features/*/design.md` → `cliver-tests/specs/`，通过 `sync-specs.sh` + MANIFEST 保证完整性
- **构建产物**（运行时引用）：env var 指向 `cliver/sample_cangjie_package/target/`

---

## Step 1：创建测试仓

```bash
cd /home/gloria/tianyue
mkdir cliver-tests && cd cliver-tests
git init
```

---

## Step 2：sync-specs.sh（含 MANIFEST 写入）

`sync-specs.sh` 在同步时写入 `specs/MANIFEST.json`，记录每个 spec 的 sha256 + spec_version + 时间戳。`run_tests.sh` 在启动前用 MANIFEST 验证同步状态。

**只同步 `design.md`，不同步 `impl.md`**：impl 文档记录了实现过程和已知问题，暴露给测试 agent 会引入相关性。

```bash
#!/usr/bin/env bash
# sync-specs.sh
# 用法：CLIVER_REPO=/path/to/cliver ./sync-specs.sh
set -e

CLIVER_REPO="${CLIVER_REPO:-/home/gloria/tianyue/cliver}"
SPECS_DIR="$(cd "$(dirname "$0")" && pwd)/specs"
MANIFEST="$SPECS_DIR/MANIFEST.json"

if [ ! -d "$CLIVER_REPO/dev-journal/features" ]; then
  echo "Error: $CLIVER_REPO/dev-journal/features not found"
  echo "Expected implementation repo at: $CLIVER_REPO"
  exit 1
fi

mkdir -p "$SPECS_DIR"

# 开始写 MANIFEST（JSON array）
echo "[" > "$MANIFEST.tmp"
first=1

for design in "$CLIVER_REPO"/dev-journal/features/*/design.md; do
  [ -f "$design" ] || continue
  feature_dir=$(basename "$(dirname "$design")")
  dest="$SPECS_DIR/${feature_dir}.md"
  cp "$design" "$dest"

  # 计算 sha256
  sha=$(sha256sum "$design" | awk '{print $1}')

  # 提取 spec_version（从 frontmatter）
  spec_version=$(grep '^spec_version:' "$design" | head -1 | awk '{print $2}' || echo "unknown")

  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  [ "$first" = "0" ] && echo "," >> "$MANIFEST.tmp"
  cat >> "$MANIFEST.tmp" <<EOF
  {
    "feature": "${feature_dir}",
    "source": "${design}",
    "dest": "${dest}",
    "spec_version": "${spec_version}",
    "sha256": "${sha}",
    "synced_at": "${ts}"
  }
EOF
  first=0
  echo "Synced: $dest (spec_version=${spec_version})"
done

echo "]" >> "$MANIFEST.tmp"
mv "$MANIFEST.tmp" "$MANIFEST"

echo ""
echo "MANIFEST written: $MANIFEST"
echo "Specs synced from $CLIVER_REPO"
```

---

## Step 3：run_tests.sh（含 spec 新鲜度检查）

测试入口在运行测试前先检查：MANIFEST 是否存在，以及源文件的 sha256 是否与 MANIFEST 一致。如果 design.md 自上次 sync 后有变动，报错并要求重新同步。

```bash
#!/usr/bin/env bash
# run_tests.sh
# 环境变量：
#   CLIVER_REPO        实现仓路径（默认 /home/gloria/tianyue/cliver）
#   WS_SERVER   WebSocket server 路径（默认 <CLIVER_REPO>/sample_cangjie_package/web/cli_ws_server.js）
#   CLI_BIN            CLI binary 路径（默认 <CLIVER_REPO>/sample_cangjie_package/target/release/bin/main）
#   SKIP_FRESHNESS     设为 1 跳过新鲜度检查（调试用）
set -e

CLIVER_REPO="${CLIVER_REPO:-/home/gloria/tianyue/cliver}"
WS_SERVER="${WS_SERVER:-$CLIVER_REPO/sample_cangjie_package/web/cli_ws_server.js}"
CLI_BIN="${CLI_BIN:-$CLIVER_REPO/sample_cangjie_package/target/release/bin/main}"
SPECS_DIR="$(cd "$(dirname "$0")" && pwd)/specs"
MANIFEST="$SPECS_DIR/MANIFEST.json"

echo "=== cliver-tests ==="
echo "CLIVER_REPO:  $CLIVER_REPO"
echo "CLI_BIN:      $CLI_BIN"
echo "WS_SERVER:    $WS_SERVER"
echo ""

# --- Spec 新鲜度检查 ---
if [ "${SKIP_FRESHNESS:-0}" != "1" ]; then
  if [ ! -f "$MANIFEST" ]; then
    echo "ERROR: specs/MANIFEST.json not found."
    echo "Run sync-specs.sh first: CLIVER_REPO=$CLIVER_REPO ./sync-specs.sh"
    exit 1
  fi

  stale=0
  # 用 node 读 MANIFEST 并验证 sha256（避免依赖 jq）
  node - <<'JSEOF'
const fs = require('fs');
const crypto = require('crypto');
const manifest = JSON.parse(fs.readFileSync('specs/MANIFEST.json', 'utf8'));
let stale = false;
for (const entry of manifest) {
  if (!fs.existsSync(entry.source)) continue;
  const current = crypto.createHash('sha256').update(fs.readFileSync(entry.source)).digest('hex');
  if (current !== entry.sha256) {
    console.error(`STALE SPEC: ${entry.feature}`);
    console.error(`  Source has changed since last sync: ${entry.source}`);
    console.error(`  spec_version at sync: ${entry.spec_version}`);
    console.error(`  Re-run: CLIVER_REPO=${process.env.CLIVER_REPO || '../cliver'} ./sync-specs.sh`);
    console.error(`  Then re-run Agent A for this feature.`);
    stale = true;
  }
}
if (stale) process.exit(1);
console.log('Spec freshness: OK');
JSEOF
fi

# --- 依赖检查 ---
if [ ! -f "$CLI_BIN" ]; then
  echo "Error: CLI binary not found at $CLI_BIN"
  echo "Run 'cd $CLIVER_REPO/sample_cangjie_package && cjpm build' first."
  exit 1
fi

if [ ! -d node_modules/ws ]; then
  echo "Installing ws..."
  npm install ws
fi

# --- 运行测试 ---
echo ""
echo "=== Backend Protocol Tests ==="
CLI_BIN="$CLI_BIN" WS_SERVER="$WS_SERVER" node backend/test_protocol.js

echo ""
echo "=== All tests passed ==="
```

---

## Step 4：test_protocol.js 的结构原则

### 4a. Server 路径使用 env var

```js
const serverPath = process.env.WS_SERVER;
if (!serverPath) {
  console.error('WS_SERVER env var required');
  process.exit(1);
}
```

### 4b. 每个测试的 name 格式

```
[feature][type] 行为描述
```

`type` 取值：`spec`（规格测试）、`invariant`（不变量）、`security`（安全）、`error`（错误路径）、`boundary`（边界值）

这个格式让 Agent B 的 gap review 可操作——直接提取 name 列表，逐条对照 spec。

```js
const uploadTests = [
  { name: '[upload][spec] valid file → upload_result with path under /tmp/cliver/uploads/', ... },
  { name: '[upload][invariant] file exists on disk after upload', ... },
  { name: '[upload][invariant] file content bytes match base64-decoded data', ... },
  { name: '[upload][error] missing data field → upload_error', ... },
  { name: '[upload][error] missing filename field → upload_error', ... },
  { name: '[upload][boundary] filename with path separators → sanitized, no directory traversal', ... },
  { name: '[upload][boundary] empty data → 0-byte file written', ... },
];

const downloadTests = [
  { name: '[download][spec] existing file → download_result with base64 data', ... },
  { name: '[download][invariant] decoded data matches file on disk', ... },
  { name: '[download][security] /etc/passwd → download_error', ... },
  { name: '[download][security] relative traversal ../../etc/passwd → download_error', ... },
  { name: '[download][security] /tmp/cliver/../etc/passwd → download_error', ... },
  { name: '[download][security] /tmp/cliver_evil/file → download_error', ... },
  { name: '[download][error] nonexistent file → download_error', ... },
  { name: '[download][error] missing path field → download_error', ... },
];
```

### 4c. Type B 不变量测试直接用 fs 验证副作用

```js
{
  name: '[upload][invariant] file exists on disk after upload',
  sendMsg: {
    type: 'upload',
    filename: 'invariant_test.csv',
    data: Buffer.from('a,b\n1,2').toString('base64')
  },
  check: (stdout, stderr, j) => {
    if (!j || j.type !== 'upload_result' || !j.path) return false;
    if (!fs.existsSync(j.path)) return false;           // 副作用验证
    const actual = fs.readFileSync(j.path);
    const expected = Buffer.from('a,b\n1,2');
    return actual.equals(expected);                     // 字节级不变量
  },
},
```

---

## Step 5：Agent A 和 Agent B 的运行方式

### 关于隔离

Agent A 和 Agent B 均以 subagent 形式通过 `Agent` 工具启动，是**独立的 inference 实例**（不同的 context window，不是角色扮演）。

**硬隔离方案（当前标准做法）**：把 spec 内容直接嵌入 Agent 的 prompt，agent 不需要自己去找文件读。这样 agent 没有"探索文件系统"的动机，信息边界由 prompt 结构本身决定，而不是依赖 agent 自律。

具体做法：
1. 主 session 读出 spec 文件内容
2. 将内容作为 prompt 的一部分传给 Agent A/B
3. Agent A 只需要 Write 工具（写 test_protocol.js）
4. Agent B 只需要输出文本（gap report），不需要任何文件工具

这和"去读 specs/ 目录"在流程上没有区别，但 agent 不持有开放的文件系统访问动机。

注意：agent 技术上仍然有 Read 工具（用于写测试时读测试基础设施），完全的技术强制隔离目前不可能。上述方案的有效性来自**两层保障**：
1. 嵌入式 prompt（agent 没有理由去找其他文件）
2. Agent B adversarial review（spec 出发，独立发现覆盖空白）

在 tracker.md 里记录每次 agent 运行的实际隔离方式（硬隔离 / 软隔离）。

### Agent A：Test Writer

**触发时机**：feature 的 design.md 标记为 `status: final` 并完成 sync 后。

**硬隔离启动方式**：
```bash
# 主 session 先读出 spec 内容
SPEC=$(cat /home/gloria/tianyue/cliver-tests/specs/<feature>.md)
# 然后在 Agent 工具的 prompt 中嵌入 $SPEC 内容
# Agent A 的任务：根据 spec 写测试，不需要读其他文件
```

Agent A prompt 结构（嵌入 spec，给写任务，不给"去探索"任务）：
```
以下是功能规格文档（完整内容）：

[嵌入 spec 内容]

你的任务：
- 在 cliver-tests/backend/test_protocol.js 中，根据上面的规格写协议测试
- 测试基础设施见 cliver-tests/ 目录（run_tests.sh、package.json）
- name 格式：[feature][type] 行为描述
- 不需要读 cliver/src/ 或任何实现文件
```

---

### Agent B：Adversarial Reviewer（固定 session 模板）

**每次测试后都跑**，不只在安全功能上跑。

**硬隔离启动方式**：同样嵌入 spec 内容 + name 列表，不给文件系统访问任务。

**信息边界**：
- 对应 feature 的 spec 内容（嵌入 prompt）
- 当前测试的 name 列表（嵌入 prompt，用下方命令提取）
- 不给测试代码、不给实现代码

**提取 name 列表的命令**：
```bash
cd /home/gloria/tianyue/cliver-tests
node -e "
const src = require('fs').readFileSync('backend/test_protocol.js', 'utf8');
const names = [...src.matchAll(/name:\s*'([^']+)'/g)].map(m => m[1]);
names.forEach(n => console.log(n));
"
```

**Agent B 固定 prompt 模板**（每次 verbatim 使用，只替换 `[FEATURE]` 和 `[NAME_LIST]`）：

```
你是一个测试覆盖审查员。你的任务是找出测试集的覆盖空白。

## 你的信息来源（仅此两项）

1. 功能规格文档（见下方 SPEC）
2. 当前测试的 name 列表（见下方 NAME LIST）

## 你不能做的事

- 不能看测试的具体代码
- 不能看功能的实现代码
- 不能猜测"实现里可能处理了什么"

## 你的任务

对照规格文档，用以下维度检查 name 列表：

1. **正常路径覆盖**：spec 里描述的每个成功场景，name 列表里有对应测试吗？
2. **副作用验证**：spec 的 Side effects / Invariants 章节里描述的每个副作用，有 [invariant] 类型的测试吗？
3. **错误条件覆盖**：spec 的 Error conditions 表格里每一行，有对应 [error] 测试吗？
4. **边界值覆盖**：spec 的 Input boundary cases 表格里每一行，有对应 [boundary] 测试吗？
5. **安全约束覆盖**：spec 的 Security constraints 章节里描述的每个攻击向量，有对应 [security] 测试吗？
6. **遗漏的输入空间**：哪些输入维度在 spec 里有描述但 name 列表里完全没有对应测试？

## 输出格式

只输出 gap report，不输出测试代码。格式：

### Confirmed Coverage（已覆盖）
- [spec 条目] → [对应的 test name]

### Gaps（未覆盖）
- [spec 条目] → 缺少测试，建议 name: [建议的 test name]

### Ambiguous（不确定）
- [spec 条目] → 不确定是否覆盖，原因：[说明]

---

SPEC:
[粘贴 specs/<feature>.md 的内容]

NAME LIST:
[粘贴 name 列表]
```

**Agent B 的输出保存到**：`cliver-tests/gap-reports/YYYY-MM-DD-<feature>.md`

---

## Step 6：fixture 库原则

`fixtures/` 里每个目录是一个最小 Cangjie package，测试 parser 的一个边界行为。

```
fixtures/generic_functions/
├── src/
│   └── generics.cj        ← func foo<T>(x: T): T
└── expected.json           ← { "commands": [] }
```

`expected.json` 是 Agent A 对"这个 fixture 应该产生什么 Manifest"的显式声明。人工 review 时看 `expected.json` 比看测试代码更直接——它是 fixture 的规格，不是实现。

---

## Step 7：Mutation Verification

每次对应核心逻辑变更后，在实现仓里手动执行，结果记录到 `cliver-tests/mutation-log.md`。

```bash
# 在 /home/gloria/tianyue/cliver/sample_cangjie_package/web/ 操作
# 每次 mutation：改 cli_ws_server.js → 跑测试 → 确认失败 → 恢复 → 确认恢复后全过

# Mutation 1：注释掉路径安全检查
# if (!resolved.startsWith('/tmp/cliver/')) { ... }  →  注释掉
cd /home/gloria/tianyue/cliver-tests && ./run_tests.sh 2>&1 | grep -E "FAIL|passed|failed"
# 预期：[download][security] 相关测试 FAILED
# 恢复后：./run_tests.sh  → 期望全过

# Mutation 2：绕过 path.resolve
# var resolved = msg.path;  （替换掉 path.resolve(msg.path)）
./run_tests.sh 2>&1 | grep -E "FAIL|passed|failed"
# 预期：[download][security] relative traversal FAILED
# 恢复

# Mutation 3：绕过 filename sanitize
# var sanitized = msg.filename;  （跳过 basename + regex）
./run_tests.sh 2>&1 | grep -E "FAIL|passed|failed"
# 预期：[upload][security] filename with special characters FAILED
# 恢复
```

**不要直接调用 `node backend/test_protocol.js`**——这会绕过 spec 新鲜度检查。mutation test 也用 `./run_tests.sh`，保证检查链完整。

`mutation-log.md` 格式：

```markdown
## YYYY-MM-DD <feature>

| Mutation | 预期失败的测试 | 实际 | 有效？ |
|----------|--------------|------|-------|
| 注释路径检查 | [download][security] /etc/passwd | FAILED ✓ | ✓ |
| path.resolve → msg.path | [download][security] relative traversal | FAILED ✓ | ✓ |
| 注释 sanitize | [upload][boundary] filename with separators | 未测试 | ✗ 缺口 |
```

---

## 各阶段产出物汇总

| 阶段 | 产出 | 位置 |
|------|------|------|
| Spec 同步 | `specs/<feature>.md` + `specs/MANIFEST.json` | cliver-tests |
| Agent A | `backend/test_protocol.js`、`fixtures/*/` | cliver-tests |
| Agent B | `gap-reports/YYYY-MM-DD-<feature>.md` | cliver-tests |
| Mutation | `mutation-log.md` | cliver-tests |
| 结论归档 | `impl.md` 的 known gaps | cliver/dev-journal/features/ |

---

## 完整执行顺序（每个 feature）

```bash
# 1. 实现仓：design.md 完成，标记 status: final，更新 spec_version
# （检查 design-doc-standard.md 完成清单）

# 2. 测试仓：同步 spec
cd /home/gloria/tianyue/cliver-tests
CLIVER_REPO=/home/gloria/tianyue/cliver ./sync-specs.sh

# 3. 测试仓：Agent A 在 cliver-tests/ 下运行，只读 specs/，写测试

# 4. 测试仓：提取 name 列表，运行 Agent B（用固定 prompt 模板）
node -e "..." > /tmp/names.txt
# → 输出 gap-reports/YYYY-MM-DD-<feature>.md

# 5. 人工决策：看 gap report，决定哪些 gap 必须补（P1/P2），哪些可接受（P3）

# 6. 补充测试（如有 P1/P2 gap）

# 7. 运行全量测试（含新鲜度检查）
./run_tests.sh

# 8. Mutation verification（手动，关键逻辑）

# 9. 实现仓：在 impl.md 记录 known gaps 结论
```
