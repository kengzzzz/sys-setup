#!/usr/bin/env bash
set -euo pipefail

root_dir="${1:?rootfs dir required}"
queue_file="/tmp$(printf '%s' "$root_dir" | tr '/' '_').queue"
seen_file="/tmp$(printf '%s' "$root_dir" | tr '/' '_').seen"
unresolved_file="${root_dir}/meta/unresolved-libs.txt"
runtime_needed_file="${root_dir}/meta/runtime-needed.txt"

scan_file() {
  local file="$1"
  readelf -d "$file" 2>/dev/null | awk '/NEEDED/ { gsub(/[\[\]]/, "", $5); print $5 }'
  local interp
  interp="$(readelf -l "$file" 2>/dev/null | awk -F': ' '/Requesting program interpreter/ { gsub(/]/, "", $2); print $2 }')"
  if [ -n "$interp" ]; then
    printf '%s\n' "$interp"
  fi
}

resolve_lib() {
  local lib="$1"
  case "$lib" in
    libcuda.so*|libnvidia-*)
      return 0
      ;;
  esac

  local dir
  for dir in \
    "${root_dir}/app" \
    /app \
    /usr/local/cuda/lib64 \
    /usr/local/nvidia/lib64 \
    /usr/local/nvidia/lib \
    /lib64 \
    /usr/lib64 \
    /usr/lib/x86_64-linux-gnu \
    /lib/x86_64-linux-gnu \
    /usr/lib \
    /lib
  do
    if [ -e "$dir/$lib" ]; then
      printf '%s\n' "$dir/$lib"
      return 0
    fi
  done

  if [ -e "$lib" ]; then
    printf '%s\n' "$lib"
    return 0
  fi

  return 1
}

: > "$queue_file"
find "${root_dir}/app" -maxdepth 1 -type f \( -perm /111 -o -name '*.so*' \) -print > "$queue_file"
: > "$seen_file"
: > "$runtime_needed_file"
rm -f "$unresolved_file"

while [ -s "$queue_file" ]; do
  file="$(head -n 1 "$queue_file")"
  tail -n +2 "$queue_file" > "${queue_file}.next"
  mv "${queue_file}.next" "$queue_file"
  real="$(readlink -f "$file")"
  grep -qxF "$real" "$seen_file" 2>/dev/null && continue
  printf '%s\n' "$real" >> "$seen_file"

  while read -r needed; do
    [ -n "$needed" ] || continue
    printf '%s -> %s\n' "$real" "$needed" >> "$runtime_needed_file"
    resolved="$(resolve_lib "$needed" || true)"
    if [ -z "$resolved" ]; then
      printf 'UNRESOLVED %s needed by %s\n' "$needed" "$real" >> "$unresolved_file"
      continue
    fi

    case "$resolved" in
      "${root_dir}"/*)
        dest="$resolved"
        ;;
      *)
        dest="${root_dir}$resolved"
        mkdir -p "$(dirname "$dest")"
        cp -a --parents "$resolved" "$root_dir/"
        ;;
    esac

    if [ -L "$resolved" ]; then
      target="$(readlink -f "$resolved")"
      case "$target" in
        "${root_dir}"/*)
          target_dest="$target"
          ;;
        *)
          target_dest="${root_dir}$target"
          mkdir -p "$(dirname "$target_dest")"
          cp -a --parents "$target" "$root_dir/"
          ;;
      esac
      printf '%s\n' "$target_dest" >> "$queue_file"
    else
      printf '%s\n' "$dest" >> "$queue_file"
    fi
  done < <(scan_file "$real")
done

find "$root_dir" -type f \( -perm /111 -o -name '*.so*' \) -exec sh -c 'for f do echo "### $f"; readelf -d "$f" 2>/dev/null | grep NEEDED || true; done' sh {} + > "${root_dir}/meta/readelf-needed.txt"

if [ -s "$unresolved_file" ]; then
  grep -vE 'UNRESOLVED (libcuda\.so(\.1)?|libnvidia-.*) ' "$unresolved_file" > "${unresolved_file}.real" || true
  test ! -s "${unresolved_file}.real"
  rm -f "${unresolved_file}.real"
fi

if [ -e "${root_dir}/usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2" ]; then
  mkdir -p "${root_dir}/lib64"
  ln -sf ../usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2 "${root_dir}/lib64/ld-linux-x86-64.so.2"
fi

link_cuda_major() {
  local base_name="$1"
  local source_file
  source_file="$(find "${root_dir}/usr/local" -type f -name "${base_name}.so.*" | sort | head -n 1)"
  if [ -n "$source_file" ]; then
    ln -sf "$(printf '%s\n' "$source_file" | sed "s#^${root_dir}##")" "${root_dir}/usr/local/cuda/lib64/${base_name}.so.$(basename "$source_file" | sed -E "s/^${base_name}\.so\.([0-9]+).*$/\1/")"
  fi
}

mkdir -p "${root_dir}/usr/local/cuda/lib64"
link_cuda_major libcudart
link_cuda_major libcublas
link_cuda_major libcublasLt

find "$root_dir" \( -type f -o -type l \) | sed "s#^${root_dir}##" | sort > "${root_dir}/meta/rootfs-files.txt"
