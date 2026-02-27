# Installing the distributed actors library

The [distributed-actors-cj](https://gitcode.com/Cangjie-SIG/distributed-actors-cj) library is available from Cangjie-SIG. To use it in this project:

## 1. Clone the repository (with submodules)

From the project root:

```bash
git clone --recurse-submodules https://gitcode.com/Cangjie-SIG/distributed-actors-cj.git distributed-actors-cj
```

This clones the `actors` package and its dependency **CangjieMagic** (in `third_party/CangjieMagic`).

## 2. Add the dependency to `cjpm.toml`

In `[dependencies]`:

```toml
actors = { path = "distributed-actors-cj" }
```

Or from git (submodules are not fetched by cjpm; the path dependency is more reliable):

```toml
actors = { path = "distributed-actors-cj" }
```

## 3. Satisfy CangjieMagic’s build requirements

The `actors` package depends on **magic** (CangjieMagic), which expects platform-specific std libs (e.g. `cangjie-stdx-mac-aarch64-*` for macOS ARM). You must either:

- Obtain the matching **cangjie-stdx** artifacts for your target and place them under  
  `distributed-actors-cj/third_party/CangjieMagic/libs/` as expected by  
  `distributed-actors-cj/third_party/CangjieMagic/cjpm.toml`, or  
- Set the environment variables / paths that CangjieMagic’s `cjpm.toml` uses for your platform.

Until those paths are set up, `cjpm update` or `cjpm build` may fail when the `actors` dependency is enabled.

## 4. Build distributed-actors-cj (stdx pre-build requirements)

The **stdx** dependency (cangjie_stdx) is built via CMake and needs:

- **CANGJIE_HOME** set to your Cangjie install (e.g. by sourcing `envsetup.sh`).
- **LLVM tools** in `PATH`: CMake looks for `llvm-ar` and `llvm-ranlib`. Cangjie’s LLVM often has only `llvm-ar`; install Homebrew’s LLVM for `llvm-ranlib`: `brew install llvm` (adds `/opt/homebrew/opt/llvm/bin` on Apple Silicon). The wrapper script adds both Cangjie’s and Homebrew’s LLVM bin to `PATH`.
- **Ninja**: `brew install ninja`.
- **CMake**: already installed.
- **DYLD_LIBRARY_PATH**: must include Cangjie’s runtime lib so the stdx build-script can load `libcangjie-runtime.dylib`; the wrapper script sets this.

From the `distributed-actors-cj` directory you can use the wrapper script:

```bash
cd distributed-actors-cj
chmod +x build_with_cangjie_env.sh
./build_with_cangjie_env.sh
```

The script also merges `libstdx.encoding.json.a` with `libstdx.encoding.jsonFFI.a` after the first build attempt if needed, so that linking magic/actors resolves the native JSON symbols (`_CJ_JSON_*`). If your Cangjie toolchain does not support the conditional `@When[env == "ohos"]` in stdx, a patch is applied (or re-apply after `cjpm update` with `./patch_stdx_certificate.sh`).

Or set up the environment yourself and run `cjpm build`:

```bash
source /path/to/cangjie/envsetup.sh
export PATH="${CANGJIE_HOME}/third_party/llvm/bin:${PATH}"
# ensure ninja is installed: brew install ninja
cjpm build
```

## 5. Use in code

After a successful build you can import the library (see distributed-actors-cj documentation for the actual package and symbol names).

---

**Note:** This project (clive) is currently configured for `darwin_aarch64_cjnative` and does not enable the `actors` dependency by default, so the main project still builds without the distributed-actors setup.
