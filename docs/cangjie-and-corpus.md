# Cangjie and corpus

This document describes how Clive relates to the Cangjie language and toolchain, and how to use the CangjieCorpus and optional ingest/query scripts in this repo.

## Cangjie and cjpm

Clive is built for **Cangjie 1.0.x** (cjnative) and uses **cjpm** for build and run:

- **Create project**: `cjpm init`
- **Build**: `cjpm build`
- **Run**: `cjpm run`
- **Test**: `cjpm test`

You must **source the Cangjie environment** (e.g. `source /path/to/cangjie/envsetup.sh`) so the compiler and linker find the SDK. Clive’s `cjpm.toml` is set for `cjc-version = "1.0.5"` and target `darwin_aarch64_cjnative`; bin-dependencies point to the SDK’s precompiled std.

For up-to-date language and API documentation, use the **context7 MCP** (as in the project’s .cursorrules) or the official CangjieCorpus.

## CangjieCorpus

The **CangjieCorpus** is the official structured documentation (manuals, API docs, examples). Layout (v1.0.0):

| Path | Content |
|------|--------|
| `manual/source_zh_cn` | User dev guide: language basics, syntax, paradigms, multi-device, performance, debugging |
| `libs/std` | Standard library API: modules, parameters, usage, error handling |
| `tools/source_zh_cn` | Tool chain: IDE, creating projects, build, debug, CLI |
| `extra` | Community extensions and templates (reference) |

- **Official repo**: [Cangjie-Pub/CangjieCorpus](https://github.com/Cangjie-Pub/CangjieCorpus) (tag `1.0.0`).
- **Mirror**: `yolomao/cangjiecorpus-mirror` — useful for docs and examples when the main repo is not accessible.

Corpus content is in **Chinese** (e.g. `source_zh_cn`).

## Ingest script (optional)

The repo includes **`scripts/ingest_cangjie_corpus.py`**, which:

- Clones **CangjieCorpus** (tag 1.0.0) into `data/CangjieCorpus` if not present
- Collects Markdown under `manual/source_zh_cn`, `libs/std`, `tools/source_zh_cn`, `extra`
- Chunks the text (e.g. by headers, ~500–800 chars per chunk)
- Builds embeddings with a local model (sentence-transformers, multilingual)
- Stores chunks and embeddings in a **ChromaDB** database under `data/cangjie_chroma`

This is **optional**: Clive does not depend on it. It is intended for RAG-style Q&A over Cangjie docs (e.g. from the Cursor skill or other tooling).

### Running the ingest script

From the **project root**, with a Python environment that has the script’s dependencies (e.g. `chromadb`, `sentence-transformers`, `git`):

```bash
python scripts/ingest_cangjie_corpus.py
```

Default paths:

- Corpus: `data/CangjieCorpus`
- Chroma DB: `data/cangjie_chroma`

If the corpus is not present, the script will try to clone it; ensure `git` is installed and the repo is accessible.

### Query script (if present)

If the repo provides a query script (e.g. `scripts/query_cango.py` or similar), you can query the ingested corpus for RAG-style answers. The Cursor skill mentions querying with something like `python scripts/query_cangjie.py "<question>"`. Check `scripts/` for the exact script name and usage.

## Summary

- **Clive**: Uses Cangjie and cjpm; no dependency on CangjieCorpus or ChromaDB.
- **CangjieCorpus**: Use for language and API reference (via context7 MCP or clone/mirror).
- **Ingest/query**: Optional for RAG over corpus; run ingest once, then use the query script if available.
