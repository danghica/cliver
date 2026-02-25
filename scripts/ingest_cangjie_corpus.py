#!/usr/bin/env python3
"""
Ingest CangjieCorpus Markdown into a ChromaDB vector database.
Clones https://github.com/Cangjie-Pub/CangjieCorpus if needed (tag 1.0.0).
Uses sentence-transformers (multilingual) for embeddings — no API key required.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

# Project root: parent of scripts/
PROJECT_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CORPUS_DIR = PROJECT_ROOT / "data" / "CangjieCorpus"
DEFAULT_CHROMA_DIR = PROJECT_ROOT / "data" / "cangjie_chroma"
CORPUS_REPO = "https://github.com/Cangjie-Pub/CangjieCorpus"
CORPUS_TAG = "1.0.0"

# Subdirs to ingest (relative to corpus root)
CORPUS_SUBDIRS = (
    "manual/source_zh_cn",
    "libs/std",
    "tools/source_zh_cn",
    "extra",
)

# Chunk size: aim for ~500–800 chars per chunk for better retrieval
MAX_CHUNK_CHARS = 800
MIN_CHUNK_CHARS = 80


def ensure_corpus_cloned(corpus_dir: Path) -> None:
    """Clone CangjieCorpus into corpus_dir if it doesn't exist."""
    if (corpus_dir / "README.md").exists():
        return
    corpus_dir.parent.mkdir(parents=True, exist_ok=True)
    try:
        from git import Repo
        print(f"Cloning {CORPUS_REPO} (tag {CORPUS_TAG}) into {corpus_dir} ...")
        Repo.clone_from(CORPUS_REPO, corpus_dir, depth=1, branch=CORPUS_TAG)
        print("Clone done.")
    except Exception as e:
        print(f"Clone failed: {e}", file=sys.stderr)
        print("Ensure git is installed and the repo is accessible. You can also clone manually:", file=sys.stderr)
        print(f"  git clone -b {CORPUS_TAG} --depth 1 {CORPUS_REPO} {corpus_dir}", file=sys.stderr)
        sys.exit(1)


def collect_md_files(corpus_dir: Path) -> list[Path]:
    """Return all .md files under the configured corpus subdirs."""
    out: list[Path] = []
    for sub in CORPUS_SUBDIRS:
        d = corpus_dir / sub
        if not d.exists():
            continue
        for p in d.rglob("*.md"):
            if p.is_file():
                out.append(p)
    return sorted(out)


def chunk_markdown(text: str, source: str) -> list[tuple[str, dict]]:
    """
    Split markdown into chunks by headers. Each chunk is (text, metadata).
    Metadata includes source and optional heading.
    """
    chunks: list[tuple[str, dict]] = []
    # Split by ## or # (keep headers with content)
    parts = re.split(r'(?=^#{1,6}\s+.+$)', text, flags=re.MULTILINE)
    current_heading: str | None = None
    for part in parts:
        part = part.strip()
        if not part:
            continue
        # Detect heading line (first line if it starts with #)
        lines = part.split("\n")
        if lines and lines[0].startswith("#"):
            current_heading = lines[0].lstrip("#").strip()
            body = "\n".join(lines[1:]).strip()
        else:
            body = part
        if not body:
            continue
        # If body is still too long, split by paragraphs
        if len(body) <= MAX_CHUNK_CHARS:
            if len(body) >= MIN_CHUNK_CHARS or not chunks:
                meta = {"source": source, "heading": current_heading or ""}
                chunks.append((body, meta))
            elif chunks:
                # Append to last chunk if small
                prev_text, prev_meta = chunks[-1]
                chunks[-1] = (prev_text + "\n\n" + body, prev_meta)
            continue
        # Split by double newline (paragraphs) and merge into ~MAX_CHUNK_CHARS
        paras = [p.strip() for p in body.split("\n\n") if p.strip()]
        acc: list[str] = []
        acc_len = 0
        for para in paras:
            if acc_len + len(para) + 2 > MAX_CHUNK_CHARS and acc:
                block = "\n\n".join(acc)
                if len(block) >= MIN_CHUNK_CHARS:
                    chunks.append((block, {"source": source, "heading": current_heading or ""}))
                acc = []
                acc_len = 0
            acc.append(para)
            acc_len += len(para) + 2
        if acc:
            block = "\n\n".join(acc)
            if len(block) >= MIN_CHUNK_CHARS:
                chunks.append((block, {"source": source, "heading": current_heading or ""}))
    return chunks


def main() -> None:
    corpus_dir = DEFAULT_CORPUS_DIR
    chroma_dir = DEFAULT_CHROMA_DIR
    if len(sys.argv) > 1:
        corpus_dir = Path(sys.argv[1])
    if len(sys.argv) > 2:
        chroma_dir = Path(sys.argv[2])

    ensure_corpus_cloned(corpus_dir)
    md_files = collect_md_files(corpus_dir)
    if not md_files:
        print("No .md files found under corpus subdirs.", file=sys.stderr)
        sys.exit(1)

    all_chunks: list[tuple[str, dict]] = []
    for path in md_files:
        rel = path.relative_to(corpus_dir)
        source = str(rel).replace("\\", "/")
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except Exception as e:
            print(f"Skip {path}: {e}", file=sys.stderr)
            continue
        for text_part, meta in chunk_markdown(text, source):
            all_chunks.append((text_part, meta))

    print(f"Collected {len(all_chunks)} chunks from {len(md_files)} files.")
    if not all_chunks:
        sys.exit(1)

    print("Loading embedding model (multilingual, no API key) ...")
    from sentence_transformers import SentenceTransformer
    model = SentenceTransformer("paraphrase-multilingual-MiniLM-L12-v2")

    print("Computing embeddings ...")
    texts = [t for t, _ in all_chunks]
    metadatas = [m for _, m in all_chunks]
    embeddings = model.encode(texts, show_progress_bar=True)

    chroma_dir.mkdir(parents=True, exist_ok=True)
    import chromadb
    from chromadb.config import Settings
    client = chromadb.PersistentClient(path=str(chroma_dir), settings=Settings(anonymized_telemetry=False))
    collection = client.get_or_create_collection(
        name="cangjie_corpus",
        metadata={"description": "Cangjie programming language corpus (manual, libs, tools, extra)"},
    )

    # Chroma expects list of str ids; metadata values must be str, int, float or bool
    # Chroma has a max batch size (~5461); add in batches to stay under limit
    ids = [f"chunk_{i}" for i in range(len(texts))]
    safe_metadatas = []
    for m in metadatas:
        safe_metadatas.append({k: (v if v is not None else "") for k, v in m.items()})

    emb_list = embeddings.tolist()
    batch_size = 4000
    for start in range(0, len(texts), batch_size):
        end = start + batch_size
        collection.add(
            ids=ids[start:end],
            embeddings=emb_list[start:end],
            documents=texts[start:end],
            metadatas=safe_metadatas[start:end],
        )
        print(f"  Added chunks {start + 1}-{end} / {len(texts)}")
    print(f"Stored {len(texts)} chunks in Chroma at {chroma_dir}")
    print("Collection: cangjie_corpus. Use scripts/query_cangjie.py to query.")


if __name__ == "__main__":
    main()
