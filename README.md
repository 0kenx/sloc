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

Install to `~/.local/bin`:

```sh
zig build -Doptimize=ReleaseFast --prefix ~/.local
```

## Usage

```
sloc [-a ext1,ext2] [-e ext1,ext2] [-o ext1,ext2] [-d] [-s] [-h]

  -a, --add ext1,ext2     Include additional file extensions
  -e, --exclude ext1,ext2 Exclude specified file extensions
  -o, --only ext1,ext2    Include ONLY these extensions (overrides -a/-e)
  -d, --descending        Flat list sorted by total lines descending
  -s, --summary           Just print totals
  -h, --help              Show help
```

### File discovery

- Inside a git repo: `git ls-files` + untracked-but-not-ignored files.
- Otherwise: recursive walk of the current directory.

### Default extensions

`c cpp h hpp cmake mk bzl py ipynb js jsx ts svelte css htm html htmx xhtml go
java hs fut sol move mo rs zig sh nix tf lua yml json proto gql sql`

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

## License

MIT — see [LICENSE](LICENSE).
