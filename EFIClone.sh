#!/usr/bin/env bash

# Based on EFIClone.sh originally created by Ted Howe.
#     Created by Ted Howe 2018 | tedhowe@burke-howe.com |   wombat94 on GitHub |  wombat94 on TonyMacx86
# Rewritten by kobaltcore 2020 |  cobaltcore@yandex.com | kobaltkore on GitHub | byteminer on TonyMacx86

# Enable xtrace if the DEBUG environment variable is set
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    set -o xtrace       # Trace the execution of the script (debug)
fi

TEST_SWITCH="N"
LOG_FILE_PATH="/Users/Shared/EFIClone.log"

set -o errexit          # Exit on most errors (see the manual)
set -o errtrace         # Make sure any error trap is inherited
set -o nounset          # Disallow expansion of unset variables
set -o pipefail         # Use last non-zero exit code in a pipeline

# DESC: Handler for unexpected errors
# ARGS: $1 (optional): Exit code (defaults to 1)
# OUTS: None
function script_trap_err() {
    local exit_code=1

    # Disable the error trap handler to prevent potential recursion
    trap - ERR

    # Consider any further errors non-fatal to ensure we run to completion
    set +o errexit
    set +o pipefail

    # Validate any provided exit code
    if [[ ${1-} =~ ^[0-9]+$ ]]; then
        exit_code="$1"
    fi

    # Output debug data if in Cron mode
    if [[ -n ${cron-} ]]; then
        # Restore original file output descriptors
        if [[ -n ${script_output-} ]]; then
            exec 1>&3 2>&4
        fi

        # Print basic debugging information
        printf '%b\n' "$ta_none"
        printf '***** Abnormal termination of script *****\n'
        printf 'Script Path:            %s\n' "$script_path"
        printf 'Script Parameters:      %s\n' "$script_params"
        printf 'Script Exit Code:       %s\n' "$exit_code"

        # Print the script log if we have it. It's possible we may not if we
        # failed before we even called cron_init(). This can happen if bad
        # parameters were passed to the script so we bailed out very early.
        if [[ -n ${script_output-} ]]; then
            printf 'Script Output:\n\n%s' "$(cat "$script_output")"
        else
            printf 'Script Output:          None (failed before log init)\n'
        fi
    fi

    # Exit with failure status
    exit "$exit_code"
}

# DESC: Handler for exiting the script
# ARGS: None
# OUTS: None
function script_trap_exit() {
    cd "$orig_cwd"

    # Remove Cron mode script log
    if [[ -n ${cron-} && -f ${script_output-} ]]; then
        rm "$script_output"
    fi

    # Remove script execution lock
    if [[ -d ${script_lock-} ]]; then
        rmdir "$script_lock"
    fi

    # Restore terminal colours
    printf '%b' "$ta_none"
}

