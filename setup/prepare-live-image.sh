#!/bin/bash

# This script requires the following shell environment variables to be set.
# - LIVE_BOOT_BASE : the top level directory where chroot and image_root directories will be placed.
#
# Function
# - Copy necessary files from chroot_dir to image_root organizedd in the following directory
#   structure so that image_root can be directly copied to the device live system partition.
#   LIVE_BOOT_BASE/
#     chroot/
#     image_root/
#       DEBIAN_CUSTOM
#       boot/
#         grub/
#           grub.cfg
#         syslinux/
#           syslinux.cfg
#           menu.c32
#           libutil.c32
#           ...
#       live/
#         vmlinuz
#         initrd
#         filesystem.squashfs
#

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

    local chroot_dir="${live_boot_base}/chroot"
    local image_root="${live_boot_base}/image_root"

    prepare_live_image "${chroot_dir}" "${image_root}"

    /bin/echo 'Completed the build with success.'
}

prepare_live_image() {
    local chroot_dir="$1"
    local image_root="$2"

    # Function
    # 1. Create Squash filesystem image of the whole "${chroot_dir}" and
    #    place it in ${live_boot_base}/image_root/live/
    # 2. Copy the kernel and initramfs to ${live_boot_base}/image_root/live/
    # 3. Write grub boot configuration file ${image_root}/boot/grub/grub.cfg
    # 4. Create "${image_root}/DEBIAN_CUSTOM" for grub
    # 5. Write syslinux boot configuration file ${image_root}/boot/syslinux/syslinux.cfg
    # 6. Copy syslinux library files in ${image_root}/boot/syslinux/
    #
    # Note
    # - On a UEFI system grub is used to boot the live system.
    # - On a BIOS system syslinux is used to boot the live system.
    # - Only one of them will function on any system at a time.
    #

    if [ ! -d "${chroot_dir}" ];then
        /bin/echo "error: ${chroot_dir} doesn't exist"
        exit 1
    fi

    # Create directories for live image files.
    /bin/echo "Creating directory ${image_root}/live"
    /bin/mkdir -p "${image_root}/live"

    #--- Squash filesystem

    # Compress the chroot environment into a Squash filesystem.
    local status
    local squashfs="${image_root}/live/filesystem.squashfs"
    /bin/rm -f "${squashfs}"
    /bin/echo "running mksquashfs to generate ${squashfs} from ${chroot_dir}"
    # accessing "${chroot_dir}" requires sudo
    /usr/bin/sudo \
        /usr/bin/mksquashfs \
        "${chroot_dir}" \
        "${squashfs}" \
        -e boot
    status="$?"
    if [ "${status}" != 0 ]; then
        /bin/echo "error: mksquashfs failed"
        exit 1
    fi

    #--- kernel

    # Copy the kernel and initramfs to the image directory from chroot directory.
    /bin/echo "Copying vmlinuz and initrd.img to ${image_root}/live"

    # Find kernel files under "${chroot_dir}/boot"
    local initrd_path vmlinuz_path config_path system_map_path
    find_kernel_files "${chroot_dir}/boot" initrd_path vmlinuz_path config_path system_map_path
    local initrd_file=$(/usr/bin/basename "${initrd_path}")
    local vmlinuz_file=$(/usr/bin/basename "${vmlinuz_path}")

    # Copy them to ${image_root}/live
    /bin/cp "${initrd_path}" "${image_root}/live"
    /bin/cp "${vmlinuz_path}" "${image_root}/live"
    /bin/cp "${config_path}" "${image_root}/live"
    /bin/cp "${system_map_path}" "${image_root}/live"

    #--- grub config

    # Add the grub menu configuration file.
    /bin/echo "Creating directory ${image_root}/boot/grub"
    /bin/mkdir -p "${image_root}/boot/grub"

    /bin/echo "Writing ${image_root}/boot/grub/grub.cfg"
    /bin/cat <<_EOD > "${image_root}/boot/grub/grub.cfg"
search --set=root --file /DEBIAN_CUSTOM

insmod all_video

set default=debian-live

# Boot automatically after 30 secs.
set timeout=30

menuentry "Debian Live" --id debian-live {
    linux /live/${vmlinuz_file} boot=live
    initrd /live/${initrd_file}
}

menuentry "Debian Live (nomodeset)" --id debian-live-nomodeset {
    linux /live/${vmlinuz_file} boot=live nomodeset
    initrd /live/${initrd_file}
}
_EOD
    status="$?"
    if [ "${status}" != 0 ]; then
        /bin/echo "error: failed writing to ${image_root}/boot/grub/grub.cfg"
        exit 1
    fi

    # Create DEBIAN_CUSTOM under ${image_root} for grub to identify the device.
    /usr/bin/touch "${image_root}/DEBIAN_CUSTOM"

    #--- syslinux config and its libraries that are not installed by the syslinux command

    # Add syslinux menu configuration file.
    /bin/echo "Creating directory ${image_root}/boot/syslinux"
    /bin/mkdir -p "${image_root}/boot/syslinux"

    /bin/echo "Writing ${image_root}/boot/syslinux/syslinux.cfg"
    /bin/cat <<_EOD > "${image_root}/boot/syslinux/syslinux.cfg"
UI menu.c32
PROMPT 0

MENU TITLE Boot menu
TIMEOUT 200
DEFAULT Debian Live nomodeset

LABEL Debian Live nomodeset
  MENU LABEL Debian Live nomodeset
  LINUX /live/${vmlinuz_file}
  APPEND initrd=/live/${initrd_file} boot=live nomodeset
  SAY "Booting Debian Live nomodeset ..."

LABEL Debian Live modeset
  MENU LABEL Debian Live modeset
  LINUX /live/${vmlinuz_file}
  APPEND initrd=/live/${initrd_file} boot=live
  SAY "Booting Debian Live ..."

LABEL Debian Live fail safe
  MENU LABEL Debian Live fail safe
  LINUX /live/${vmlinuz_file}
  APPEND initrd=/live/${initrd_file} boot=live noapic noapm nodma nomce nolapic nomodeset nosmp vga=normal
  SAY "Booting Debian Live fail safe ..."
_EOD
    status="$?"
    if [ "${status}" != 0 ]; then
        /bin/echo "error: failed writing to ${image_root}/boot/syslinux/syslinux.cfg"
        exit 1
    fi

    # Add syslinux library files
    /bin/echo "Copying syslinux library files to ${image_root}/boot/syslinux"
    /bin/cp /usr/lib/syslinux/modules/bios/{hdt.c32,libcom32.c32,libgpl.c32,libmenu.c32,libutil.c32,menu.c32} \
       "${image_root}/boot/syslinux"
    status="$?"
    if [ "${status}" != 0 ]; then
        /bin/echo "error: failed copying /usr/lib/syslinux/modules/bios/{hdt.c32,libcom32.c32,libgpl.c32,libmenu.c32,libutil.c32,menu.c32} to ${image_root}/boot/syslinux"
        exit 1
    fi
}

find_kernel_files() {
    local boot_dir="$1"
    local -n initrd_path_ref="$2"
    local -n vmlinuz_path_ref="$3"
    local -n config_path_ref="$4"
    local -n system_map_path_ref="$5"

    local initrd_glob="${boot_dir}/initrd*"
    local vmlinuz_glob="${boot_dir}/vmlinuz*"
    local config_glob="${boot_dir}/config*"
    local system_map_glob="${boot_dir}/System.map*"

    shopt -s nullglob
    find_glob_match_one ${initrd_glob} initrd_path_ref
    find_glob_match_one ${vmlinuz_glob} vmlinuz_path_ref
    find_glob_match_one ${config_glob} config_path_ref
    find_glob_match_one ${system_map_glob} system_map_path_ref
    shopt -u nullglob
}

find_glob_match_one() {
    local glob_exp="$1"
    local -n path_ref="$2"

    local files=(${glob_exp})
    if [ "${#files[@]}" = 0 ]; then
        /bin/echo "error: can't find any file that match glob ${glob_exp}"
        exit 1
    elif [ "${#files[@]}" = 1 ]; then
        path_ref="${files[0]}"
    else
        /bin/echo "error: found more than a single match for ${glob_exp}"
        exit 1
    fi
}


main "$@"
