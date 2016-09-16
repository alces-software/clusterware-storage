#==============================================================================
# Copyright (C) 2016 Stephen F. Norledge and Alces Software Ltd.
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
http_storage_configure() {
    local name base_url system data datafile
    if [ "$1" == "--system" ]; then
        system="$1"
        shift
    fi
    name="$1"
    path="$2"

    echo -n "Display name [${name}]: " >/dev/stderr
    read display_name
    display_name="${display_name:-${name}}"

    while [ -z "${base_url}" ]; do
        echo -n "Base URL: " >/dev/stderr
        read base_url
    done

    data=$(cat <<EOF
---
name: '${name}'
type: http
base_url: '${base_url}'
EOF
    )
    if ! datafile="$(echo "${data}" | storage_write_configuration ${system} "${name}.target.yml")"; then
        echo "failed to write ${name}.target.yml configuration"
        return 1
    fi
    data=$(cat <<EOF
cw_STORAGE_http_base_url="${base_url}"
EOF
    )
    if ! datafile="$(echo "${data}" | storage_write_configuration ${system} "${name}.http.rc")"; then
        echo "failed to write ${name}.http.rc configuration"
        return 1
    fi
}

http_storage_list() {
    local name target data dirs files tgt
    name="$1"
    target="$2"
    . $(storage_get_configuration "${name}")
    # fetch manifest file
    if [ "${target}" ]; then
        manifest="${target}/manifest.txt"
    else
        manifest="manifest.txt"
    fi
    manifest=$(curl -s -f ${cw_STORAGE_http_base_url}/${manifest})
    if [ "${manifest}" ] && ! echo "${manifest[*]}" | grep -q '<Error>'; then
        # fetch each file within manifest file
        dirs="$(echo "$manifest" | grep "/$" | sort)"
        files="$(echo "$manifest" | grep -v "/$" | sort)"
        for f in ${dirs}; do
            printf "%s %9s   %s\n" "                " "DIR" "${f%?}"
        done
        for f in ${files}; do
            if [ "$target" ]; then
                tgt="${target}/$f"
            else
                tgt="$f"
            fi
            if data=$(curl -s --head -f ${cw_STORAGE_http_base_url}/${tgt} | tr -d '\r'); then
                size=$(echo "$data" | grep "Content-Length" | cut -f2 -d' ')
                if date=$(echo "$data" | grep "Last-Modified" | cut -f2- -d' '); then
                    date=$(date -d "${date}" +"%Y-%m-%d %H:%M")
                else
                    date="<n/a>           "
                fi
                printf "%s %9s   %s\n" "${date}" "${size}" "${f}"
            fi
        done
    else
        echo "No manifest found for: ${cw_STORAGE_http_base_url}"
    fi
}

http_storage_put() {
    echo "uploading not supported by 'http' backend"
    return 1
}

http_storage_get() {
    local name source target targetdir target_is_dir recursive
    name="$1"
    shift
    while [[ "$1" == -* ]]; do
	shift
    done
    source=$1
    if [ -d "$2" ]; then
        targetdir="$2"
        target_is_dir=true
    else
        targetdir="$(dirname "${2}")"
    fi
    if [ ! -d "${targetdir}" ]; then
        echo "get from storage failed - no such target directory"
        return 1
    fi
    if [ "$target_is_dir" ]; then
        target="$(cd "${targetdir}" && pwd)/$(basename "$source")"
    else
        target="$(cd "${targetdir}" && pwd)/$(basename "${2:-$source}")"
    fi
    . $(storage_get_configuration "${name}")
    if curl -s -f -o ${target} ${cw_STORAGE_http_base_url}/${source}; then
        echo "${name}:${source} -> ${target}"
    else
        echo "get from storage failed"
        return 1
    fi
}

http_storage_rm() {
    echo "deletion not supported by 'http' backend"
    return 1
}

http_storage_rmbucket() {
    echo "buckets not supported by 'http' backend"
    return 1
}

http_storage_mkbucket() {
    echo "buckets not supported by 'http' backend"
    return 1
}

http_storage_addbucket() {
    echo "external buckets not supported by 'http' backend"
    return 1
}
