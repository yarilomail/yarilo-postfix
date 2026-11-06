#!/bin/sh
set -eu

if [ -f "/etc/postfix/tls/tls.crt" ]; then
    mkdir -p /run/postfix/tls
    cp /etc/postfix/tls/tls.crt /run/postfix/tls/tls.crt
    cp /etc/postfix/tls/tls.key /run/postfix/tls/tls.key
    chmod 644 /run/postfix/tls/tls.crt
    chmod 600 /run/postfix/tls/tls.key
    # The issuer's CA, for verifying the next relay (relay-fwd to relay-fwd-out).
    if [ -f "/etc/postfix/tls/ca.crt" ]; then
        cp /etc/postfix/tls/ca.crt /run/postfix/tls/ca.crt
        chmod 644 /run/postfix/tls/ca.crt
    fi
fi

case "${RELAY_TYPE:-}" in
    mx)  /configure-mx.sh ;;
    mta) /configure-mta.sh ;;
    fwd) /configure-fwd.sh ;;
    fwd-out) /configure-fwd-out.sh ;;
    *)
        echo "RELAY_TYPE must be mx, mta, fwd or fwd-out" >&2
        exit 1
        ;;
esac

exec postfix start-fg
