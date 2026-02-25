#!/usr/bin/env python3
"""
Query the Cangjie corpus vector DB. Run after ingest_cangjie_corpus.py.
Usage: python scripts/query_cangjie.py "how do I create a Cangjie project?"
"""
from __future__ import annotations

import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CHROMA_DIR = PROJECT_ROOT / "data" / "cangjie_chroma"


def main() -> None:
    if len(sys.argv) < 2:
        print("Usage: python query_cangjie.py <query text> [n_results=5]", file=sys.stderr)
        sys.exit(1)
    query = " ".join(sys.argv[1:-1]) if len(sys.argv) > 2 and sys.argv[-1].isdigit() else " ".join(sys.argv[1:])
    n_results = int(sys.argv[-1]) if len(sys.argv) > 2 and sys.argv[-1].isdigit() else 5
    if not query:
        print("Provide a non-empty query.", file=sys.stderr)
        sys.exit(1)

    chroma_dir = DEFAULT_CHROMA_DIR
    if not chroma_dir.exists():
        print(f"Chroma DB not found at {chroma_dir}. Run: python scripts/ingest_cangjie_corpus.py", file=sys.stderr)
        sys.exit(1)

    from sentence_transformers import SentenceTransformer
    import chromadb

    model = SentenceTransformer("paraphrase-multilingual-MiniLM-L12-v2")
    client = chromadb.PersistentClient(path=str(chroma_dir))
    collection = client.get_collection("cangjie_corpus")
    q_embedding = model.encode([query]).tolist()
    results = collection.query(query_embeddings=q_embedding, n_results=n_results, include=["documents", "metadatas"])
    docs = results["documents"][0]
    metadatas = results["metadatas"][0]
    for i, (doc, meta) in enumerate(zip(docs, metadatas), 1):
        source = meta.get("source", "")
        heading = meta.get("heading", "")
        print(f"--- Result {i} [{source}] {heading} ---")
        print(doc[:1200] + ("..." if len(doc) > 1200 else ""))
        print()


if __name__ == "__main__":
    main()
