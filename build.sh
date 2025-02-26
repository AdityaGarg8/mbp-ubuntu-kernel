#!/bin/bash

set -eu -o pipefail

### Environment variable
export DEBIAN_FRONTEND=noninteractive

### Dependencies in docker
apt-get update
apt-get install -y lsb-release

KERNEL_VERSION=6.13.4
PKGREL=3
DISTRO=$(lsb_release -i | cut -d ":" -f 2 | xargs)
CODENAME=$(lsb_release -c | cut -d ":" -f 2 | xargs)

if [[ ${DISTRO} = Debian ]]
then
CONFIG=debian
else
CONFIG=ubuntu
fi

#KERNEL_REPOSITORY=git://kernel.ubuntu.com/virgin/linux-stable.git
KERNEL_REPOSITORY=https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git

REPO_PATH=$(pwd)
WORKING_PATH=/root/work
KERNEL_PATH="${WORKING_PATH}/linux-kernel"

### Debug commands
echo "Kernel version: ${KERNEL_VERSION}"
echo "Config distro: ${CONFIG}"
echo "Working path: ${WORKING_PATH}"
echo "Kernel repository: ${KERNEL_REPOSITORY}"
echo "Current path: ${REPO_PATH}"
echo "CPU threads: $(nproc --all)"
grep 'model name' /proc/cpuinfo | uniq

get_next_version () {
  echo $PKGREL
}

### Clean up
rm -rfv ./*.deb

mkdir "${WORKING_PATH}" && cd "${WORKING_PATH}"
cp -rf "${REPO_PATH}"/{patches,templates} "${WORKING_PATH}"
rm -rf "${KERNEL_PATH}"

### Dependencies
apt-get install -y build-essential fakeroot libncurses-dev bison flex libssl-dev libelf-dev \
  openssl dkms libudev-dev libpci-dev libiberty-dev autoconf wget xz-utils git \
  libcap-dev bc rsync cpio debhelper kernel-wedge curl gawk dwarves zstd python3

### get Kernel and Drivers
git clone --depth 1 --single-branch --branch "v${KERNEL_VERSION}" \
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

#chmod a+x "${KERNEL_PATH}"/debian/rules
#chmod a+x "${KERNEL_PATH}"/debian/scripts/*
#chmod a+x "${KERNEL_PATH}"/debian/scripts/misc/*

echo >&2 "===]> Info: Bulding src... "

cd "${KERNEL_PATH}"
make clean

# Make config friendly with vanilla kernel
sed -i 's/CONFIG_VERSION_SIGNATURE=.*/CONFIG_VERSION_SIGNATURE=""/g' "${WORKING_PATH}/templates/default-config-${CONFIG}"
sed -i 's/CONFIG_SYSTEM_TRUSTED_KEYS=.*/CONFIG_SYSTEM_TRUSTED_KEYS=""/g' "${WORKING_PATH}/templates/default-config-${CONFIG}"
sed -i 's/CONFIG_SYSTEM_REVOCATION_KEYS=.*/CONFIG_SYSTEM_REVOCATION_KEYS=""/g' "${WORKING_PATH}/templates/default-config-${CONFIG}"

# I want silent boot
sed -i 's/CONFIG_CONSOLE_LOGLEVEL_DEFAULT=.*/CONFIG_CONSOLE_LOGLEVEL_DEFAULT=4/g' "${WORKING_PATH}/templates/default-config-${CONFIG}"
sed -i 's/CONFIG_CONSOLE_LOGLEVEL_QUIET=.*/CONFIG_CONSOLE_LOGLEVEL_QUIET=1/g' "${WORKING_PATH}/templates/default-config-${CONFIG}"
sed -i 's/CONFIG_MESSAGE_LOGLEVEL_DEFAULT=.*/CONFIG_MESSAGE_LOGLEVEL_DEFAULT=4/g' "${WORKING_PATH}/templates/default-config-${CONFIG}"

# Copy the modified config
cp -v "${WORKING_PATH}/templates/default-config-${CONFIG}" "${KERNEL_PATH}/.config"

# Disable debug info
./scripts/config --undefine GDB_SCRIPTS
./scripts/config --undefine DEBUG_INFO
./scripts/config --undefine DEBUG_INFO_SPLIT
./scripts/config --undefine DEBUG_INFO_REDUCED
./scripts/config --undefine DEBUG_INFO_COMPRESSED
./scripts/config --set-val  DEBUG_INFO_NONE       y
./scripts/config --set-val  DEBUG_INFO_DWARF5     n

make olddefconfig

# Enable T2 drivers
./scripts/config --module CONFIG_HID_APPLETB_BL
./scripts/config --module CONFIG_HID_APPLETB_KBD
./scripts/config --module CONFIG_DRM_APPLETBDRM
./scripts/config --module CONFIG_BT_HCIBCM4377
./scripts/config --module CONFIG_APFS_FS
./scripts/config --enable CONFIG_MODULE_FORCE_UNLOAD

# Get rid of the dirty tag
echo "" >"${KERNEL_PATH}"/.scmversion

# Build Deb packages
make -j "$(getconf _NPROCESSORS_ONLN)" deb-pkg LOCALVERSION=-${PKGREL}-t2-"${CODENAME}" KDEB_PKGVERSION="$(make kernelversion)-$(get_next_version)"

#### Copy artifacts to shared volume
echo >&2 "===]> Info: Copying debs and calculating SHA256 ... "
cp -rfv "${KERNEL_PATH}/.config" "/tmp/artifacts/kernel_config_${KERNEL_VERSION}-${CODENAME}"
cp -rfv ../*.deb /tmp/artifacts/

if [[ (${#KERNEL_VERSION} = 3) || (${#KERNEL_VERSION} = 4) ]]
then
mv "/tmp/artifacts/linux-libc-dev_${KERNEL_VERSION}.0-${PKGREL}_amd64.deb" "/tmp/artifacts/linux-libc-dev_${KERNEL_VERSION}.0-${PKGREL}-${CODENAME}_amd64.deb"
else
mv "/tmp/artifacts/linux-libc-dev_${KERNEL_VERSION}-${PKGREL}_amd64.deb" "/tmp/artifacts/linux-libc-dev_${KERNEL_VERSION}-${PKGREL}-${CODENAME}_amd64.deb"
fi
sha256sum ../*.deb >/tmp/artifacts/sha256-"${CODENAME}"
