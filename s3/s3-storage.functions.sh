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
s3_storage_configure() {
    local name access_key secret_key system
    if [ "$1" == "--system" ]; then
        system="$1"
        shift
    fi
    name="$1"
    access_key="$2"

    echo -n "Display name [${name}]: " >/dev/stderr
    read display_name
    display_name="${display_name:-${name}}"

    while [ -z "${access_key}" ]; do
        echo -n "Access key: " >/dev/stderr
        read access_key
    done

    while [ -z "${secret_key}" ]; do
        echo -n "Secret key: " >/dev/stderr
        read -s secret_key
        echo >/dev/stderr
    done

    echo -n "Service address [s3.amazonaws.com]: " >/dev/stderr
    read address
    address="${address:-s3.amazonaws.com}"

    data=$(cat <<EOF
---
name: ${name}
type: s3
access_key: ${access_key}
secret_key: ${secret_key}
address: ${address}
EOF
    )
    if ! echo "${data}" | storage_write_configuration ${system} "${name}.target.yml"; then
        echo "failed to write ${name}.target.yml configuration"
        return 1
    fi
    data=$(cat <<EOF
[default]
access_key = ${access_key}
secret_key = ${secret_key}
host_base = ${address}
host_bucket = %(bucket)s.${address}
use_https = True
check_ssl_certificate = True
EOF
    )
    if ! echo "${data}" | storage_write_configuration ${system} "${name}.s3.cfg"; then
        echo "failed to write ${name}.s3.cfg configuration"
        return 1
    fi
}

s3_storage_perform() {
    local name cmd
    cmd="$1"
    name="$2"
    shift 2
    "${cw_ROOT}"/opt/s3cmd/s3cmd -c "$(storage_get_configuration "${name}")" "${cmd}" "$@" 2>&1 | \
        grep -v 'python-magic'
}

s3_storage_list() {
    local args
    if [[ ! -z "$2" && "$2" != "s3://"* ]]; then
        args=("$1" "s3://${2}")
    else
        args=("$1" "$2")
    fi
    s3_storage_perform "ls" "${args[@]}"
}

s3_storage_get() {
    local args
    if [ -z "$3" ]; then
        echo "you must supply a destination"
        return 1
    fi
    if [[ "$2" != "s3://"* ]]; then
        args=("$1" "s3://${2}" "$3")
    else
        args=("$1" "$2" "$3")
    fi
    s3_storage_perform "get" "${args[@]}"
}

s3_storage_put() {
    local args
    if [[ "$3" != "s3://"* ]]; then
        args=("$1" "$2" "s3://${3}")
    else
        args=("$1" "$2" "$3")
    fi
    s3_storage_perform "put" "${args[@]}"
}

s3_storage_mkbucket() {
    local args
    if [[ "$2" != "s3://"* ]]; then
        args=("$1" "s3://${2}")
    else
        args=("$1" "$2")
    fi
    s3_storage_perform "mb" "${args[@]}"
}

s3_storage_rmbucket() {
    local args
    if [[ "$2" != "s3://"* ]]; then
        args=("$1" "s3://${2}")
    else
        args=("$1" "$2")
    fi
    s3_storage_perform "rb" "${args[@]}"
}

s3_storage_rm() {
    local args
    if [[ "$2" != "s3://"* ]]; then
        args=("$1" "s3://${2}")
    else
        args=("$1" "$2")
    fi
    s3_storage_perform "del" "${args[@]}"
}
