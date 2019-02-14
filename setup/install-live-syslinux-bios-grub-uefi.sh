#!/bin/bash

# This script requires the following shell environment variables.
# - LIVE_BOOT_BASE : the top level directory where chroot and image_root directories will be placed.
#
# Function
# - Create three GPT partitions on a USB drive.
#   partition 1: EFI
#   partition 2: Debian Live system
#   partition 3: Data partition
# - Install Debian Live system and grub on the second partition.
#

set -o pipefail

# The following definition should be the same as the one in wrapper/electrum-luks-constants
WALLET_MEDIA_VOLUME_LABEL='EDATA'

main() {
    local device
    if [ $# = 1 ]; then
        device="$1"
    else
        /bin/echo "Usage: $0 <target-device>"
        /bin/echo "Note:"
        /bin/echo "<target-device> should be a device and not a partition."
        /bin/echo "To display the currently attached devices run /bin/lsblk"
        exit
    fi

    if [ ! -d "${LIVE_BOOT_BASE}" ]; then
        /bin/echo "LIVE_BOOT_BASE '${LIVE_BOOT_BASE}' doesn't exist!"
        exit 1
    fi
    local live_boot_base="${LIVE_BOOT_BASE}"
    live_boot_base=$(/usr/bin/realpath ${live_boot_base})

    local device_type
    find_device_type "${device}" device_type
    if [ "${device_type}" != 'disk' ];then
        /bin/echo "error: ${device} is not a device."
        /bin/echo "Check the result of /bin/lsblk to get the right device."
        exit 1
    fi

    local image_root="${live_boot_base}/image_root"

    check_read_device "${device}"

    partition_device "${device}" "${image_root}"

    format_device_filesystem "${device}"

    install_system_on_drive "${image_root}" "${device}"
}

find_device_type() {
    local device="$1"
    local -n type_ref="$2"

    local output status
    output=$(/bin/lsblk -o TYPE ${device} | grep 'disk')
    status="$?"
    if [ "${status}" = 0 ];then
        type_ref='disk'
    else
        # either a non-existent divice or a partition
        type_ref='notdisk'
    fi
}

# check if we have a right device
check_read_device() {
    local device="$1"

    local text1 text2 text3 text4 text5 text6 text7
    local status

    text1="<b>Going to read data from ${device} for a few seconds to see if you specified the intended device.\n"
    text2='Please watch the <span foreground="blue">access light</span> of the USB device right after pressing OK to this dialog.</b>'
    /usr/bin/yad \
        --title "Check Device" \
        --text "${text1}${text2}" \
        --button 'OK:0' --no-escape \
        --image 'dialog-information' --window-icon 'dialog-information' \
        --center --borders 12 --fixed

    # read in 200MB from ${device}
    /bin/echo "reading some data out of ${device}"
    /usr/bin/sudo /bin/dd if=${device} of=/dev/null bs=1M count=200
    status="$?"
    if [ "${status}" != '0' ]; then
        /bin/echo "canceling operation."
        exit 1
    fi

    text1='<b>Did you see the access light on your USB device?\n'
    text2='If so it is good to proceed to work on your device.\n'
    text3="Going forward the command will completely erase data on the device ${device}.\n\n"
    text4='If you are not 100% sure that the device you provided is the one\n'
    text5='for your USB drive press Exit here to stop.\n'
    text6='<span foreground="red">Warning: In case you provided a wrong device name proceeding here\n'
    text7='will destroy data on an uninteded device which could be the host system drive.</span></b>'
    /usr/bin/yad \
        --title "Check Device" \
        --text "${text1}${text2}${text3}${text4}${text5}${text6}${text7}" \
        --button='Exit:1' --button='Go:0' --no-escape \
        --image 'dialog-question' --window-icon='dialog-question' \
        --center --fixed --borders=12
    status="$?"
    if [ "${status}" != '0' ]; then
        /bin/echo "canceling operation."
        exit 1
    fi
}

# Create GPT partition table on the device.
# Partition 1:
#   From 1 MiB to 200 MiB.
#   EFI partition.
# Partition 2:
#   From 200 MiB to 200 MiB + multiple of 1 MiB that is large enough to accomodate
#   grub config, kernel, initrd, and the Squash filesystem image of live filesystem.
#   Add legacy_boot flag in 2nd partition for the MBR bootloader (that will be installed later)
#   to be able to find the partition for syslinux.
# Partition 3:
#   From the next to the end of the partition 2 to the end of the drive.
#   Data partition.
#
partition_device() {
    local device="$1"
    local image_root="$2"

    # Find the partition size adequate to accomodate all files under "${image_root}".
    # We use MiB for parted position parameters for optimal alignment as suggested in
    # https://askubuntu.com/questions/932545/the-resulting-partition-is-not-properly-aligned-for-best-performance

    /bin/echo "checking if the device ${device} has capacity to hold all files under ${image_root}."
    local output
    local status
    output=$(/bin/lsblk -n -o TYPE,SIZE --bytes ${device})
    status="$?"
    if [ "${status}" != '0' ]; then
        exit 1
    fi
    local device_size=$(/bin/echo "${output}" | /bin/grep 'disk' | /bin/sed -e 's/disk *//')
    /bin/echo "size of ${device}: ${device_size} bytes"

    local total_bytes
    total_bytes=$(/usr/bin/du -s --bytes "${image_root}" | /bin/sed -e 's/[ \t].*//' )
    status="$?"
    if [ "${status}" != '0' ]; then
        exit 1
    fi
    /bin/echo "total size for the image files in ${image_root} is around ${total_bytes} bytes"

    local _1_MiB='1048576'
    local device_size_MiB=$(( ${device_size} / ${_1_MiB} ))
    local multiple=$(( ${total_bytes} / ${_1_MiB} ))
    local suggested_system_MiB=$(( ${multiple} + 256 ))  # add extra space of 256 MiB
    local suggested_system_bytes=$(( ${suggested_system_MiB} * ${_1_MiB} ))
    if [ "${suggested_system_bytes}" -ge "${device_size}" ]; then
        /bin/echo "The device ${device} is too small to accomodate our Debian Live system."
        exit 2
    fi
    /bin/echo "suggested partition_size for the system: ${suggested_system_bytes} bytes"

    local p1_start='1MiB'
    local p1_end='200MiB'
    local p2_start='200MiB'
    local p2_end="$((200 + ${suggested_system_MiB}))MiB"
    local p3_start="$((200 + ${suggested_system_MiB}))MiB"
    local p3_end='100%'

    local text1 text2 text3 text4 text5 text6
    text1="<b>Total size of the device ${device} is ${device_size_MiB} MiB.\n\n"
    text2="We are going to create partitions on the USB device ${device} :\n"
    text3="  partition 1: ${p1_start} to ${p1_end}.\n"
    text4="  partition 2: ${p2_start} to ${p2_end}.\n"
    text5="  partition 3: ${p3_start} to ${p3_end}.\n"
    text6="\nThis is the last chance to stop the process in case you want to change the device.</b>"

    /usr/bin/yad \
        --title "Partition Device" \
        --text "${text1}${text2}${text3}${text4}${text5}${text6}" \
        --button='Exit:1' --button='Go:0' --no-escape \
        --image 'dialog-question' --window-icon='dialog-question' \
        --center --fixed --borders=12
    status="$?"
    if [ "${status}" != '0' ]; then
        /bin/echo "canceling partitioning the device."
        exit 1
    fi

    # Erase partition table signatures of the type iso9660 which will interfere with successful booting
    # but can not be removed by parted.
    # Trying to boot with a remaining iso9660 signature will lead to a hard to diagnose boot error:
    #	error: invalid magic number.
    #	error: you need to load the kernel first.
    #
    /usr/bin/sudo /sbin/wipefs --all --types iso9660 "${device}"

    # create three partitions on ${device},
    /bin/echo "creating partition: ${p1_start} to ${p1_end}; partition: ${p2_start} to ${p2_end}; partition: ${p3_start} to ${p3_end}"
    /usr/bin/sudo \
        /sbin/parted --script --align optimal \
        "${device}" \
        mklabel gpt \
        mkpart ESP fat32 "${p1_start}" "${p1_end}" \
            name 1 EFI \
            set 1 esp on \
        mkpart primary fat32 "${p2_start}" "${p2_end}" \
            name 2 Debian \
            set 2 legacy_boot on \
            set 2 msftdata on \
        mkpart primary fat32 "${p3_start}" "${p3_end}" \
            name 3 Data \
            set 3 msftdata on

    /usr/bin/sudo /sbin/partprobe

    # mkfs in the following step could fail if we don't wait a few seconds right after editing the partition table.
    /bin/sleep 5
}

# Format all partitions of ${device} and add filesystem labels
# Partition 1:
#   filesystem: FAT 32
#   label:
# Partition 2:
#   filesystem: FAT 32
#   label: DEBIAN
# Partition 3:
#   filesystem: FAT 32
#   label: ${WALLET_MEDIA_VOLUME_LABEL}
#
format_device_filesystem() {
    local device="$1"

    local partition_1="${device}1"
    local partition_2="${device}2"
    local partition_3="${device}3"
    local status

    /bin/echo "formating partition ${partition_1}"
    /usr/bin/sudo /sbin/mkfs.vfat -F 32 "${partition_1}"
    status="$?"
    if [ "${status}" != '0' ]; then
        /bin/echo "failed /sbin/mkfs.vfat -F 32 ${partition_1}"
        exit 1
    fi

    /bin/echo "formating partition ${partition_2}"
    /usr/bin/sudo /sbin/mkfs.vfat -F 32 -n DEBIAN "${partition_2}"
    status="$?"
    if [ "${status}" != '0' ]; then
        /bin/echo "failed /sbin/mkfs.vfat -F 32 -n DEBIAN ${partition_2}"
        exit 1
    fi

    /bin/echo "formating partition ${partition_3}"
    /usr/bin/sudo /sbin/mkfs.vfat -F 32 -n "${WALLET_MEDIA_VOLUME_LABEL}" "${partition_3}"
    status="$?"
    if [ "${status}" != '0' ]; then
        /bin/echo "failed /sbin/mkfs.vfat -F 32 -n ${WALLET_MEDIA_VOLUME_LABEL} ${partition_3}"
        exit 1
    fi
}

#
# Install grub bootloader, syslnux bootloader, and the live system on the partitions of ${device}
#
# Booting on a BIOS system
# - MBR bootloader gptmbr.bin finds the GPT partition marked with the legacy_boot flag.
# - syslinux bootloader on the found GPT partition will find syslinux.cfg and load syslinux libraries.
# - syslinux identifies the Linux kernel and initrd to boot the kernel by passing the arguments listed in /boot/syslinux/syslinux.cfg.
#
# Booting on a UEFI system
# - UEFI identifies the FAT partition that has the UEFI bootloader.
# - grub bootloader finds its configuration file /boot/grub/grub.cfg to boot the Linux kernel by passing the arguments listed in the config.
#
install_system_on_drive() {
    local image_root="$1"
    local device="$2"

    local partition_1="${device}1"
    local partition_2="${device}2"
    local status

    #--- mount device filesystems

    local efi_mount_point sys_mount_point

    efi_mount_point=$(/bin/mktemp --directory --tmpdir 'efi.XXXXXXXXXX')
    status="$?"
    if [ "${status}" != '0' ]; then
        exit 1
    fi
    /bin/echo "created temporary mount directory ${efi_mount_point}"

    sys_mount_point=$(/bin/mktemp --directory --tmpdir 'sys.XXXXXXXXXX')
    status="$?"
    if [ "${status}" != '0' ]; then
        exit 1
    fi
    /bin/echo "created temporary mount directory ${sys_mount_point}"

    /bin/echo "mounting ${partition_1} at ${efi_mount_point}"
    /usr/bin/sudo /bin/mount "${partition_1}" "${efi_mount_point}"
    status="$?"
    if [ "${status}" != '0' ]; then
        /bin/echo "failed /bin/mount ${partition_1} ${efi_mount_point}"
        exit 1
    fi

    /bin/echo "mounting ${partition_2} at ${sys_mount_point}"
    /usr/bin/sudo /bin/mount "${partition_2}" "${sys_mount_point}"
    status="$?"
    if [ "${status}" != '0' ]; then
        /bin/echo "failed /bin/mount ${partition_2} ${sys_mount_point}"
        exit 1
    fi

    #--- install grub in EFI partition and live partition

    /bin/echo "running grub-install --target=x86_64-efi --efi-directory=${efi_mount_point} --boot-directory=${sys_mount_point}/boot ${device}"
    /usr/bin/sudo \
        /usr/sbin/grub-install \
        --target=x86_64-efi \
        --efi-directory="${efi_mount_point}" \
        --boot-directory="${sys_mount_point}/boot" \
        --removable \
        --recheck \
        "${device}"
    status="$?"
    if [ "${status}" != '0' ]; then
        /bin/echo "failed grub-install --target=x86_64-efi --efi-directory=${efi_mount_point} --boot-directory=${sys_mount_point}/boot"
        exit 1
    fi

    #--- install live system

    /bin/echo "copying ${image_root}/. to ${sys_mount_point}"
    /usr/bin/sudo /bin/cp -r "${image_root}/." "${sys_mount_point}"
    status="$?"
    if [ "${status}" != '0' ]; then
        /bin/echo "failed /bin/cp ${image_root}/. ${sys_mount_point}"
        exit 1
    fi

    #--- unmount device filesystems

    /bin/echo "unmounting ${efi_mount_point}"
    /usr/bin/sudo /bin/umount "${efi_mount_point}"
    status="$?"
    if [ "${status}" != '0' ]; then
        /bin/echo "failed /bin/umount ${efi_mount_point}"
        exit 1
    fi

    /bin/echo "unmounting ${sys_mount_point}"
    /usr/bin/sudo /bin/umount "${sys_mount_point}"
    status="$?"
    if [ "${status}" != '0' ]; then
        /bin/echo "failed /bin/umount ${sys_mount_point}"
        exit 1
    fi

    /bin/sleep 2

    /bin/echo "removing temporary mount directory ${efi_mount_point}"
    /bin/rm -r "${efi_mount_point}"
    /bin/echo "removing temporary mount directory ${sys_mount_point}"
    /bin/rm -r "${sys_mount_point}"

    #--- install syslinux

    # Install syslinux bootloader in VBR and /boot/syslinux/ of ${partition_2}.
    # This command needs to be run without mounting ${partition_2}.
    # This will install ldlinux.sys and ldlinux.c32 under the directory /boot/syslinux/
    # which should have been created in the previous step.
    /bin/echo "running syslinux --directory /boot/syslinux/ --install ${partition_2}"
    /usr/bin/sudo \
        /usr/bin/syslinux \
        --directory '/boot/syslinux/' \
        --install \
        "${partition_2}"
    status="$?"
    if [ "${status}" != '0' ]; then
        /bin/echo "failed syslinux --directory /boot/syslinux/ --install ${partition_2}"
        exit 1
    fi

    /bin/echo "Copying syslinux gptmbr.bin to MBR of ${device}"
    /usr/bin/sudo \
        /bin/dd \
        bs=440 count=1 conv=notrunc \
        if='/usr/lib/syslinux/mbr/gptmbr.bin' \
        of="${device}"
    status="$?"
    if [ "${status}" != '0' ]; then
        /bin/echo "failed dd bs=440 count=1 conv=notrunc if=/usr/lib/syslinux/mbr/gptmbr.bin of=${device}"
        exit 1
    fi
}


main "$@"
