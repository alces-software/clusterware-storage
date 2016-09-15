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
swift_storage_configure() {
    local name username api_key endpoint system data datafile
    if [ "$1" == "--system" ]; then
        system="$1"
        shift
    fi
    name="$1"
    access_key="$2"

    echo -n "Display name [${name}]: " >/dev/stderr
    read display_name
    display_name="${display_name:-${name}}"

    while [ -z "${username}" ]; do
        echo -n "Username: " >/dev/stderr
        read username
    done

    while [ -z "${api_key}" ]; do
        echo -n "API key: " >/dev/stderr
        read -s api_key
        echo >/dev/stderr
    done

    while [ -z "${endpoint}" ]; do
        echo -n "Authentication endpoint: " >/dev/stderr
        read endpoint
    done

    data=$(cat <<EOF
---
name: '${name}'
type: swift
username: '${username}'
api_key: '${api_key}'
endpoint: '${endpoint}'
EOF
    )
    if ! datafile="$(echo "${data}" | storage_write_configuration ${system} "${name}.target.yml")"; then
        echo "failed to write ${name}.target.yml configuration"
        return 1
    fi
    data=$(cat <<EOF
cw_STORAGE_swift_username="${username}"
cw_STORAGE_swift_api_key="${api_key}"
cw_STORAGE_swift_endpoint="${endpoint}"
EOF
    )
    if ! datafile="$(echo "${data}" | storage_write_configuration ${system} "${name}.swift.rc")"; then
        echo "failed to write ${name}.swift.rc configuration"
        return 1
    fi
}

swift_storage_perform() {
    local name cmd
    cmd="$1"
    name="$2"
    shift 2
    . "$(storage_get_configuration "${name}")"
    swift -A ${cw_STORAGE_swift_endpoint} \
          -U ${cw_STORAGE_swift_username} \
          -K ${cw_STORAGE_swift_api_key} "${cmd}" "$@" 2>&1
}

swift_storage_list() {
    swift_storage_perform "list" "$@" -l | head -n-1 | \
        (while read l; do
             if [ "$2" ]; then
                 size="$(echo "$l" | cut -f1 -d' ')"
                 fname="$(echo "$l" | cut -f5- -d' ')"
             else
                 l="$(echo "$l" | awk '{for(i=2;i<=NF;i++)printf $i" ";print""}')"
                 size="DIR"
                 fname="$(echo "$l" | cut -f4- -d' ')"
             fi
             date="$(echo "$l" | cut -f2-3 -d' ')"
             printf "%s %9s   %s\n" "${date%:*}" "${size}" "${fname}"
         done)
}

swift_storage_get() {
    local args recursive container file target
    args=("$1")
    shift
    while [[ "$1" == "-"* ]]; do
        if [ "$1" == "-R" -o "$1" == "-r" ]; then
            recursive=true
        else
            args+=($1)
        fi
        shift
    done
    if [[ $1 != *"/"* ]]; then
        container=$1
    else
        container="${1%%/*}"
        file="${1#*/}"
    fi
    target="$2"
    if [ "$recursive" -a -z "$file" ]; then
        args+=(-D "${target:-$container}" "$container")
    elif [ -z "$file" ]; then
        echo "refusing to download bucket without recursive option"
        return 1
    else
        args+=(-o "${target:-$(basename "$file")}" "$container" "$file")
    fi
    swift_storage_perform "download" "${args[@]}"
}

swift_storage_put() {
    local args recursive container file source
    args=("$1")
    shift
    while [[ "$1" == -* ]]; do
        if [ "$1" == "-R" -o "$1" == "-r" ]; then
            recursive=true
        else
            args+=($1)
        fi
        shift
    done
    if [[ $2 != *"/"* ]]; then
        container=$2
    else
        container="${2%%/*}"
        file="${2#*/}"
    fi
    source="$1"
    if [ -z "$container" ]; then
        echo "you must supply a destination"
        return 1
    fi
    if [ -d "$source" ]; then
        if [ "$recursive" ]; then
            args+=(--object-name "$file" "$container" "$source")
        else
            echo "refusing to upload directory without recursive option"
            return 1
        fi
    else
        args+=("$container" "$source" --object-name "${file:-$(basename $source)}")
    fi
    swift_storage_perform "upload" "${args[@]}"
}

swift_storage_mkbucket() {
    local args
    args=("$1" "$2")
    swift_storage_perform "post" "${args[@]}"
}

swift_storage_rmbucket() {
    echo "use a recursive 'rm' command to remove a bucket from the 'swift' backend"
    return 1
}

swift_storage_rm() {
    local args recursive force confirm container file
    args=("$1")
    shift
    while [[ "$1" == -* ]]; do
        if [ "$1" == "-R" -o "$1" == "-r" -o "$1" == "--recursive" ]; then
            recursive=true
        elif [ "$1" == "-Rf" -o "$1" == "-rf" -o "$1" == "-fr" -o "$1" == "-fR" ]; then
            force=true
            recursive=true
        elif [ "$1" == "-f" -o "--force" ]; then
            force=true
        fi
        shift
    done
    if [[ $1 != *"/"* ]]; then
        container=$1
    else
        container="${1%%/*}"
        file="${1#*/}"
    fi
    if [ "$file" ]; then
        if [ "$recursive" ]; then
            echo "unable to use a recursive 'rm' unless removing an entire bucket"
            return 1
        else
            args+=("$container" "$file")
        fi
    elif [ -z "$recursive" ]; then
        echo "refusing to delete bucket without recursive option"
        return 1
    else
        args+=("$container")
    fi
    if [ "$recursive" ]; then
        if [ -z "$force" ]; then
            echo -n "$cw_BINNAME: recursively delete '${container}'? " >/dev/stderr
            read -N1 confirm
            echo "" > /dev/stderr
            if [ "$confirm" != "y" -a "$confirm" != 'Y' ]; then
                echo "delete from storage aborted"
                return 2
            fi
        fi
    fi
    swift_storage_perform "delete" "${args[@]}"
}

swift_storage_addbucket() {
    echo "external buckets not supported by 'swift' backend"
    return 1
}
