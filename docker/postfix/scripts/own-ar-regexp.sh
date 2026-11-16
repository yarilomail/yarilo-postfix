#!/bin/sh
# Prints the header_checks line that drops an Authentication-Results naming
# this ADMD (authserv-id $1, the MX's myhostname). Only the MX may state
# results for it; arc-milter copies the MX's into the ARC set.
set -eu
_id=$(printf '%s' "${1:?authserv-id}" | sed 's/[][\\.^$*+?(){}|/]/\\&/g')
printf '/^Authentication-Results:[[:space:]]*%s([[:space:];]|$)/ IGNORE\n' "${_id}"
