#!/usr/bin/env bash
#
# inspect-build-flags.sh IMAGE_REF
#
# Pulls a container image, extracts its Go entrypoint binary, and prints every
# ldflags "-X importpath.Name=value" build flag baked into it (e.g.
# main.Version, main.GitBranch, license-verifier info.EnforceLicense, ...).
#
# Works for any non-stripped Go binary. Reads the values straight out of the
# ELF symbol table, so it does not need to run the (foreign-arch) binary.

set -euo pipefail

IMAGE="${1:-}"
if [[ -z "$IMAGE" ]]; then
  echo "usage: inspect-build-flags.sh <image-ref>" >&2
  echo "  e.g. inspect-build-flags.sh ghcr.io/foo/bar:tag" >&2
  echo "       inspect-build-flags.sh ghcr.io/foo/bar@sha256:..." >&2
  exit 1
fi

for bin in docker go; do
  command -v "$bin" >/dev/null 2>&1 || { echo "error: '$bin' not found in PATH" >&2; exit 1; }
done

PLATFORM="${PLATFORM:-linux/amd64}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo ">> pulling $IMAGE ($PLATFORM)" >&2
docker pull --platform "$PLATFORM" "$IMAGE" >/dev/null

# Resolve the entrypoint binary path inside the image.
ENTRY="$(docker inspect --format '{{if .Config.Entrypoint}}{{index .Config.Entrypoint 0}}{{else}}{{index .Config.Cmd 0}}{{end}}' "$IMAGE")"
if [[ -z "$ENTRY" ]]; then
  echo "error: could not determine entrypoint binary from image config" >&2
  exit 1
fi
echo ">> entrypoint binary: $ENTRY" >&2

# Extract the binary.
CID="$(docker create --platform "$PLATFORM" "$IMAGE")"
docker cp "$CID:$ENTRY" "$WORK/binary" >/dev/null
docker rm "$CID" >/dev/null

# ELF reader: enumerate every "-X"-injected string var (they each get a
# "<symbol>.str" sibling) and dereference its string header.
cat > "$WORK/reader.go" <<'EOF'
package main

import (
	"debug/elf"
	"encoding/binary"
	"fmt"
	"os"
	"sort"
	"strings"
)

func readAt(f *elf.File, addr, n uint64) []byte {
	for _, s := range f.Sections {
		if s.Type == elf.SHT_NOBITS {
			continue
		}
		if addr >= s.Addr && addr+n <= s.Addr+s.Size {
			data, err := s.Data()
			if err != nil {
				return nil
			}
			off := addr - s.Addr
			return data[off : off+n]
		}
	}
	return nil
}

func readString(f *elf.File, symAddr uint64) string {
	hdr := readAt(f, symAddr, 16)
	if hdr == nil {
		return ""
	}
	ptr := binary.LittleEndian.Uint64(hdr[0:8])
	length := binary.LittleEndian.Uint64(hdr[8:16])
	if ptr == 0 || length == 0 {
		return ""
	}
	b := readAt(f, ptr, length)
	return string(b)
}

func main() {
	f, err := elf.Open(os.Args[1])
	if err != nil {
		panic(err)
	}
	defer f.Close()

	syms, err := f.Symbols()
	if err != nil {
		panic(err)
	}

	addr := map[string]uint64{}
	injected := map[string]bool{}
	for _, s := range syms {
		addr[s.Name] = s.Value
		if strings.HasSuffix(s.Name, ".str") {
			base := strings.TrimSuffix(s.Name, ".str")
			if strings.HasPrefix(base, "runtime.") {
				continue // not a user -X flag
			}
			injected[base] = true
		}
	}

	names := make([]string, 0, len(injected))
	for n := range injected {
		names = append(names, n)
	}
	sort.Strings(names)

	for _, n := range names {
		a, ok := addr[n]
		if !ok {
			continue
		}
		val := readString(f, a)
		if val == "" {
			val = "<empty>"
		}
		// Collapse multi-line values (e.g. LicenseCA PEM) to a note.
		if strings.Contains(val, "\n") {
			val = fmt.Sprintf("<%d bytes, multi-line>", len(val))
		}
		fmt.Printf("%-60s = %s\n", n, val)
	}
}
EOF

echo ">> build flags:" >&2
echo
GOFLAGS='' GO111MODULE=off go run "$WORK/reader.go" "$WORK/binary"
