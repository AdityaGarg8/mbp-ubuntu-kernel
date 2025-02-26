#!/bin/bash

set -eu -o pipefail

BUILD_PATH=/tmp/build-kernel

# Patches
T2_PATCHES_GIT_URL=https://github.com/t2linux/linux-t2-patches.git
T2_PATCHES_BRANCH_NAME=main
T2_PATCHES_COMMIT_HASH=HEAD

rm -rf "${BUILD_PATH}"
mkdir -p "${BUILD_PATH}"
cd "${BUILD_PATH}" || exit

### AppleSMC and BT aunali fixes
git clone --single-branch --branch ${T2_PATCHES_BRANCH_NAME} ${T2_PATCHES_GIT_URL} \
  "${BUILD_PATH}/linux-mbp-arch"
cd "${BUILD_PATH}/linux-mbp-arch" || exit
git checkout ${T2_PATCHES_COMMIT_HASH}

while IFS= read -r file; do
  echo "==> Adding ${file}"
  cp -rfv "${file}" "${WORKING_PATH}"/patches/"${file##*/}"
done < <(find "${BUILD_PATH}/linux-mbp-arch" -type f -name "*.patch")
