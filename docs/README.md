# Clive documentation

**Clive** is a Cangjie package-to-CLI utility. It parses a Cangjie package’s source, discovers public functions and public constructors, and generates a CLI driver that exposes them as commands—without runtime reflection.

This directory contains detailed documentation for users, contributors, and integrators.

## Documentation index

| Document | Description |
|----------|-------------|
| [Overview](overview.md) | What Clive does, features, and high-level workflow |
| [Architecture](architecture.md) | Design, pipeline, and component responsibilities |
| [User guide](user-guide.md) | Build, run, environment, and using the generated CLI |
| [Generated driver](generated-driver.md) | How the generated `cli_driver.cj` works (object store, overloads, arg conversion) |
| [API reference](api-reference.md) | Parser and codegen types and public APIs (Manifest, CommandInfo, etc.) |
| [Limitations and future](limitations-and-future.md) | v1 limitations, known issues, and planned improvements |
| [Development](development.md) | Contributing, file layout, cjpm, and testing |
| [Cangjie and corpus](cangjie-and-corpus.md) | Cangjie toolchain, CangjieCorpus, and ingest/query scripts |

## Quick links

- **Root README**: [../README.md](../README.md) — short project summary and quick start
- **Sample package**: [../sample_cangjie_package/README.md](../sample_cangjie_package/README.md) — minimal package for testing Clive
