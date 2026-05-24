#!/bin/sh
# Extract the __text section bytes from a Mach-O dylib.
# Usage: extract_text.sh <input.dylib> <output.bin>
set -e
in=$1
out=$2

# Use otool -l to find __text offset and size.
read offset size <<EOF
$(otool -l "$in" | awk '
  $1 == "sectname" && $2 == "__text" { in_text = 1; have_off = have_sz = 0; next }
  in_text && $1 == "offset" { off = $2; have_off = 1 }
  in_text && $1 == "size"   { sz  = $2; have_sz  = 1 }
  in_text && have_off && have_sz { print off, sz; exit }
')
EOF

if [ -z "$offset" ] || [ -z "$size" ]; then
  echo "extract_text: could not locate __text in $in" >&2
  exit 1
fi

# otool prints size as hex (0x...) and offset as decimal.
size=$((size))

dd if="$in" of="$out" bs=1 skip="$offset" count="$size" status=none
echo "extract_text: wrote $size bytes from offset $offset"
