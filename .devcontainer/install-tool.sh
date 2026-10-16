#!/bin/sh
set -eu

asset="$1"
url="$2"
dest="$3"
member="${4:-}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

curl -fsSL --retry 3 -o "$tmp/artifact" "$url"

expected="$(awk -v p="$asset" '$1 == p { print $2 }' /tmp/tools.tsv)"
if [ -z "$expected" ]; then
  echo "нет хэша для $asset" >&2
  exit 1
fi
echo "$expected  $tmp/artifact" | sha256sum -c -

if [ -z "$member" ]; then
  install -m 0755 "$tmp/artifact" "$dest"
  exit 0
fi

case "$asset" in
  *.zip) unzip -q "$tmp/artifact" -d "$tmp" ;;
  *) tar -xf "$tmp/artifact" -C "$tmp" ;;
esac

install -m 0755 "$tmp/$member" "$dest"
