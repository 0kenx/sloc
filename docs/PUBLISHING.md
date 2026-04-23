# Publishing `sloc`

This repository is now set up for source-based publication across common Linux
package ecosystems plus macOS. The included package templates assume
GitHub-hosted releases; if you publish somewhere else, adjust the release URLs.

## Release Checklist

1. Update `VERSION`, `build.zig.zon`, and `CHANGELOG.md`.
2. Run `./scripts/check-version-sync.sh`.
3. Run `zig build test -Dversion="$(cat VERSION)"`.
4. Create and push a tag named `v$(cat VERSION)`.
5. Let `.github/workflows/release.yml` build:
   - `sloc-<version>-source.tar.gz`
   - Linux archives for `x86_64-linux-musl` and `aarch64-linux-musl`
   - macOS archives for `x86_64-macos` and `aarch64-macos`
   - `checksums.txt`
6. Render ecosystem-specific manifests:

```sh
./scripts/render-packaging.sh --repo OWNER/REPO --checksums-file checksums.txt
```

Rendered files land in `packaging/rendered/<version>/`.

## Nix

- `flake.nix` exposes `packages`, `apps`, `devShells`, and an overlay.
- `default.nix` keeps non-flake users working.
- `nix/package.nix` is intended to be close to what a nixpkgs submission needs.

## Linux/macOS Publication Targets

- Homebrew: render `homebrew/sloc.rb`, then publish it to a tap or submit it to
  `homebrew-core`.
- Arch Linux: render `arch/PKGBUILD`, then publish to the AUR.
- Alpine: render `alpine/APKBUILD`, then submit it to the aports tree.
- Debian/Ubuntu: render the `debian/` directory, copy it into the release
  source tree, and build with `dpkg-buildpackage`.
- Generic Linux/macOS users: download the tagged tarballs from GitHub Releases.
