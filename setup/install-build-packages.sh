#!/bin/bash

# This script requires the following shell environment variables.
# - LIVE_BOOT_BASE : the top level directory where chroot and image_root directories will be placed.
# - TARGET_SYSTEM_ARCHITECTURE : either amd64 or i386.
# - TARGET_SYSTEM_DEBIAN_VERSION_CODENAME : one of Debian version codenames.
#     See https://www.debian.org/releases/ for the available codenames.
#
# Function
# - Install Debian packages used for building a live Debian system.
# - Bootstrap a Debian system in the directory `${LIVE_BOOT_BASE}/chroot`
#   based on the target architecture TARGET_SYSTEM_ARCHITECTURE and
#   the target Debian version TARGET_SYSTEM_DEBIAN_VERSION_CODENAME.

main() {
    if [ ! -d "${LIVE_BOOT_BASE}" ]; then
        /bin/echo "LIVE_BOOT_BASE '${LIVE_BOOT_BASE}' doesn't exist!"
        exit 1
    fi
    local live_boot_base="${LIVE_BOOT_BASE}"
    live_boot_base=$(/usr/bin/realpath --canonicalize-existing ${live_boot_base})
    local status="$?"
    if [ "${status}" != 0 ]; then
        exit 1
    fi

    if [ "${TARGET_SYSTEM_ARCHITECTURE}" != 'i386' ] && [ "${TARGET_SYSTEM_ARCHITECTURE}" != 'amd64' ]; then
        /bin/echo "TARGET_SYSTEM_ARCHITECTURE '${TARGET_SYSTEM_ARCHITECTURE}' is not accepted!"
        exit 1
    fi
    local architecture="${TARGET_SYSTEM_ARCHITECTURE}"

    if [ -z "${TARGET_SYSTEM_DEBIAN_VERSION_CODENAME}" ]; then
        /bin/echo "TARGET_SYSTEM_DEBIAN_VERSION_CODENAME is not set"
        exit 1
    fi
    local debian_version="${TARGET_SYSTEM_DEBIAN_VERSION_CODENAME}"

    local chroot_dir="${live_boot_base}/chroot"
    if [ -d "${chroot_dir}" ]; then
        /bin/echo "${chroot_dir} already exists!"
        exit 1
    fi

    install_build_prerequisites

    /bin/mkdir -p "${chroot_dir}"

    bootstrap_live "${chroot_dir}" "${architecture}" "${debian_version}"
}

# install prerequisites packages for building live Debian
install_build_prerequisites() {
    /usr/bin/sudo /usr/bin/apt-get install \
                  debootstrap \
                  squashfs-tools \
                  grub-pc-bin \
                  grub-efi-amd64-bin \
                  syslinux syslinux-common \
                  parted \
                  gdisk \
                  mtools \
                  dosfstools \
                  yad
}

# Bootstrap and Configure Debian
bootstrap_live() {
    local chroot_dir="$1"
    local architecture="$2"
    local debian_version="$3"

    /usr/bin/sudo /usr/sbin/debootstrap \
                  --arch="${architecture}" \
                  --variant=minbase \
                  "${debian_version}" \
                  "${chroot_dir}" \
                  http://ftp.us.debian.org/debian/
}


main "$@"
