#!/bin/sh
set -eu
. /common.sh

LMTP_HOST="${LMTP_HOST:-yarilo-lmtp}"
LMTP_PORT="${LMTP_PORT:-24}"
RSPAMD_ADDR="${RSPAMD_ADDR:-localhost:11332}"
DKIM_MILTER_ADDR="${DKIM_MILTER_ADDR:-}"
MAILFROM_MILTER_ADDR="${MAILFROM_MILTER_ADDR:-}"
SASL_LOGIN_ADDR="${SASL_LOGIN_ADDR:-yarilo-sasl-login:12345}"

postconf -e "relayhost ="
postconf -e "virtual_mailbox_domains = mysql:/etc/postfix/mysql-domains.cf"
postconf -e "virtual_alias_maps = mysql:/etc/postfix/mysql-aliases.cf"
postconf -e "virtual_transport = lmtp:[${LMTP_HOST}]:${LMTP_PORT}"
postconf -e "lmtp_destination_recipient_limit = 1"
postconf -e "lmtp_assume_final = yes"

postconf -e "smtpd_sasl_type = dovecot"
postconf -e "smtpd_sasl_path = inet:${SASL_LOGIN_ADDR}"
postconf -e "smtpd_sasl_auth_enable = yes"
postconf -e "smtpd_sasl_security_options = noanonymous"
postconf -e "smtpd_sasl_local_domain = ${MAIL_DOMAIN}"

postconf -e "smtpd_relay_restrictions = permit_mynetworks permit_sasl_authenticated reject"
# No permit_mynetworks: a login sends as its own address from the pod network too.
postconf -e "smtpd_sender_restrictions = reject_authenticated_sender_login_mismatch"
# A login owns its address and the alias rows naming it in goto, in its domain
# by mailfrom-milter; %u keeps the @domain lookup from reaching a catch-all.
_gen_mysql_cf /etc/postfix/mysql-sender-login.cf \
    "SELECT username FROM mailbox WHERE username='%u@%d' AND active=1 UNION ALL SELECT goto FROM alias WHERE address='%u@%d' AND active=1"
postconf -e "smtpd_sender_login_maps = mysql:/etc/postfix/mysql-sender-login.cf"

_milters="inet:${RSPAMD_ADDR}"
# mailfrom-milter and the signer default to tempfail: with either down mail waits
# in the queue instead of leaving unchecked or unsigned; rspamd keeps accept.
# mailfrom-milter comes first, so a forged From: is refused before signing.
if [ -n "${MAILFROM_MILTER_ADDR}" ]; then
    _milters="${_milters}, { inet:${MAILFROM_MILTER_ADDR}, default_action=tempfail }"
fi
if [ -n "${DKIM_MILTER_ADDR}" ]; then
    _milters="${_milters}, { inet:${DKIM_MILTER_ADDR}, default_action=tempfail }"
fi
postconf -e "milter_default_action = accept"
postconf -e "milter_protocol = 6"
postconf -e "smtpd_milters = ${_milters}"
postconf -e "non_smtpd_milters = ${_milters}"

if [ -f "/run/postfix/tls/tls.crt" ]; then
    cat >> /etc/postfix/master.cf << EOF
submission inet n       -       n       -       -       smtpd
  -o syslog_name=postfix/submission
  -o smtpd_tls_security_level=encrypt
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_relay_restrictions=permit_sasl_authenticated,reject
  -o milter_macro_daemon_name=ORIGINATING
EOF
fi
