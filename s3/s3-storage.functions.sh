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
    local name access_key secret_key system data datafile
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
name: '${name}'
type: s3
access_key: '${access_key}'
secret_key: '${secret_key}'
address: '${address}'
buckets: []
EOF
    )
    if ! datafile="$(echo "${data}" | storage_write_configuration ${system} "${name}.target.yml")"; then
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
    if [ "${address}" == "storage.googleapis.com" ]; then
        data="${data}"$'\n'"signature_v2 = True"
    fi
    if ! datafile="$(echo "${data}" | storage_write_configuration ${system} "${name}.s3.cfg")"; then
        echo "failed to write ${name}.s3.cfg configuration"
        return 1
    fi
    data=$(cat <<EOF
cw_STORAGE_s3_config="${datafile}"
cw_STORAGE_s3_buckets=()
EOF
    )
    if ! datafile="$(echo "${data}" | storage_write_configuration ${system} "${name}.s3.rc")"; then
        echo "failed to write ${name}.s3.rc configuration"
        return 1
    fi
}

s3_storage_perform() {
    local name cmd
    cmd="$1"
    name="$2"
    shift 2
    . "$(storage_get_configuration "${name}")"
    "${cw_ROOT}"/opt/s3cmd/s3cmd -c "${cw_STORAGE_s3_config}" "${cmd}" "$@" 2>&1 | \
        grep -v 'python-magic'
}

s3_storage_list() {
    local args a
    if [[ ! -z "$2" && "$2" != "s3://"* ]]; then
        args=("$1" "s3://${2}")
    else
        args=("$1" "$2")
    fi
    s3_storage_perform "ls" "${args[@]}"
    if [ -z "$2" ]; then
        for a in "${cw_STORAGE_s3_buckets[@]}"; do
            echo "        EXTERNAL  $a"
        done
    fi
}

s3_storage_get() {
    local args name
    args=("$1")
    shift
    while [[ "$1" == "-"* ]]; do
	if [ "$1" == "-R" -o "$1" == "-r" ]; then
	    args+=(--recursive)
	else
            args+=($1)
	fi
	shift
    done
    if [ -z "$2" ]; then
        echo "you must supply a destination"
        return 1
    fi
    if [[ "$1" != "s3://"* ]]; then
        args+=("s3://${1}" "$2")
    else
        args+=("$1" "$2")
    fi
    s3_storage_perform "get" "${args[@]}"
}

s3_storage_put() {
    local args name
    args=("$1")
    shift
    while [[ "$1" == -* ]]; do
	if [ "$1" == "-R" -o "$1" == "-r" ]; then
	    args+=(--recursive)
	fi
	shift
    done
    if [[ "$2" != "s3://"* ]]; then
        args+=("$1" "s3://${2}")
    else
        args+=("$1" "$2")
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
    local args bucket rcfile
    if [[ "$2" != "s3://"* ]]; then
        args=("$1" "s3://${2}")
    else
        args=("$1" "$2")
    fi
    rcfile="$(storage_get_configuration "${args[0]}")"
    targetfile="$(dirname "${rcfile}")/${name}.target.yml"
    bucket="${args[1]}"
    if grep -q "^cw_STORAGE_s3_buckets=.*\"${bucket}\"" "${rcfile}"; then
        sed -i "${rcfile}" -e "s,^\(cw_STORAGE_s3_buckets=(.*\) \"${bucket}\"\([^)]*\),\1\2,g"
        sed -i "${targetfile}" -e "s,^\(buckets: \[.*\)\"${bucket}\"\([^]]*\),\1\2,g" -e "s/\[, /[/g"
        echo "removed external bucket: ${bucket}"
    else
        s3_storage_perform "rb" "${args[@]}"
    fi
}

s3_storage_rm() {
    local args recursive force confirm
    args=("$1")
    shift
    while [[ "$1" == -* ]]; do
	if [ "$1" == "-R" -o "$1" == "-r" ]; then
	    args+=(--recursive)
	    recursive=true
	fi
	if [ "$1" == "-f" ]; then
	    force=true
	fi
	if [ "$1" == "-Rf" -o "$1" == "-rf" -o "$1" == "-fr" -o "$1" == "-fR" ]; then
	    force=true
	    recursive=true
	    args+=(--recursive)
	fi
	shift
    done
    if [[ "$1" != "s3://"* ]]; then
        args+=("s3://${1}")
    else
        args+=("$1")
    fi
    if [ "$recursive" ]; then
	if [ -z "$force" ]; then
	    echo -n "$cw_BINNAME: recursively delete '$1'? " >/dev/stderr
	    read -N1 confirm
	    echo "" > /dev/stderr
	    if [ "$confirm" != "y" -a "$confirm" != 'Y' ]; then
		echo "delete from storage aborted"
		return 2
	    fi
	fi
    fi
    s3_storage_perform "del" "${args[@]}"
}

s3_storage_addbucket() {
    local name bucket rcfile targetfile
    name="$1"
    bucket="$2"
    if [ -z "${bucket}" ]; then
        echo "you must supply a bucket name"
        return 1
    elif [[ "$bucket" != "s3://"* ]]; then
        bucket="s3://${bucket}"
    fi
    rcfile="$(storage_get_configuration "${name}")"
    targetfile="$(dirname "${rcfile}")/${name}.target.yml"
    if grep -q "^cw_STORAGE_s3_buckets=.*\"${bucket}\"" "${rcfile}"; then
        echo "external bucket already exists: ${bucket}"
        return 1
    else
        sed -i "${rcfile}" -e "s,^\(cw_STORAGE_s3_buckets=([^)]*\),\1 \"${bucket}\",g"
        sed -i "${targetfile}" -e "s|^\(buckets: \[[^]]*\)|\1, \"${bucket}\"|g" -e "s/\[, /[/g"
        echo "added external bucket: ${bucket}"
    fi
}
