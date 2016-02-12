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
dropbox_storage_configure() {
    local name access_key secret_key system data datafile manual token_file
    if [ "$1" == "--system" ]; then
        system="$1"
        shift
    fi
    if [ "$1" == "--manual" ]; then
	manual="$1"
	shift
    fi
    name="$1"

    echo -n "Display name [${name}]: " >/dev/stderr
    read display_name
    display_name="${display_name:-${name}}"

    if [ "$manual" ]; then
	access_key="$2"
	while [ -z "${access_key}" ]; do
            echo -n "Access token: " >/dev/stderr
            read access_key
	done

	while [ -z "${secret_key}" ]; do
            echo -n "Access secret: " >/dev/stderr
            read -s secret_key
            echo >/dev/stderr
	done
    else
	# make temporary file for secretz
	token_file=$(mktemp /tmp/clusterware-dropbox.XXXXXXXX)
	if dropbox_storage_authorize "${token_file}" >/dev/stderr; then
	    # read file containing secretz
	    . "${token_file}"
	    rm -f "${token_file}"
	    # remove file containing secretz
	    access_key="${cw_STORAGE_dropbox_access_token}"
	    secret_key="${cw_STORAGE_dropbox_access_secret}"
	else
	    # clean up temporary file not containing secretz
	    rm -f "${token_file}"
	    echo "failed to authorize"
	    return 1
	fi
    fi
    
    if ! dropbox_storage_verify "${access_key}" "${secret_key}"; then
        echo "failed to verify supplied credentials"
        return 1
    fi
    
    data=$(cat <<EOF
---
name: '${name}'
type: dropbox
access_key: '${access_key}'
secret_key: '${secret_key}'
EOF
    )
    if ! datafile="$(echo "${data}" | storage_write_configuration ${system} "${name}.target.yml")"; then
        echo "failed to write ${name}.target.yml configuration"
        return 1
    fi
    data=$(cat <<EOF
cw_STORAGE_dropbox_access_token="${access_key}"
cw_STORAGE_dropbox_access_secret="${secret_key}"
EOF
    )
    if ! datafile="$(echo "${data}" | storage_write_configuration ${system} "${name}.dropbox.rc")"; then
        echo "failed to write ${name}.dropbox.rc configuration"
        return 1
    fi
}

dropbox_storage_verify() {
    local cw_STORAGE_dropbox_access_token cw_STORAGE_dropbox_access_secret
    cw_STORAGE_dropbox_access_token=$1
    cw_STORAGE_dropbox_access_secret=$2
    export cw_STORAGE_dropbox_access_token cw_STORAGE_dropbox_access_secret
    . "${cw_ROOT}"/etc/ruby.rc
    "${cw_ROOT}"/opt/clusterware-dropbox-cli/bin/clusterware-dropbox \
		verify
}

dropbox_storage_authorize() {
    local filename
    filename=$1
    . "${cw_ROOT}"/etc/ruby.rc
    "${cw_ROOT}"/opt/clusterware-dropbox-cli/bin/clusterware-dropbox \
		authorize --quiet "${filename}"
}

dropbox_storage_perform() {
    local name cmd
    cmd="$1"
    name="$2"
    shift 2
    . "$(storage_get_configuration "${name}")"
    export cw_STORAGE_dropbox_access_token cw_STORAGE_dropbox_access_secret
    . "${cw_ROOT}"/etc/ruby.rc
    "${cw_ROOT}"/opt/clusterware-dropbox-cli/bin/clusterware-dropbox \
		"${cmd}" "$@"
}

dropbox_storage_list() {
    dropbox_storage_perform "ls" "$@"
}

dropbox_storage_get() {
    dropbox_storage_perform "get" "$@"
}

dropbox_storage_put() {
    dropbox_storage_perform "put" "$@"
}

dropbox_storage_mkbucket() {
    dropbox_storage_perform "mkdir" "$@"
}

dropbox_storage_rmbucket() {
    dropbox_storage_perform "rmdir" "$@"
}

dropbox_storage_rm() {
    dropbox_storage_perform "rm" "$@"
}

dropbox_storage_addbucket() {
    echo "external buckets not supported by 'dropbox' backend"
    return 1
}
