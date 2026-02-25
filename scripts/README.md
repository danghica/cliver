# CangjieCorpus → Vector DB

Build a local vector database from [Cangjie-Pub/CangjieCorpus](https://github.com/Cangjie-Pub/CangjieCorpus) for RAG (no API key).

## Setup

```bash
cd /path/to/clive
python -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r scripts/requirements.txt
```

## Ingest (clone + chunk + embed + store)

```bash
python scripts/ingest_cangjie_corpus.py
```

- Clones the corpus to `data/CangjieCorpus` if missing (tag `1.0.0`).
- Chunks Markdown by sections, embeds with a multilingual model, stores in Chroma at `data/cangjie_chroma`.

Optional: `python scripts/ingest_cangjie_corpus.py /path/to/corpus /path/to/chroma`

## Query

```bash
python scripts/query_cangjie.py "仓颉如何创建工程"
python scripts/query_cangjie.py "how do I create a project" 8
```

Uses the same embedding model and returns the top-k chunks with `source` and `heading` metadata.
