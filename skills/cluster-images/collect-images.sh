#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${CONFIG_DIR:-$HOME/Downloads/configs}"
OUT="${HOME}/yamls/complete-images-list.yaml"
PER_CLUSTER=0
clusters=""

usage() {
    cat <<'EOF'
Usage: collect-images.sh [--out FILE] [--per-cluster] <cluster> [cluster ...]

Each <cluster> is the basename of a kubeconfig in ~/Downloads/configs, with or without
the .yaml suffix (e.g. "offline-ace" -> ~/Downloads/configs/offline-ace.yaml). The
literal argument "all" expands to every kubeconfig in that directory.

Collects container images from every pod in each cluster and prints one sorted,
de-duplicated list.

  --out FILE      write the unique list to FILE
                  (default: ~/yamls/complete-images-list.yaml)
  --per-cluster   print a per-cluster breakdown before the merged list

  CONFIG_DIR=<dir>  override the kubeconfig directory
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --out) OUT="$2"; shift 2 ;;
        --per-cluster) PER_CLUSTER=1; shift ;;
        -h|--help) usage; exit 0 ;;
        all)
            clusters="$clusters
$(find "$CONFIG_DIR" -maxdepth 1 -name '*.yaml' -exec basename {} .yaml \; | sort)"
            shift ;;
        -*) echo "unknown flag: $1" >&2; usage >&2; exit 2 ;;
        *) clusters="$clusters
${1%.yaml}"; shift ;;
    esac
done

clusters=$(printf '%s\n' "$clusters" | grep -v '^$' | awk '!seen[$0]++' || true)
if [[ -z $clusters ]]; then
    echo "no cluster given; pass one or more names from $CONFIG_DIR (or 'all')" >&2
    usage >&2
    exit 2
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
: >"$tmp/all"
: >"$tmp/failed"
: >"$tmp/order"
ncluster=0

while IFS= read -r name; do
    ncluster=$((ncluster + 1))
    kubeconfig="$CONFIG_DIR/$name.yaml"
    slug=$(printf '%s' "$name" | tr -c 'A-Za-z0-9._-' '_')
    if [[ ! -f $kubeconfig ]]; then
        printf '%s: no kubeconfig at %s\n' "$name" "$kubeconfig" >>"$tmp/failed"
        continue
    fi
    if ! KUBECONFIG="$kubeconfig" kubectl get pods -A -o yaml >"$tmp/raw" 2>"$tmp/err"; then
        printf '%s: %s\n' "$name" "$(tr '\n' ' ' <"$tmp/err")" >>"$tmp/failed"
        continue
    fi
    # spec + status image fields; drop the digest-only entries kubelet reports (image: sha256:<64hex>)
    grep -E '^[[:space:]]*-?[[:space:]]*image:[[:space:]]' "$tmp/raw" \
        | sed -E 's/^[[:space:]]*-?[[:space:]]*image:[[:space:]]*//; s/^"//; s/"$//; s/^'\''//; s/'\''$//' \
        | grep -vE '^sha256:[0-9a-f]{64}$' \
        | grep -vE '^[[:space:]]*$' \
        | sort -u >"$tmp/list.$slug" || : >"$tmp/list.$slug"
    printf '%s\n' "$name" >>"$tmp/order"
    cat "$tmp/list.$slug" >>"$tmp/all"
done <<<"$clusters"

if [[ $PER_CLUSTER -eq 1 ]]; then
    while IFS= read -r name; do
        slug=$(printf '%s' "$name" | tr -c 'A-Za-z0-9._-' '_')
        printf '## %s (%s images)\n' "$name" "$(wc -l <"$tmp/list.$slug" | tr -d ' ')"
        cat "$tmp/list.$slug"
        echo
    done <"$tmp/order"
fi

sort -u "$tmp/all" >"$tmp/uniq"
printf '## unique across %d cluster(s): %s images\n' "$ncluster" "$(wc -l <"$tmp/uniq" | tr -d ' ')"
cat "$tmp/uniq"

if [[ -s $tmp/order ]]; then
    mkdir -p "$(dirname "$OUT")"
    sed -E 's/^/- /' "$tmp/uniq" >"$OUT"
    printf '\nwritten: %s\n' "$OUT"
else
    printf '\nno cluster reachable; %s left untouched\n' "$OUT"
fi

if [[ -s $tmp/failed ]]; then
    printf '\n## failed clusters\n'
    cat "$tmp/failed"
    exit 1
fi