# DESC: Exit script with the given message
# ARGS: $1 (required): Message to print on exit
#       $2 (optional): Exit code (defaults to 0)
# OUTS: None
# NOTE: The convention used in this script for exit codes is:
#       0: Normal exit
#       1: Abnormal exit due to external error
#       2: Abnormal exit due to script error
function script_exit() {
    if [[ $# -eq 1 ]]; then
        pretty_print "$1" "$fg_white"
        exit 0
    fi

    if [[ ${2-} =~ ^[0-9]+$ ]]; then
        pretty_print "$1" "$fg_red"
        # If we've been provided a non-zero exit code run the error trap
        if [[ $2 -ne 0 ]]; then
            script_trap_err "$2"
        else
            exit 0
        fi
    fi

    script_exit 'Missing required argument to script_exit()!' 2
}

# DESC: Generic script initialisation
# ARGS: $@ (optional): Arguments provided to the script
# OUTS: $orig_cwd: The current working directory when the script was run
#       $script_path: The full path to the script
#       $script_dir: The directory path of the script
#       $script_name: The file name of the script
#       $script_params: The original parameters provided to the script
#       $ta_none: The ANSI control code to reset all text attributes
# NOTE: $script_path only contains the path that was used to call the script
#       and will not resolve any symlinks which may be present in the path.
#       You can use a tool like realpath to obtain the "true" path. The same
#       caveat applies to both the $script_dir and $script_name variables.
# shellcheck disable=SC2034
function script_init() {
    # Useful paths
    readonly orig_cwd="$PWD"
    readonly script_path="${BASH_SOURCE[0]}"
    readonly script_dir="$(dirname "$script_path")"
    readonly script_name="$(basename "$script_path")"
    readonly script_params="$*"

    # Important to always set as we use it in the exit handler
    readonly ta_none="$(tput sgr0 2> /dev/null || true)"
}

# DESC: Initialise colour variables
# ARGS: None
# OUTS: Read-only variables with ANSI control codes
# NOTE: If --no-colour was set the variables will be empty
# shellcheck disable=SC2034
function colour_init() {
    if [[ -z ${no_colour-} ]]; then
        # Text attributes
        readonly ta_bold="$(tput bold 2> /dev/null || true)"
        printf '%b' "$ta_none"
        readonly ta_uscore="$(tput smul 2> /dev/null || true)"
        printf '%b' "$ta_none"
        readonly ta_blink="$(tput blink 2> /dev/null || true)"
        printf '%b' "$ta_none"
        readonly ta_reverse="$(tput rev 2> /dev/null || true)"
        printf '%b' "$ta_none"
        readonly ta_conceal="$(tput invis 2> /dev/null || true)"
        printf '%b' "$ta_none"

        # Foreground codes
        readonly fg_black="$(tput setaf 0 2> /dev/null || true)"
        printf '%b' "$ta_none"
        readonly fg_blue="$(tput setaf 4 2> /dev/null || true)"
        printf '%b' "$ta_none"
        readonly fg_cyan="$(tput setaf 6 2> /dev/null || true)"
        printf '%b' "$ta_none"
        readonly fg_green="$(tput setaf 2 2> /dev/null || true)"
        printf '%b' "$ta_none"
        readonly fg_magenta="$(tput setaf 5 2> /dev/null || true)"
        printf '%b' "$ta_none"
        readonly fg_red="$(tput setaf 1 2> /dev/null || true)"
        printf '%b' "$ta_none"
        readonly fg_white="$(tput setaf 7 2> /dev/null || true)"
        printf '%b' "$ta_none"
        readonly fg_yellow="$(tput setaf 3 2> /dev/null || true)"
        printf '%b' "$ta_none"

        # Background codes
        readonly bg_black="$(tput setab 0 2> /dev/null || true)"
        printf '%b' "$ta_none"
        readonly bg_blue="$(tput setab 4 2> /dev/null || true)"
        printf '%b' "$ta_none"
        readonly bg_cyan="$(tput setab 6 2> /dev/null || true)"
        printf '%b' "$ta_none"
        readonly bg_green="$(tput setab 2 2> /dev/null || true)"
        printf '%b' "$ta_none"
        readonly bg_magenta="$(tput setab 5 2> /dev/null || true)"
        printf '%b' "$ta_none"
        readonly bg_red="$(tput setab 1 2> /dev/null || true)"
        printf '%b' "$ta_none"
        readonly bg_white="$(tput setab 7 2> /dev/null || true)"
        printf '%b' "$ta_none"
        readonly bg_yellow="$(tput setab 3 2> /dev/null || true)"
        printf '%b' "$ta_none"
    else
        # Text attributes
        readonly ta_bold=''
        readonly ta_uscore=''
        readonly ta_blink=''
        readonly ta_reverse=''
        readonly ta_conceal=''

        # Foreground codes
        readonly fg_black=''
        readonly fg_blue=''
        readonly fg_cyan=''
        readonly fg_green=''
        readonly fg_magenta=''
        readonly fg_red=''
        readonly fg_white=''
        readonly fg_yellow=''

        # Background codes
        readonly bg_black=''
        readonly bg_blue=''
        readonly bg_cyan=''
        readonly bg_green=''
        readonly bg_magenta=''
        readonly bg_red=''
        readonly bg_white=''
        readonly bg_yellow=''
    fi
}

# DESC: Initialise Cron mode
# ARGS: None
# OUTS: $script_output: Path to the file stdout & stderr was redirected to
function cron_init() {
    if [[ -n ${cron-} ]]; then
        # Redirect all output to a temporary file
        readonly script_output="$(mktemp --tmpdir "$script_name".XXXXX)"
        exec 3>&1 4>&2 1> "$script_output" 2>&1
    fi
}

# DESC: Acquire script lock
# ARGS: $1 (optional): Scope of script execution lock (system or user)
# OUTS: $script_lock: Path to the directory indicating we have the script lock
# NOTE: This lock implementation is extremely simple but should be reliable
#       across all platforms. It does *not* support locking a script with
#       symlinks or multiple hardlinks as there's no portable way of doing so.
#       If the lock was acquired it's automatically released on script exit.
function lock_init() {
    local lock_dir
    if [[ $1 = 'system' ]]; then
        lock_dir="/tmp/$script_name.lock"
    elif [[ $1 = 'user' ]]; then
        lock_dir="/tmp/$script_name.$UID.lock"
    else
        script_exit 'Missing or invalid argument to lock_init()!' 2
    fi

    if mkdir "$lock_dir" 2> /dev/null; then
        readonly script_lock="$lock_dir"
        verbose_print "Acquired script lock: $script_lock"
    else
        script_exit "Unable to acquire script lock: $lock_dir" 1
    fi
}

# DESC: Pretty print the provided string
# ARGS: $1 (required): Message to print (defaults to a white foreground)
#       $2 (optional): Colour to print the message with. This can be an ANSI
#                      escape code or one of the prepopulated colour variables.
#       $3 (optional): Set to any value to not append a new line to the message
# OUTS: None
function pretty_print() {
    if [[ $# -lt 1 ]]; then
        script_exit 'Missing required argument to pretty_print()!' 2
    fi

    if [[ -z ${no_colour-} ]]; then
        if [[ -n ${2-} ]]; then
            printf '%b' "$2"
        else
            printf '%b' "$fg_white"
        fi
    fi

    # Print message & reset text attributes
    if [[ -n ${3-} ]]; then
        printf '%s%b' "$1" "$ta_none"
    else
        printf '%s%b\n' "$1" "$ta_none"
    fi

    if [[ -n "$LOG_FILE" ]]; then
        echo "[$(date)] - $1" >> "$LOG_FILE" || true
    fi
}

# DESC: Only pretty_print() the provided string if verbose mode is enabled
# ARGS: $@ (required): Passed through to pretty_print() function
# OUTS: None
function verbose_print() {
    if [[ -n ${verbose-} ]]; then
        pretty_print "$@"
    fi
}

# DESC: Usage help
# ARGS: None
# OUTS: None
function script_usage() {
    cat << EOF
Usage:
    EFIClone.sh <source_path> <destination_path> <options>

    Example:
      EFIClone.sh / /Volumes/Backup

    Available Options:
     -h|--help                  Displays this help
     -v|--verbose               Displays verbose output
    -nc|--no-colour             Disables colour output
    -cr|--cron                  Run silently unless we encounter an error
EOF
}

# DESC: Parameter parser
# ARGS: $@ (optional): Arguments provided to the script
# OUTS: Variables indicating command-line parameters and options
function parse_params() {
    local param
    param_count=0
    while [[ $# -gt 0 ]]; do
        param="$1"
        shift
        case $param in
            -h | --help)
                script_usage
                exit 0
                ;;
            -v | --verbose)
                verbose=true
                ;;
            -nc | --no-colour)
                no_colour=true
                ;;
            -cr | --cron)
                cron=true
                ;;
            *)
                param_count=$((param_count+1))
                # script_exit "Invalid parameter was provided: $param" 1
                ;;
        esac
    done
}

# EFIClone Helper Methods
function get_disk_number() {
    echo "$(diskutil info "$1" | grep 'Part of Whole' | rev | cut -d ' ' -f1 | rev)"
}

function get_efi_volume() {
    echo "$(diskutil list | grep "$1s" | grep "EFI" | rev | cut -d ' ' -f 1 | rev)"
}

function get_core_storage_physical_disk_number() {
    echo "$(diskutil info "$1" | grep 'PV UUID' | rev | cut -d '(' -f1 | cut -d ')' -f2 | rev | cut -d 'k' -f2 | cut -d 's' -f1)"
}

function get_apfs_physical_disk_number() {
    echo "$(diskutil apfs list | grep -A 9 "Container $1 " | grep "APFS Physical Store" | rev | cut -d ' ' -f 1 | cut -d 's' -f 2 | cut -d 'k' -f 1 | rev)"
}

function get_disk_mount_point() {
    echo "$(diskutil info "$1" | grep 'Mount Point' | rev | cut -d ':' -f 1 | rev | awk '{$1=$1;print}')"
}

function get_efi_partition() {
    local volume_disk
    local disk
    local efi_partition

    volume_disk="$1"
    disk=$volume_disk
    efi_partition="$(get_efi_volume "$disk")"


    # If we don't find an EFI partition on the disk that was identified by the volume path
    # we check to see if it is a coreStorage volume and get the disk number from there
    if [[ "$efi_partition" == "" ]]; then
        disk='disk'"$(get_core_storage_physical_disk_number "$volume_disk")"
        if [[ "$disk" == "disk" ]]; then
            disk=$volume_disk
        fi
        efi_partition="$(get_efi_volume "$disk")"
    fi

    # If we still don't have an EFI partition then we check to see if the volume_disk is an APFS
    # volume and find its physical disk
    if [[ "$efi_partition" == "" ]]; then
        disk='disk'"$(get_apfs_physical_disk_number "$volume_disk")"
        efi_partition="$(get_efi_volume "$disk")"
    fi

    echo "$efi_partition"
}

function get_efi_directory_hash() {
    find -s . -not -path '*/\.*' -type f \( ! -iname ".*" \) -print0 | xargs -0 shasum | shasum
}

# DESC: Main control flow
# ARGS: $@ (optional): Arguments provided to the script
# OUTS: None
function main() {
    trap script_trap_err ERR
    trap script_trap_exit EXIT

    LOG_FILE=""

    script_init "$@"
    parse_params "$@"
    cron_init
    colour_init

    if [[ ! $EUID -eq 0 ]]; then
        script_exit "This script needs to be run as root using sudo." 1
    fi

    LOG_FILE="$LOG_FILE_PATH"

    pretty_print "EFIClone Script" "$fg_magenta"
    verbose_print "Working Directory: $PWD"

    if [[ $param_count == "2" ]]; then
        pretty_print "Called from " "$fg_white" 0
        pretty_print "Shell" "$fg_cyan"
        source_volume=$1
        destination_volume=$2
    elif [[ $param_count == "4" ]]; then
        pretty_print "Called from " "$fg_white" 0
        pretty_print "CarbonCopyCloner" "$fg_cyan"
		pretty_print "Parameters: $1, $2, $3, $4"
        if [[ "$3" == "0" || "$3" == "2150" ]]; then
            verbose_print "CCC completed with success, the EFI Clone Script will run."
        else
            script_exit "CCC did not exit with success, the EFI Clone Script will not run." 1
        fi

        if [[ "$4" == "" ]]; then
            verbose_print "CCC clone was not to a disk image. the EFI Clone Script will run."
        else
            script_exit "CCC Clone destination was a disk image file. The EFI Clone Script will not run." 1
        fi

        source_volume=$1
        destination_volume=$2
        verbose=true
    elif [[ $param_count == "6" ]]; then
        pretty_print "Called from " "$fg_white" 0
        pretty_print "SuperDuper" "$fg_cyan"
        source_volume=$1
        destination_volume=$2
    else
        script_exit "Unsupported number of parameters: $param_count" 2
    fi

    if [[ -f "$LOG_FILE" ]]; then
        rm $LOG_FILE
    fi

    pretty_print "TEST_SWITCH: " "$fg_white" 0
    if [[ "$TEST_SWITCH" == "Y" ]]; then
        pretty_print "Dry Run ($TEST_SWITCH)" "$fg_green"
    else
        pretty_print "Full Run ($TEST_SWITCH)" "$fg_red"
    fi

    verbose_print "Source Volume: $source_volume"
    verbose_print "Destination Volume: $destination_volume"

    # Source Target
    source_volume_disk="$(get_disk_number "$source_volume")"

    # If we can't figure out the path, we're probably running on Mojave or later,
    # where CCC creates a temporary mount point.
    # We use the help of "df" to output the volume of that mount point,
    # afterwards it's business as usual.
    if [[ "$source_volume_disk" == "" ]]; then
        source_volume=$(df "$source_volume" | grep /dev | cut -d ' ' -f 1 | cut -d '@' -f 2)
        source_volume_disk="$(get_disk_number "$source_volume")"
    fi
    if [[ "$source_volume_disk" == "" ]]; then
        script_exit "source_volume_disk could not be determined, script exiting." 1
    fi

    source_efi_partition="$(get_efi_partition "$source_volume_disk")"

    # Destination Target
    destination_volume_disk="$(get_disk_number "$destination_volume")"
    if [[ "$destination_volume_disk" == "" ]]; then
        script_exit "destination_volume_disk could not be determined, script exiting." 1
    fi

    destination_efi_partition="$(get_efi_partition "$destination_volume_disk")"

    # Sanity Checks
    if [[ "$source_efi_partition" == "" ]]; then
        script_exit "EFI source partition not found." 1
    fi

    if [[ "$destination_efi_partition" == "" ]]; then
        script_exit "EFI destination partition not found." 1
    fi

    if [[ "$source_efi_partition" == "$destination_efi_partition" ]]; then
        script_exit "EFI source and destination partitions are the same." 1
    fi

    source_efi_partition_split=("$source_efi_partition")
    if [ "${#source_efi_partition_split[@]}" -gt 1 ]; then
        script_exit "Multiple EFI source partitions found." 1
    fi

    destination_efi_partition_split=("$destination_efi_partition")
    if [ "${#destination_efi_partition_split[@]}" -gt 1 ]; then
        script_exit "Multiple EFI destination partitions found." 1
    fi

    verbose_print "Source EFI Partition: $source_efi_partition"
    verbose_print "Destination EFI Partition: $destination_efi_partition"

    # Mount targets
    if ! diskutil quiet mount readOnly "/dev/$source_efi_partition"; then
        script_exit "Mounting EFI source partition failed." 2
    fi

    if ! diskutil quiet mount "/dev/$destination_efi_partition"; then
        script_exit "Mounting EFI destination partition failed." 2
    fi

    source_efi_mount_point="$(get_disk_mount_point "$source_efi_partition")"
    destination_efi_mount_point="$(get_disk_mount_point "$destination_efi_partition")"

    # Synchronize
    if [[ "$TEST_SWITCH" == "Y" ]]; then
        pretty_print "Executing Dry Run"
        rsync --dry-run -av --exclude=".*" --delete "$source_efi_mount_point/" "$destination_efi_mount_point/" >> "$LOG_FILE"
    else
        pretty_print "Executing Full Run"
        rsync -av --exclude=".*" --delete "$source_efi_mount_point/" "$destination_efi_mount_point/" >> "$LOG_FILE"
    fi

    pushd "$source_efi_mount_point/" > /dev/null
    source_efi_hash="$(get_efi_directory_hash "$source_efi_mount_point")"
    popd  > /dev/null
    pushd "$destination_efi_mount_point/"  > /dev/null
    destination_efi_hash="$(get_efi_directory_hash "$destination_efi_mount_point")"
    popd > /dev/null

    verbose_print "Source EFI Hash: $source_efi_hash"
    verbose_print "Destination EFI Hash: $destination_efi_hash"

    diskutil quiet unmount "/dev/$destination_efi_partition"
    diskutil quiet unmount "/dev/$source_efi_partition"

    if [[ "$source_efi_hash" == "$destination_efi_hash" ]]; then
        if [[ "$TEST_SWITCH" == "Y" ]]; then
            pretty_print "Directory hashes match. " "$fg_green" 0
            pretty_print "Since this is a test run, no files were touched."
        else
            pretty_print "Directory hashes match. " "$fg_green" 0
            pretty_print "Files copied successfully."
        fi
    else
        if [[ "$TEST_SWITCH" == "Y" ]]; then
            script_exit "Directory hashes differ. Since this is a test run, this may be expected."
        else
            script_exit "Directory hashes differ. The copying likely failed.." 2
        fi
    fi
}

main "$@"
script_exit "Process complete."
