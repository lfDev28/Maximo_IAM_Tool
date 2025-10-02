#!/bin/sh
# Shared portable helpers for dev scripts (POSIX sh).

load_env_files() {
  root=$1
  if [ -f "$root/.env" ]; then
    set -a
    . "$root/.env"
    set +a
  fi
  if [ -f "$root/.env.override" ]; then
    set -a
    . "$root/.env.override"
    set +a
  fi
}

normalize_release() {
  nr_input=$1
  nr_step=$(printf '%s' "$nr_input" | tr '[:upper:]' '[:lower:]')
  nr_step=$(printf '%s' "$nr_step" | sed 's/[^a-z0-9.-]/-/g')
  nr_step=$(printf '%s' "$nr_step" | sed 's/^[^a-z0-9]*//')
  nr_step=$(printf '%s' "$nr_step" | sed 's/[^a-z0-9]*$//')
  if [ -z "$nr_step" ]; then
    nr_step=mas-iam
  fi
  printf '%s' "$nr_step"
}

resolve_release() {
  rr_raw=$1
  rr_auto=${2:-0}
  rr_rel=$(normalize_release "$rr_raw")
  if [ "$rr_auto" = "1" ]; then
    case "$rr_raw" in
      ''|-*|*-)
        rr_base=$(normalize_release "${rr_raw%-}")
        if [ -z "$rr_base" ]; then
          rr_base=mas-iam
        fi
        rr_ts=$(date +%Y%m%d%H%M%S)
        rr_rel="${rr_base}${rr_ts}"
        ;;
    esac
  fi
  printf '%s' "$(normalize_release "$rr_rel")"
}

persist_override() {
  po_root=$1
  po_rel=$2
  po_ns=$3
  po_sc=${4:-}
  {
    printf 'RELEASE=%s\n' "$po_rel"
    printf 'NAMESPACE=%s\n' "$po_ns"
    if [ -n "$po_sc" ]; then
      printf 'STORAGE_CLASS=%s\n' "$po_sc"
    fi
  } >"$po_root/.env.override"
}

make_args() {
  ma_ns=$1
  ma_rel=$2
  ma_sc=${3:-}
  printf 'NS=%s\n' "$ma_ns"
  printf 'NAMESPACE=%s\n' "$ma_ns"
  printf 'DEV_NS=%s\n' "$ma_ns"
  printf 'RELEASE=%s\n' "$ma_rel"
  printf 'DEV_RELEASE=%s\n' "$ma_rel"
  if [ -n "$ma_sc" ]; then
    printf 'SC=%s\n' "$ma_sc"
    printf 'STORAGE_CLASS=%s\n' "$ma_sc"
  fi
}
