#!/bin/sh
# relay-fwd-out: yarilo's mail for other domains, from relay-fwd only. Signs it
# (dkim-milter-fwd) and rewrites the envelope sender with SRS, then delivers.
set -eu
. /common.sh

DKIM_MILTER_ADDR="${DKIM_MILTER_ADDR:-}"
POSTSRSD_HOST="${POSTSRSD_HOST:-}"
SASL_USER="${SASL_USER:?SASL_USER: the account relay-fwd logs in with}"
SASL_PASSWORD="${SASL_PASSWORD:?SASL_PASSWORD is required}"
RATE_LIMIT="${RATE_LIMIT:-0}"

[ -f /run/postfix/tls/tls.crt ] || { echo "FATAL: relay-fwd-out needs its TLS secret" >&2; exit 1; }

postconf -e "relayhost ="

# A local sender keeps its address: the first map that answers wins, so the
# domain table stops the lookup before postsrsd for every active local domain.
if [ -n "${POSTSRSD_HOST}" ]; then
    _gen_mysql_cf /etc/postfix/mysql-local-sender.cf \
        "SELECT '%s' FROM domain WHERE domain='%d' AND active=1"
    postconf -e "sender_canonical_maps = mysql:/etc/postfix/mysql-local-sender.cf, socketmap:inet:${POSTSRSD_HOST}:10003:forward"
    postconf -e "sender_canonical_classes = envelope_sender"
fi

_milters=""
if [ -n "${DKIM_MILTER_ADDR}" ]; then
    _milters="{ inet:${DKIM_MILTER_ADDR}, default_action=tempfail }"
fi
postconf -e "milter_protocol = 6"
postconf -e "smtpd_milters = ${_milters}"
postconf -e "non_smtpd_milters ="

_sasldb_user "${SASL_USER}" "${SASL_PASSWORD}"

# relay-fwd is the only client, so the per-client limit bounds all forwarded
# mail; it sits in mynetworks, which anvil exempts by default.
if [ "${RATE_LIMIT}" -gt 0 ]; then
    postconf -e "smtpd_client_message_rate_limit = ${RATE_LIMIT}"
    postconf -e "smtpd_client_event_limit_exceptions ="
    postconf -e "anvil_rate_time_unit = 60s"
fi

# 587 only: no listener without a login.
postconf -MX smtp/inet
cat >> /etc/postfix/master.cf << EOF
submission inet n       -       n       -       -       smtpd
  -o syslog_name=postfix/submission
  -o smtpd_tls_security_level=encrypt
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_relay_restrictions=permit_sasl_authenticated,reject
  -o milter_macro_daemon_name=ORIGINATING
EOF
