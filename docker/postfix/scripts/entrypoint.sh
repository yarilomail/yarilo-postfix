#!/bin/sh
set -eu

if [ -f "/etc/postfix/tls/tls.crt" ]; then
    mkdir -p /run/postfix/tls
    cp /etc/postfix/tls/tls.crt /run/postfix/tls/tls.crt
    cp /etc/postfix/tls/tls.key /run/postfix/tls/tls.key
    chmod 644 /run/postfix/tls/tls.crt
    chmod 600 /run/postfix/tls/tls.key
fi

case "${RELAY_TYPE:-}" in
    mx)  /configure-mx.sh ;;
    mta) /configure-mta.sh ;;
    fwd) /configure-fwd.sh ;;
    *)
        echo "RELAY_TYPE must be mx, mta, or fwd" >&2
        exit 1
        ;;
esac

exec postfix start-fg
