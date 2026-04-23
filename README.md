# sloc

A fast, standalone source-lines-of-code counter that splits counts into **code**
vs **test**. Zero runtime dependencies (not even `awk` or `git` at build time
— `git` is used opportunistically at run time when inside a repo).

Originally a fish function; rewritten in Zig as a single static binary.

## What it counts

For every file matching an allowed extension, each non-empty, non-bracket-only,
non-comment line is counted as either **code** or **test**:

- Whole file is classified as **test** if its path or filename matches a test
  convention (see below).
- For Rust files, lines inside `#[cfg(test)] mod <name> { ... }` blocks are
  counted as **test** regardless of path.

### Skipped lines

A line is not counted when, after trimming, it is:

- empty, or
- made up entirely of brackets (`{ } [ ] ( )`), or
- a line comment starting with `//`, `--`, `#`, or `'`.

### Test detection

- **Directory components:** `test/`, `tests/`, `spec/`, `specs/`, `__tests__/`,
  `e2e/`, `cypress/`, `playwright/`, `testing/`, `fixtures/`.
- **Filenames:** `*_test.*`, `*_tests.*`, `*_spec.*`, `*.test.*`, `*.spec.*`,
  `test_*.*`, `tests_*.*`, `conftest.py`, and `*Test.{java,kt,scala,groovy}`,
  `*Tests.*`, `*IT.*`, `*ITCase.*`.
- **Rust inline:** `#[cfg(test)] mod <ident> { … }` blocks (brace-tracked).

## Build

Requires Zig 0.15.2+.

```sh
zig build -Doptimize=ReleaseFast
./zig-out/bin/sloc --help
```

Install to `~/.local`:

```sh
zig build -Doptimize=ReleaseFast --prefix ~/.local
~/.local/bin/sloc --version
```

This also installs:

- `share/licenses/sloc/LICENSE`
- `share/doc/sloc/README.md`
- `share/doc/sloc/CHANGELOG.md`
- `share/man/man1/sloc.1`

### Nix

Flake and non-flake Nix packaging are included:

```sh
nix build
./result/bin/sloc --help

nix run . -- --summary
```

## Usage

```
sloc [-a ext1,ext2] [-e ext1,ext2] [-o ext1,ext2] [-d] [-s] [-V] [-h]

  -a, --add ext1,ext2     Include additional file extensions
  -e, --exclude ext1,ext2 Exclude specified file extensions
  -o, --only ext1,ext2    Include ONLY these extensions (overrides -a/-e)
  -d, --descending        Flat list sorted by total lines descending
  -s, --summary           Just print totals
  -V, --version           Show version
  -h, --help              Show help
```

### File discovery

- Inside a git repo: `git ls-files` + untracked-but-not-ignored files.
- Otherwise: recursive walk of the current directory.

### Default extensions

`c cpp h hpp cmake mk bzl py ipynb js jsx ts svelte css htm html htmx xhtml go
java hs fut sol move mo rs zig sh nix tf lua yml json proto gql sql agda asm s
brs cc cxx hh hxx cs clj cljs cljc coffee litcoffee iced cr scss sass less styl
dart ex exs erl hrl fs fsi fsx f for f90 f95 f03 f08 groovy gradle hbs
handlebars hx hy jade jl kt kts tex ly ls mjs mochi monkey mustache nim nims m
mm ml mli pl pm php prql pug r rkt rpy rb scala nut svg swift tsx vb xml yaml
vhd vhdl v vh sv svh lagda bs csx liticed stylus escript xrl yrl fsscript gvy
gy gsh lhs cjs ily lyi mll mly t pod phtml php3 php4 php5 phps pyi pyw rktd
rktl rpym rpymc sc bas cls frm shtml app.src`

Extension matching is case-insensitive and supports multi-dot suffixes such as
`.app.src`.

## Example

```
$ sloc
Included extensions: c, cpp, h, hpp, ...
 code   test  path
    4      5  .
    4      3  ├──src/
    2      0  │   ├──app.py
    2      3  │   ├──lib.rs
    0      2  ├──tests/
    0      2  │   ├──test_app.py

Summary by file type:
     2       2  .py
     2       3  .rs

     4       5  TOTAL (code / test)
```

## Tests

```sh
zig build test
```

## Distribution

The repository now includes:

- `flake.nix`, `default.nix`, and [`nix/package.nix`](nix/package.nix) for Nix.
- GitHub Actions CI plus tagged Linux/macOS release builds in `.github/workflows/`.
- Package templates for Homebrew, Arch, Alpine, and Debian under `packaging/templates/`.
- [`scripts/render-packaging.sh`](scripts/render-packaging.sh) to render release-ready package files after a tagged source tarball exists.

Publishing notes live in [docs/PUBLISHING.md](docs/PUBLISHING.md).

## License

MIT — see [LICENSE](LICENSE).
