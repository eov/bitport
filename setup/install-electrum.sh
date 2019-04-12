#!/bin/bash

# Install Electrum, its wrapper scripts and the launcher scripts into the chroot directory.
#
# This script requires the following shell environment variables.
# - LIVE_BOOT_BASE : the top level directory where chroot and image_root directories will be placed.
# - CODE_DIR : the directory where wrapper code is placed.
# - ELECTRUM_TGZ : the path to Electrum-?.?.?.tar.gz file downloaded from https://electrum.org/#download
#
# Function
# - expand Electrum-?.?.?.tar.gz into
#   ${live_boot_base}/electrum/
# - copy
#   ${live_boot_base}/electrum/Electrum-?.?.?/
#   to ${chroot_dir}/opt/electrum/
# - copy
#   ${code_dir}/wrapper/
#   to ${chroot_dir}/opt/electrum/
# - copy
#   ${code_dir}/launcher/*
#   to ${chroot_dir}/usr/local/share/applications/

set -o pipefail

main() {
    if [ ! -d "${LIVE_BOOT_BASE}" ];then
        /bin/echo "LIVE_BOOT_BASE '${LIVE_BOOT_BASE}' doesn't exist!"
        exit 1
    fi
    if [ ! -d "${CODE_DIR}" ];then
        /bin/echo "CODE_DIR '${CODE_DIR}' doesn't exist!"
        exit 1
    fi
    if [ ! -e "${ELECTRUM_TGZ}" ];then
        /bin/echo "ELECTRUM_TGZ '${ELECTRUM_TGZ}' doesn't exist!"
        exit 1
    fi

    local live_boot_base="${LIVE_BOOT_BASE}"
    local code_dir="${CODE_DIR}"
    local electrum_tgz="${ELECTRUM_TGZ}"

    # remove trailing / if any
    live_boot_base=$(/usr/bin/realpath ${live_boot_base})
    code_dir=$(/usr/bin/realpath ${code_dir})

    local chroot_dir="${live_boot_base}/chroot"
    if [ ! -d "${chroot_dir}" ];then
        /bin/echo "error: ${live_boot_base} doesn't have chroot directory"
        exit 1
    fi

    if [ ! -d "${code_dir}/wrapper" ];then
        /bin/echo "error: ${code_dir}/wrapper doesn't exist"
        exit 1
    fi
    if [ ! -d "${code_dir}/launcher" ];then
        /bin/echo "error: ${code_dir}/launcher doesn't exist"
        exit 1
    fi

    # top level directory within the archive "${electrum_tgz}"
    local top_level
    top_level=$(/bin/tar tf "${electrum_tgz}" | /bin/grep '/' | /bin/sed -e 's|/.*||' | /usr/bin/uniq)
    local status="$?"
    if [ "$status" != 0 ]; then
        /bin/echo "error: failed expanding ${electrum_tgz}"
        exit 1
    fi

    # expand the Electrum tar archive under "${electrum_dir}".
    # e.g. Electrum-3.2.2.tar.gz will be expanded as ${electrum_dir}/Electrum-3.2.3/
    local electrum_dir="${live_boot_base}/electrum"
    /bin/mkdir -p "${electrum_dir}"

    /bin/tar xf "${electrum_tgz}" -C "${electrum_dir}"
    status="$?"
    if [ "$status" != 0 ]; then
        /bin/echo "error: failed expanding ${electrum_tgz} into ${electrum_dir}"
        exit 1
    fi
    local electrum_version_dir="${electrum_dir}/${top_level}"

    # copy the expanded ${electrum_version_dir} to ${chroot_dir}/opt/electrum/
    local chroot_electrum_dir="${chroot_dir}/opt/electrum/"
    /usr/bin/sudo /bin/mkdir -p "${chroot_electrum_dir}"
    /bin/echo "copying ${electrum_version_dir} to ${chroot_electrum_dir}"
    /usr/bin/sudo /bin/cp -r "${electrum_version_dir}" "${chroot_electrum_dir}"

    # copy Electrum wrapper and associated scripts to ${chroot_dir}/opt/electrum/
    /bin/echo "copying ${code_dir}/wrapper/ to ${chroot_electrum_dir}"
	/usr/bin/sudo /bin/cp -r "${code_dir}/wrapper" "${chroot_electrum_dir}"

    # copy Electrum wrapper desktop launchers to ${chroot_dir}/usr/local/share/applications/
    local chroot_launcher_dir="${chroot_dir}/usr/local/share/applications"
    /bin/echo "copying ${code_dir}/launcher/* to ${chroot_launcher_dir}"
    /usr/bin/sudo /bin/mkdir -p "${chroot_launcher_dir}"
    /usr/bin/sudo /bin/cp -r "${code_dir}/launcher/." "${chroot_launcher_dir}"
}


main "$@"
