#!/bin/bash

set -eu -o pipefail

## Update docker image tag, because kernel build is using `uname -r` when defining package version variable
# KERNEL_VERSION=$(curl -s https://www.kernel.org | grep '<strong>' | head -3 | tail -1 | cut -d'>' -f3 | cut -d'<' -f1)
KERNEL_VERSION=hwe-5.13
UBUNTU_REL=14.14
PKGREL=1
#KERNEL_REPOSITORY=git://kernel.ubuntu.com/virgin/linux-stable.git
KERNEL_REPOSITORY=git://git.launchpad.net/~ubuntu-kernel/ubuntu/+source/linux/+git/focal
REPO_PATH=$(pwd)
WORKING_PATH=/root/work
KERNEL_PATH="${WORKING_PATH}/linux-kernel"

### Debug commands
echo "KERNEL_VERSION=$KERNEL_VERSION"
echo "${WORKING_PATH}"
echo "Current path: ${REPO_PATH}"
echo "CPU threads: $(nproc --all)"
grep 'model name' /proc/cpuinfo | uniq

get_next_version () {
  echo $PKGREL
}

get_local_version () {
  echo $UBUNTU_REL
}

### Clean up
rm -rfv ./*.deb

mkdir "${WORKING_PATH}" && cd "${WORKING_PATH}"
cp -rf "${REPO_PATH}"/{patches,templates} "${WORKING_PATH}"
rm -rf "${KERNEL_PATH}"

### Dependencies
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y build-essential fakeroot libncurses-dev bison flex libssl-dev libelf-dev \
  openssl dkms libudev-dev libpci-dev libiberty-dev autoconf wget xz-utils git \
  bc rsync cpio dh-modaliases debhelper kernel-wedge curl

### get Kernel
git clone --depth 1 --single-branch --branch "${KERNEL_VERSION}" \
  "${KERNEL_REPOSITORY}" "${KERNEL_PATH}"
cd "${KERNEL_PATH}" || exit

#### Create patch file with custom drivers
echo >&2 "===]> Info: Creating patch file... "
KERNEL_VERSION="${KERNEL_VERSION}" WORKING_PATH="${WORKING_PATH}" "${REPO_PATH}/patch_driver.sh"

#### Apply patches
cd "${KERNEL_PATH}" || exit

echo >&2 "===]> Info: Applying patches... "
[ ! -d "${WORKING_PATH}/patches" ] && {
  echo 'Patches directory not found!'
  exit 1
}


while IFS= read -r file; do
  echo "==> Adding $file"
  patch -p1 <"$file"
done < <(find "${WORKING_PATH}/patches" -type f -name "*.patch" | sort)

chmod a+x "${KERNEL_PATH}"/debian/rules
chmod a+x "${KERNEL_PATH}"/debian/scripts/*
chmod a+x "${KERNEL_PATH}"/debian/scripts/misc/*

echo >&2 "===]> Info: Bulding src... "

cd "${KERNEL_PATH}"
make clean
cp "${WORKING_PATH}/templates/default-config" "${KERNEL_PATH}/.config"
make olddefconfig

# Get rid of the dirty tag
echo "" >"${KERNEL_PATH}"/.scmversion

# Build Deb packages
make -j "$(getconf _NPROCESSORS_ONLN)" deb-pkg LOCALVERSION="-$(get_local_version)-hwe-t2-big-sur KDEB_PKGVERSION="$(make kernelversion)-$(get_local_version)-$(get_next_version)"

#### Copy artifacts to shared volume
echo >&2 "===]> Info: Copying debs and calculating SHA256 ... "
#cp -rfv ../*.deb "${REPO_PATH}/"
#cp -rfv "${KERNEL_PATH}/.config" "${REPO_PATH}/kernel_config_${KERNEL_VERSION}"
cp -rfv "${KERNEL_PATH}/.config" "/tmp/artifacts/kernel_config_${KERNEL_VERSION}"
cp -rfv ../*.deb /tmp/artifacts/
sha256sum ../*.deb >/tmp/artifacts/sha256
