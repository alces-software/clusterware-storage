#==============================================================================
# Copyright (C) 2015 Stephen F. Norledge and Alces Software Ltd.
#
# This file/package is part of Alces Clusterware.
#
# Alces Clusterware is free software: you can redistribute it and/or
# modify it under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation, either version 3 of
# the License, or (at your option) any later version.
#
# Alces Clusterware is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this package.  If not, see <http://www.gnu.org/licenses/>.
#
# For more information on the Alces Clusterware, please visit:
# https://github.com/alces-software/clusterware
#==============================================================================
posix_storage_configure() {
    local name path system data datafile
    if [ "$1" == "--system" ]; then
        system="$1"
        shift
    fi
    name="$1"
    path="$2"

    echo -n "Display name [${name}]: " >/dev/stderr
    read display_name
    display_name="${display_name:-${name}}"

    while [ -z "${path}" ]; do
        echo -n "Path: " >/dev/stderr
        read path
    done

    data=$(cat <<EOF
---
name: '${name}'
type: posix
dir: '${path}'
EOF
    )
    if ! datafile="$(echo "${data}" | storage_write_configuration ${system} "${name}.target.yml")"; then
        echo "failed to write ${name}.target.yml configuration"
        return 1
    fi
    data=$(cat <<\EOF
if [ "${cw_POSIX_path:0:1}" == "%" ]; then
  cw_POSIX_path="$(echo "${cw_POSIX_path:1}" | sed -e "s,#{dir},$HOME,g" -e "s,#{name},$(id -un),g")"
  cw_POSIX_path="$(echo "${cw_POSIX_path}" | sed -e "s,#{::Dir.tmpdir},${TMPDIR:-/tmp},g")"
fi
EOF
    )
    if ! datafile="$(echo -e "cw_POSIX_path=\"${path}\"\n${data}" | storage_write_configuration ${system} "${name}.posix.rc")"; then
        echo "failed to write ${name}.posix.rc configuration"
        return 1
    fi
}

posix_storage_sanitize_target() {
    local target
    target="$(echo "$1" | sed 's,//*\([^/]\),/\1,g')"
    if [ "${target:0:1}" == "/" ]; then
        target="${target:1}"
    fi
    while [ "${target:0:3}" == "../" ]; do
        target="${target:3}"
    done
    if [ "${target}" == ".." ]; then
        target=""
    fi
    echo "${target}"
}

posix_storage_list() {
    local name target
    name="$1"
    target=$(posix_storage_sanitize_target "$2")
    . $(storage_get_configuration "${name}")
    (
        cd "${HOME}"
        set -o pipefail
        if find "${cw_POSIX_path}"/"${target}" \
            -mindepth 1 \
            -maxdepth 1 \
            -type d \
            -printf "%AY-%Am-%Ad %AH:%AM       DIR   %f\n" 2>/dev/null | sort -k4; then
            find "${cw_POSIX_path}"/"${target}" \
                -maxdepth 1 \
                -type f \
                -printf "%AY-%Am-%Ad %AH:%AM %9s   %f\n" | sort -k4
        else
            echo "not found: ${target}"
        fi
        set +o pipefail
    )
}

posix_storage_put() {
    local name source target
    name="$1"
    source="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
    target="$(posix_storage_sanitize_target "${3:-$(basename "$source")}")"
    . $(storage_get_configuration "${name}")
    (
        cd "${HOME}"
        mkdir -p "$(dirname "${cw_POSIX_path}"/"${target}")" 2>/dev/null &&
          cp -p "${source}" "${cw_POSIX_path}"/"${target}"
    )
    if [ $? -gt 0 ]; then
        echo "put to storage failed"
        return 1
    else
        echo "${2} -> ${name}:${target}"
    fi
}

posix_storage_get() {
    local name source target targetdir target_is_dir
    name="$1"
    source="$(posix_storage_sanitize_target "$2")"
    if [ -d "$3" ]; then
        targetdir="$3"
        target_is_dir=true
    else
        targetdir="$(dirname "${3}")"
    fi
    if [ ! -d "${targetdir}" ]; then
        echo "get from storage failed - no such target directory"
        return 1
    fi
    if [ "$target_is_dir" ]; then
        target="$(cd "${targetdir}" && pwd)/$(basename "$source")"
    else
        target="$(cd "${targetdir}" && pwd)/$(basename "${3:-$source}")"
    fi
    . $(storage_get_configuration "${name}")
    (
        cd "${HOME}"
        cp -p "${cw_POSIX_path}"/"${source}" "${target}"
    )
    if [ $? -gt 0 ]; then
        echo "get from storage failed"
        return 1
    else
        echo "${name}:${source} -> ${target}"
    fi
}

posix_storage_rm() {
    local name target
    name="$1"
    target="$(posix_storage_sanitize_target "$2")"
    . $(storage_get_configuration "${name}")
    (
        cd "${HOME}"
        if rm -f "${cw_POSIX_path}"/"${target}" 2>/dev/null; then
            bucket="${target%%/*}"
            if [ -d "${cw_POSIX_path}"/"${bucket}" ]; then
                cd "${cw_POSIX_path}"/"${bucket}"
                rmdir --ignore-fail-on-non-empty -p "$(dirname "${target#*/}")"
            fi
        else
            exit 1
        fi
    )
    if [ $? -gt 0 ]; then
        echo "delete from storage failed"
        return 1
    else
        echo "deleted ${name}:${target}"
    fi
}

posix_storage_rmbucket() {
    local name target
    name="$1"
    if [[ "$2" == *"/"* ]]; then
        echo "invalid '/' character in bucket name"
        return 1
    fi
    target="$2"
    . $(storage_get_configuration "${name}")
    (
        cd "${HOME}"
        rmdir "${cw_POSIX_path}"/"${target}" 2>/dev/null
    )
    if [ $? -gt 0 ]; then
        echo "bucket removal failed"
        return 1
    else
        echo "removed bucket ${name}:${target}"
    fi
}

posix_storage_mkbucket() {
    local name target
    name="$1"
    if [[ "$2" == *"/"* ]]; then
        echo "invalid '/' character in bucket name"
        return 1
    fi
    target="$2"
    . $(storage_get_configuration "${name}")
    (
        cd "${HOME}"
        mkdir "${cw_POSIX_path}"/"${target}" 2>/dev/null
    )
    if [ $? -gt 0 ]; then
        echo "bucket creation failed"
        return 1
    else
        echo "created bucket ${name}:${target}"
    fi
}

posix_storage_addbucket() {
    echo "external buckets not supported by 'posix' backend"
    return 1
}
