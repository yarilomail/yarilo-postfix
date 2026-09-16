#!/bin/sh
set -eu
. /common.sh

LMTP_HOST="${LMTP_HOST:-yarilo-lmtp}"
LMTP_PORT="${LMTP_PORT:-24}"
RSPAMD_ADDR="${RSPAMD_ADDR:-localhost:11332}"
RBL_RESTRICTIONS="${RBL_RESTRICTIONS:-}"

postconf -e "relayhost ="
postconf -e "virtual_mailbox_domains = mysql:/etc/postfix/mysql-domains.cf"
postconf -e "virtual_alias_maps = mysql:/etc/postfix/mysql-aliases.cf"
postconf -e "virtual_mailbox_maps = mysql:/etc/postfix/mysql-mailbox.cf"
postconf -e "virtual_transport = lmtp:[${LMTP_HOST}]:${LMTP_PORT}"
postconf -e "lmtp_destination_recipient_limit = 1"
postconf -e "lmtp_assume_final = yes"

postconf -e "smtpd_relay_restrictions = permit_mynetworks reject_unauth_destination"
postconf -e "smtpd_helo_required = yes"
postconf -e "smtpd_helo_restrictions = permit_mynetworks, reject_non_fqdn_helo_hostname, reject_invalid_helo_hostname"
postconf -e "smtpd_sender_restrictions = permit_mynetworks, reject_non_fqdn_sender, reject_unknown_sender_domain"

RCPT_RESTRICTIONS="permit_mynetworks, reject_non_fqdn_recipient, reject_unknown_recipient_domain, reject_unauth_destination"
if [ -n "${RBL_RESTRICTIONS}" ]; then
    RCPT_RESTRICTIONS="${RCPT_RESTRICTIONS}, ${RBL_RESTRICTIONS}"
fi
postconf -e "smtpd_recipient_restrictions = ${RCPT_RESTRICTIONS}"

postconf -e "milter_default_action = accept"
postconf -e "milter_protocol = 6"
postconf -e "smtpd_milters = inet:${RSPAMD_ADDR}"
postconf -e "non_smtpd_milters ="

postconf -e "smtpd_client_connection_count_limit = 50"
postconf -e "smtpd_client_connection_rate_limit = 30"
postconf -e "smtpd_client_message_rate_limit = 100"

# Two ways for a fronted client's real address to reach this MX, each on its own
# listener: a PROXY one demands the header from everybody, so 25 cannot serve it.
if [ -n "${MX_XCLIENT_PORT:-}" ]; then
    postconf -M "${MX_XCLIENT_PORT}/inet=${MX_XCLIENT_PORT} inet n - n - - smtpd -o smtpd_authorized_xclient_hosts=${MX_XCLIENT_HOSTS:-\$mynetworks}"
fi
if [ -n "${MX_PROXY_PORT:-}" ]; then
    postconf -M "${MX_PROXY_PORT}/inet=${MX_PROXY_PORT} inet n - n - - smtpd -o smtpd_upstream_proxy_protocol=haproxy"
fi
