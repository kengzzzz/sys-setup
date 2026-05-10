#!/usr/bin/env bash
set -euo pipefail

build_dir="${1:?build dir required}"
binary_name="${2:?binary name required}"
out_dir="${3:?output dir required}"
llama_commit="${4:?llama commit required}"

mkdir -p "${out_dir}/app" "${out_dir}/meta"
cp -a "${build_dir}/bin/${binary_name}" "${out_dir}/app/"
find "${build_dir}/bin" -maxdepth 1 -name '*.so*' -exec cp -a {} "${out_dir}/app/" \;
find "${out_dir}/app" -type f -perm /111 -exec strip --strip-unneeded {} + || true
find "${out_dir}/app" -type f -name '*.so*' -exec strip --strip-unneeded {} + || true
printf '%s\n' "${llama_commit}" > "${out_dir}/meta/llama.cpp.commit"
cmake -LA -N "${build_dir}" > "${out_dir}/meta/cmake-cache.txt"
(cd "${out_dir}/app" && find . -maxdepth 1 -type f -printf '%P\n' | sort) > "${out_dir}/meta/app-files.txt"
