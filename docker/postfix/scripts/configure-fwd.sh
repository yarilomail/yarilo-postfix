#!/bin/sh
set -eu
. /common.sh

RSPAMD_ADDR="${RSPAMD_ADDR:-localhost:11332}"
DKIM_MILTER_ADDR="${DKIM_MILTER_ADDR:-}"
POSTSRSD_HOST="${POSTSRSD_HOST:-yarilo-postsrsd}"
LMTP_ADDR="${LMTP_ADDR:-}"
SASL_USER="${SASL_USER:-}"
SASL_PASSWORD="${SASL_PASSWORD:-}"

postconf -e "relayhost ="

if [ -n "${LMTP_ADDR}" ]; then
    postconf -e "virtual_mailbox_domains = mysql:/etc/postfix/mysql-domains.cf"
    postconf -e "virtual_mailbox_maps ="
    postconf -e "virtual_transport = lmtp:inet:${LMTP_ADDR}"
    postconf -e "lmtp_host_lookup = native"
fi

postconf -e "sender_canonical_maps = socketmap:inet:${POSTSRSD_HOST}:10003:forward"
postconf -e "sender_canonical_classes = envelope_sender"
postconf -e "recipient_canonical_maps = socketmap:inet:${POSTSRSD_HOST}:10003:reverse"
postconf -e "recipient_canonical_classes = envelope_recipient,header_recipient"

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
        cat > /etc/postfix/sasl/smtpd.conf << 'SASLCF'
pwcheck_method: auxprop
auxprop_plugin: sasldb
sasldb_path: /etc/sasldb2
mech_list: PLAIN LOGIN
SASLCF
        cp /etc/postfix/sasl/smtpd.conf /etc/sasl2/smtpd.conf
        printf '%s' "${SASL_PASSWORD}" | saslpasswd2 -c -f /etc/sasldb2 -u "${MAIL_DOMAIN}" -p "${SASL_USER}"
        [ -f /etc/sasldb2 ] || { echo "FATAL: saslpasswd2 did not create /etc/sasldb2" >&2; exit 1; }
        chown postfix:postfix /etc/sasldb2
        chmod 640 /etc/sasldb2
        postconf -e "smtpd_sasl_type = cyrus"
        postconf -e "smtpd_sasl_path = smtpd"
        postconf -e "smtpd_sasl_auth_enable = yes"
        postconf -e "smtpd_sasl_security_options = noanonymous"
        postconf -e "cyrus_sasl_config_path = /etc/sasl2"
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
