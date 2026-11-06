#!/bin/sh
set -eu
. /common.sh

RSPAMD_ADDR="${RSPAMD_ADDR:-localhost:11332}"
DKIM_MILTER_ADDR="${DKIM_MILTER_ADDR:-}"
POSTSRSD_HOST="${POSTSRSD_HOST:-}"
LMTP_ADDR="${LMTP_ADDR:-}"
SASL_USER="${SASL_USER:-}"
SASL_PASSWORD="${SASL_PASSWORD:-}"
FWD_OUT_ADDR="${FWD_OUT_ADDR:-}"
FWD_OUT_SASL_USER="${FWD_OUT_SASL_USER:-}"
FWD_OUT_SASL_PASSWORD="${FWD_OUT_SASL_PASSWORD:-}"

postconf -e "relayhost ="

if [ -n "${LMTP_ADDR}" ]; then
    postconf -e "virtual_mailbox_domains = mysql:/etc/postfix/mysql-domains.cf"
    postconf -e "virtual_mailbox_maps ="
    postconf -e "virtual_transport = lmtp:inet:${LMTP_ADDR}"
    postconf -e "lmtp_host_lookup = native"
fi

# With relay-fwd-out, local domains go to yarilo by LMTP as they are and the
# rest to relay-fwd-out, which signs and rewrites; this relay does neither.
if [ -n "${FWD_OUT_ADDR}" ]; then
    [ -n "${FWD_OUT_SASL_USER}" ] && [ -n "${FWD_OUT_SASL_PASSWORD}" ] \
        || { echo "FATAL: FWD_OUT_ADDR needs FWD_OUT_SASL_USER and FWD_OUT_SASL_PASSWORD" >&2; exit 1; }
    [ -f /run/postfix/tls/ca.crt ] \
        || { echo "FATAL: FWD_OUT_ADDR needs the issuer's ca.crt in the TLS secret" >&2; exit 1; }
    [ -z "${DKIM_MILTER_ADDR}" ] && [ -z "${POSTSRSD_HOST}" ] \
        || { echo "FATAL: with FWD_OUT_ADDR relay-fwd neither signs nor rewrites" >&2; exit 1; }
    _out_host="${FWD_OUT_ADDR%:*}"
    postconf -e "relayhost = [${_out_host}]:${FWD_OUT_ADDR##*:}"
    printf '[%s]:%s %s:%s\n' "${_out_host}" "${FWD_OUT_ADDR##*:}" "${FWD_OUT_SASL_USER}@${MAIL_DOMAIN}" "${FWD_OUT_SASL_PASSWORD}" \
        > /etc/postfix/sasl_passwd
    chmod 600 /etc/postfix/sasl_passwd
    postconf -e "smtp_sasl_auth_enable = yes"
    postconf -e "smtp_sasl_password_maps = texthash:/etc/postfix/sasl_passwd"
    postconf -e "smtp_sasl_security_options = noanonymous"
    postconf -e "smtp_sasl_tls_security_options = noanonymous"
    postconf -e "smtp_tls_security_level = secure"
    postconf -e "smtp_tls_CAfile = /run/postfix/tls/ca.crt"
    postconf -e "smtp_tls_secure_cert_match = nexthop"
fi

if [ -n "${POSTSRSD_HOST}" ]; then
    postconf -e "sender_canonical_maps = socketmap:inet:${POSTSRSD_HOST}:10003:forward"
    postconf -e "sender_canonical_classes = envelope_sender"
    postconf -e "recipient_canonical_maps = socketmap:inet:${POSTSRSD_HOST}:10003:reverse"
    postconf -e "recipient_canonical_classes = envelope_recipient,header_recipient"
fi

postconf -e "smtpd_relay_restrictions = permit_mynetworks reject_unauth_destination"
postconf -e "smtpd_recipient_restrictions = permit_mynetworks, reject_unauth_destination"

_milters="inet:${RSPAMD_ADDR}"
# The signer alone defaults to tempfail: with it down mail waits in the queue
# instead of leaving unsigned; rspamd keeps milter_default_action (accept).
if [ -n "${DKIM_MILTER_ADDR}" ]; then
    _milters="${_milters}, { inet:${DKIM_MILTER_ADDR}, default_action=tempfail }"
fi
postconf -e "milter_default_action = accept"
postconf -e "milter_protocol = 6"
postconf -e "smtpd_milters = ${_milters}"
postconf -e "non_smtpd_milters = \$smtpd_milters"

if [ -f "/run/postfix/tls/tls.crt" ]; then
    _sasl_opts="  -o smtpd_relay_restrictions=permit_mynetworks,reject"

    if [ -n "${SASL_USER}" ] && [ -n "${SASL_PASSWORD}" ]; then
        _sasldb_user "${SASL_USER}" "${SASL_PASSWORD}"
        postconf -e "smtpd_sasl_auth_enable = yes"
        _sasl_opts="  -o smtpd_sasl_auth_enable=yes
  -o smtpd_relay_restrictions=permit_mynetworks,permit_sasl_authenticated,reject"
    fi

    cat >> /etc/postfix/master.cf << EOF
submission inet n       -       n       -       -       smtpd
  -o syslog_name=postfix/submission
  -o smtpd_tls_security_level=encrypt
${_sasl_opts}
  -o milter_macro_daemon_name=ORIGINATING
EOF
fi
