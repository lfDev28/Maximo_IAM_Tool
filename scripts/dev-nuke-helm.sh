#!/bin/sh
set -eu

# Portable removal of Helm v3 release metadata (Secrets/ConfigMaps) for a given
# release name across ALL namespaces. POSIX compliant.
#
# Env:
#   RELEASE  - release name (defaults from ../.env RELEASE or 'mas-iam')
#   DRY_RUN  - set to 1 to preview only
# Flags:
#   -y/--yes     - skip confirmation prompt
#   -n/--dry-run - show what would be removed (same as DRY_RUN=1)
#   --prefix     - treat RELEASE as a prefix (matches mas-iam, mas-iam-01, ...)

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

USER_RELEASE=${RELEASE:-}

if [ -f "$REPO_ROOT/.env" ]; then
  set -a
  . "$REPO_ROOT/.env"
  set +a
fi

if [ -n "$USER_RELEASE" ]; then
  RELEASE=$USER_RELEASE
fi

REL=${RELEASE:-mas-iam}
DRY=${DRY_RUN:-0}
AUTO_YES=0
MATCH_MODE=exact # exact | prefix

usage() {
  cat <<USAGE
Usage: RELEASE=<name> $0 [options]
  -y, --yes       Delete without prompting
  -n, --dry-run   Preview matching release metadata
  --prefix        Match release names starting with RELEASE
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    -y|--yes)
      AUTO_YES=1
      ;;
    -n|--dry-run)
      DRY=1
      ;;
    --prefix)
      MATCH_MODE=prefix
      ;;
    --)
      shift
      break
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
  shift
done

echo "Scanning for Helm release metadata of '$REL' across all namespaces..."

tmpfile=$(mktemp -t helmrel.XXXXXX)
trap 'rm -f "$tmpfile"' EXIT

list_matches() {
  kind=$1
  kubectl get "$kind" -A -l owner=helm \
    -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,REL:.metadata.labels.name' --no-headers 2>/dev/null \
    | awk -v rel="$REL" -v mode="$MATCH_MODE" '
        function match(val, rel, mode) {
          if (mode == "prefix") {
            return index(val, rel) == 1
          }
          return val == rel
        }
        $3 != "" && match($3, rel, mode) { print $1"\t"$2 }
      ' || true

  kubectl get "$kind" -A -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name' --no-headers 2>/dev/null \
    | awk -v rel="$REL" -v mode="$MATCH_MODE" '
        BEGIN {
          rel_regex = rel
          gsub("\\.", "\\\\.", rel_regex)
        }
        {
          pattern = "^sh\\.helm\\.release\\.[vV][0-9]+\\." rel_regex
          if (mode == "prefix") {
            pattern = pattern "[A-Za-z0-9.-]*"
          }
          pattern = pattern "\\.[0-9]+$"
          if ($2 ~ pattern) {
            print $1"\t"$2
          }
        }
      ' || true
}

for kind in secret configmap; do
  list_matches "$kind" >>"$tmpfile"
done

sort -u "$tmpfile" -o "$tmpfile"

if [ ! -s "$tmpfile" ]; then
  echo "No Helm release metadata found for '$REL'."
  exit 0
fi

echo "Found the following items:"
sed 's/^/ - /' "$tmpfile"

if [ "$AUTO_YES" -ne 1 ] && [ "$DRY" != "1" ]; then
  printf "Delete these items now? Type 'yes' to continue: "
  read ans
  if [ "$ans" != "yes" ]; then
    echo "Aborted"
    exit 1
  fi
fi

if [ "$DRY" = "1" ]; then
  echo "[DRY] Skipping deletions."
  exit 0
fi

echo "Deleting..."
TAB=$(printf '\t')
while IFS="$TAB" read -r NS NAME; do
  [ -z "$NS" ] && continue
  if kubectl -n "$NS" get secret "$NAME" >/dev/null 2>&1; then
    kubectl -n "$NS" delete secret "$NAME" --ignore-not-found || true
  elif kubectl -n "$NS" get configmap "$NAME" >/dev/null 2>&1; then
    kubectl -n "$NS" delete configmap "$NAME" --ignore-not-found || true
  fi
done <"$tmpfile"

echo "Done removing Helm release metadata for '$REL'."
