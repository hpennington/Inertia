#!/usr/bin/env bash
#
# Renders every diagram in website/diagrams/ to a light and a dark SVG in
# website/docs/assets/diagrams/. The docs embed the SVGs directly, so the site
# needs no mermaid plugin and no JavaScript at read time.
#
# Requires mermaid-cli:  npm install -g @mermaid-js/mermaid-cli
#
# Usage: website/scripts/render-diagrams.sh [name ...]
#        (no arguments renders everything)

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
website="$(dirname "$here")"
src="$website/diagrams"
out="$website/docs/assets/diagrams"

if ! command -v mmdc >/dev/null 2>&1; then
  echo "mmdc not found. Install it with: npm install -g @mermaid-js/mermaid-cli" >&2
  exit 1
fi

mkdir -p "$out"

if [ "$#" -gt 0 ]; then
  sources=()
  for name in "$@"; do
    sources+=("$src/${name%.mmd}.mmd")
  done
else
  sources=("$src"/*.mmd)
fi

# The docs use the dark diagrams on both colour schemes, so the dark surface is
# baked into the SVG rather than left transparent — light text on a transparent
# background would disappear against the light scheme's white page. Add `light`
# here (and the #only-light / #only-dark suffixes back in the markdown) to go
# back to a per-scheme pair.
themes=(dark)

for file in "${sources[@]}"; do
  name="$(basename "$file" .mmd)"
  for theme in "${themes[@]}"; do
    case "$theme" in
      dark) background="#1e1f29" ;;
      *)    background="transparent" ;;
    esac

    echo "rendering $name ($theme)"
    mmdc \
      --input "$file" \
      --output "$out/$name-$theme.svg" \
      --configFile "$src/mermaid.$theme.json" \
      --backgroundColor "$background" \
      --quiet

    # mmdc writes width="100%" with no height, which gives an <img> no intrinsic
    # size — a tall diagram would then be stretched to the full column width.
    # Give the root the viewBox's own dimensions and let CSS scale it down.
    python3 - "$out/$name-$theme.svg" <<'PY'
import re, sys

path = sys.argv[1]
svg = open(path, encoding="utf-8").read()
box = re.search(r'viewBox="[-\d.]+ [-\d.]+ ([\d.]+) ([\d.]+)"', svg)
if box:
    w, h = round(float(box.group(1))), round(float(box.group(2)))
    svg = svg.replace('width="100%"', f'width="{w}" height="{h}"', 1)
    open(path, "w", encoding="utf-8").write(svg)
PY
  done
done

echo "done: $out"
