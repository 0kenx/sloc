#!/usr/bin/env sh
set -eu

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
version=$(tr -d '\r\n' < "$root_dir/VERSION")
repo=""
sha256=""
checksums_file=""
out_dir=""
maintainer="0kenx <km@nxfi.app>"
release_date=$(LC_ALL=C date -R)
release_year=$(date +%Y)

usage() {
  cat <<'EOF'
Usage: ./scripts/render-packaging.sh --repo OWNER/REPO [options]

Options:
  --repo OWNER/REPO         GitHub repository used for published releases
  --version X.Y.Z           Override the version from VERSION
  --sha256 HASH             SHA-256 for sloc-<version>-source.tar.gz
  --checksums-file PATH     Read the source tarball SHA-256 from checksums.txt
  --maintainer "Name <mail>"
                            Maintainer string for Debian packaging
  --out-dir PATH            Output directory (default: packaging/rendered/<version>)
  -h, --help                Show this help text
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)
      repo=$2
      shift 2
      ;;
    --version)
      version=$2
      shift 2
      ;;
    --sha256)
      sha256=$2
      shift 2
      ;;
    --checksums-file)
      checksums_file=$2
      shift 2
      ;;
    --maintainer)
      maintainer=$2
      shift 2
      ;;
    --out-dir)
      out_dir=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [ -z "$repo" ]; then
  echo "--repo is required" >&2
  exit 1
fi

if [ -z "$out_dir" ]; then
  out_dir="$root_dir/packaging/rendered/$version"
fi

archive="sloc-${version}-source.tar.gz"

if [ -z "$sha256" ] && [ -n "$checksums_file" ]; then
  while IFS= read -r line; do
    case "$line" in
      *"  $archive")
        sha256=${line%%  *}
        break
        ;;
    esac
  done < "$checksums_file"
fi

if [ -z "$sha256" ]; then
  echo "a source tarball SHA-256 is required via --sha256 or --checksums-file" >&2
  exit 1
fi

escape_sed_replacement() {
  printf '%s' "$1" | sed 's/[&|]/\\&/g'
}

version_esc=$(escape_sed_replacement "$version")
repo_esc=$(escape_sed_replacement "$repo")
sha256_esc=$(escape_sed_replacement "$sha256")
maintainer_esc=$(escape_sed_replacement "$maintainer")
date_esc=$(escape_sed_replacement "$release_date")
year_esc=$(escape_sed_replacement "$release_year")

render_template() {
  src=$1
  dest=$2
  mkdir -p "$(dirname "$dest")"
  sed \
    -e "s|@VERSION@|$version_esc|g" \
    -e "s|@REPO@|$repo_esc|g" \
    -e "s|@SHA256@|$sha256_esc|g" \
    -e "s|@MAINTAINER@|$maintainer_esc|g" \
    -e "s|@DATE_RFC2822@|$date_esc|g" \
    -e "s|@YEAR@|$year_esc|g" \
    "$src" > "$dest"
}

render_template \
  "$root_dir/packaging/templates/homebrew/sloc.rb.in" \
  "$out_dir/homebrew/sloc.rb"
render_template \
  "$root_dir/packaging/templates/arch/PKGBUILD.in" \
  "$out_dir/arch/PKGBUILD"
render_template \
  "$root_dir/packaging/templates/alpine/APKBUILD.in" \
  "$out_dir/alpine/APKBUILD"
render_template \
  "$root_dir/packaging/templates/debian/changelog.in" \
  "$out_dir/debian/changelog"
render_template \
  "$root_dir/packaging/templates/debian/control.in" \
  "$out_dir/debian/control"
render_template \
  "$root_dir/packaging/templates/debian/copyright.in" \
  "$out_dir/debian/copyright"
mkdir -p "$out_dir/debian/source"
cp "$root_dir/packaging/templates/debian/rules" "$out_dir/debian/rules"
cp "$root_dir/packaging/templates/debian/source/format" "$out_dir/debian/source/format"
chmod 755 "$out_dir/debian/rules"

printf 'Rendered packaging files in %s\n' "$out_dir"
