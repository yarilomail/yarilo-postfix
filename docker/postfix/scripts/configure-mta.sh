#!/bin/sh
set -eu
. /common.sh

LMTP_HOST="${LMTP_HOST:-yarilo-lmtp}"
LMTP_PORT="${LMTP_PORT:-24}"
RSPAMD_ADDR="${RSPAMD_ADDR:-localhost:11332}"
OPENDKIM_ADDR="${OPENDKIM_ADDR:-}"
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
postconf -e "smtpd_sender_restrictions = permit_mynetworks, reject_authenticated_sender_login_mismatch"
postconf -e "smtpd_sender_login_maps = regexp:/etc/postfix/sender_login_maps"

cat > /etc/postfix/sender_login_maps << 'EOF'
/^(.+)@(.+)$/ ${1}@${2}
/^(.+)$/       ${1}
EOF

_milters="inet:${RSPAMD_ADDR}"
if [ -n "${OPENDKIM_ADDR}" ]; then
    _milters="${_milters},inet:${OPENDKIM_ADDR}"
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
