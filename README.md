# sloc

A fast, standalone source-lines-of-code counter that splits counts into **code**,
**comment**, and **test** lines by default, with optional blank-line counting and
configurable test splitting. Zero runtime dependencies (not even `awk` or `git` at build time
— `git` is used opportunistically at run time when inside a repo).

Originally a fish function; rewritten in Zig as a single static binary.

## What it counts

For every file matching an allowed extension, each line is counted into one of
the enabled buckets:

- Whole file is classified as **test** if its path or filename matches a test
  convention (see below).
- Audited default extensions use per-language plugins for comment styles and
  test heuristics. Unknown `--add` extensions fall back to generic `//`, `--`,
  `#`, and `'` comment markers.
- Blank lines are counted only with `-b` / `--blanks`.
- Symbol-only lines are skipped by default; `-p` / `--count-symbols` counts
  them as **code** or **test** depending on context.
- For Rust files, lines inside `#[cfg(test)] mod <name> { ... }` blocks are
  counted as **test** regardless of path.
- `-n` / `--no-split-tests` merges test lines into the main `LINES` column.

### Skipped lines

By default, a line is not counted when, after trimming, it is:

- empty, or
- made up entirely of symbols or punctuation, such as `{ } [ ] ( )`.

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
sloc [-a ext1,ext2] [-e ext1,ext2] [-o ext1,ext2] [-d] [-s] [-n] [-c] [-b] [-p] [-l] [-r]
     [--line-authors] [--churn] [-V] [-h]

  -a, --add ext1,ext2     Include additional file extensions
  -e, --exclude ext1,ext2 Exclude specified file extensions
  -o, --only ext1,ext2    Include ONLY these extensions (overrides -a/-e)
  -d, --descending        Flat list sorted by total lines descending
  -s, --summary           Just print totals
  -n, --no-split-tests    Merge test lines into the main code/lines column
  -c, --no-comments       Exclude comment lines from counts and output
  -b, --blanks            Show blank-line counts
  -p, --count-symbols     Count symbol-only lines as code/test
  -l, --line-authors      Use git blame to color summary bars by line author
  -r, --churn             Use git log to show added/deleted churn by file type
  -V, --version           Show version
  -h, --help              Show help
```

Short boolean flags can be combined, e.g. `-ncblr`.

### File discovery

- Inside a git repo: `git ls-files` + untracked-but-not-ignored files.
- Otherwise: recursive walk of the current directory.

### Git reports

`--line-authors` changes the file-type summary bar into a stacked author bar
using `git blame --line-porcelain`. Each file type keeps one row, and the
`AUTHORS` column lists the largest current line authors with their share of that
file type. The report uses the same code, test, comment, blank, and symbol-only
settings as the main count.

`--churn` adds whole-history `git log --all --no-merges --numstat --no-renames
--format=` columns to the file-type summary. `CHURN` is `deleted / added *
100`; binary numstat entries are skipped. File types with historical churn but
no current matching files are still shown.

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
 code   test  comment  path
    4      5        3  .
    4      3        2  ├──src/
    2      0        1  │   ├──app.py
    2      3        1  │   ├──lib.rs
    0      2        1  ├──tests/
    0      2        1  │   ├──test_app.py

Summary by file type:
     2       2        2  .py
     2       3        1  .rs

     4       5        3  TOTAL (code / test / comment)
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
