#!/usr/bin/env sh
set -eu

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
version=$(tr -d '\r\n' < "$root_dir/VERSION")
zon_version=$(sed -n 's/^[[:space:]]*\.version = "\(.*\)",$/\1/p' "$root_dir/build.zig.zon")

if [ -z "$zon_version" ]; then
  echo "could not extract .version from build.zig.zon" >&2
  exit 1
fi

if [ "$version" != "$zon_version" ]; then
  echo "VERSION ($version) does not match build.zig.zon ($zon_version)" >&2
  exit 1
fi
