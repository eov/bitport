#!/bin/bash

# This script requires the following shell environment variables.
# - LIVE_BOOT_BASE : the top level directory where chroot and image_root directories will be placed.
# - CODE_DIR : the directory where wrapper code is placed.
#
# Function
# - Overwrite applications config files in the chroot directory.
# - Copy ${code_dir}/debian/* to ${chroot_dir}/
#

main() {
    if [ ! -d "${LIVE_BOOT_BASE}" ]; then
        /bin/echo "LIVE_BOOT_BASE '${LIVE_BOOT_BASE}' doesn't exist!"
        exit 1
    fi
    local live_boot_base="${LIVE_BOOT_BASE}"

    if [ ! -d "${CODE_DIR}" ];then
        /bin/echo "CODE_DIR ${CODE_DIR} doesn't exist!"
        exit 1
    fi
    local code_dir="${CODE_DIR}"

    live_boot_base=$(/usr/bin/realpath --canonicalize-existing "${live_boot_base}")
    code_dir=$(/usr/bin/realpath --canonicalize-existing "${code_dir}")

    local chroot_dir="${live_boot_base}/chroot"
    if [ ! -d "${chroot_dir}" ];then
        /bin/echo "error: ${chroot_dir} doesn't have chroot directory"
        exit
    fi
    if [ ! -d "${code_dir}/debian" ];then
        /bin/echo "error: ${code_dir}/debian/ doesn't exist"
        exit
    fi

    local customization=(
        '/etc/lightdm/lightdm.conf'
        '/etc/sudoers'
        '/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml'
        '/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/thunar.xml'
    )

    local cust dest_path dest_orig
    for cust in ${customization[@]}; do
        dest_path="${chroot_dir}${cust}"
        dest_orig="${dest_path},original"

        if [ ! -e "${dest_orig}" ]; then
            if [ -e "${dest_path}" ]; then
                /usr/bin/sudo /bin/mv "${dest_path}" "${dest_orig}"
            else
                /usr/bin/sudo /bin/touch "${dest_orig}"
            fi
        fi
        /usr/bin/sudo /bin/cp "${code_dir}/debian${cust}" "${dest_path}"
    done
}


main "$@"
