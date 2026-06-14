# Changelog

## 1.1.0 - 2026-06-14

- Added complexity reporting with `--complexity`, `--top-complexity`, and `--top-lines`.
- Added per-language complexity scanning for common C-like, Zig, Rust, Go, and Python code.
- Upgraded the project to Zig 0.16.0 and updated build, process, filesystem, and IO API usage.
- Updated CI, release, Nix, and Debian packaging metadata to require Zig 0.16.0+.

## 1.0.0 - 2026-04-23

- Initial public release.
- Added embedded version reporting with `sloc --version`.
- Installed man page, license, and project docs through `zig build --prefix`.
- Added Nix flake and non-flake packaging.
- Added Linux/macOS release automation and distro package templates.
