#!/bin/sh
MAIL_DOMAIN="${MAIL_DOMAIN:-example.com}"
MAIL_HOSTNAME="${MAIL_HOSTNAME:-mail.example.com}"
MAIL_MYNETWORKS="${MAIL_MYNETWORKS:-127.0.0.0/8 10.0.0.0/8}"
MAIL_DOMAINS="${MAIL_DOMAINS:-${MAIL_DOMAIN}}"

postconf -e "myhostname = ${MAIL_HOSTNAME}"
postconf -e "smtp_helo_name = ${MAIL_HOSTNAME}"
postconf -e "mydomain = ${MAIL_DOMAIN}"
postconf -e "myorigin = ${MAIL_DOMAIN}"
postconf -e "inet_interfaces = all"
postconf -e "inet_protocols = ipv4"
postconf -e "mydestination = localhost"
postconf -e "biff = no"
postconf -e "append_dot_mydomain = no"
postconf -e "alias_maps ="
postconf -e "alias_database ="
postconf -e "maillog_file = /dev/stdout"
postconf -e "mynetworks = ${MAIL_MYNETWORKS}"
postconf -e "smtpd_banner = \$myhostname ESMTP"

MYSQL_HOST="${MYSQL_HOST:-localhost}"
MYSQL_USER="${MYSQL_USER:-postfix}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-}"
MYSQL_DBNAME="${MYSQL_DBNAME:-yarilo}"

_gen_mysql_cf() {
    local _file="$1" _query="$2"
    printf 'hosts = %s\nuser = %s\npassword = %s\ndbname = %s\nquery = %s\ntls_verify_cert = no\n' \
        "${MYSQL_HOST}" "${MYSQL_USER}" "${MYSQL_PASSWORD}" "${MYSQL_DBNAME}" "${_query}" \
        > "${_file}"
    chmod 640 "${_file}"
}

_gen_mysql_cf /etc/postfix/mysql-domains.cf \
    "SELECT domain FROM domain WHERE domain='%s' AND active=1"
_gen_mysql_cf /etc/postfix/mysql-aliases.cf \
    "SELECT goto FROM alias WHERE address='%s' AND active=1 UNION ALL SELECT goto FROM alias WHERE address='@%d' AND active=1 AND NOT EXISTS (SELECT 1 FROM alias WHERE address='%s' AND active=1)"
_gen_mysql_cf /etc/postfix/mysql-mailbox.cf \
    "SELECT username FROM mailbox WHERE username='%s' AND active=1"

postconf -e "smtp_tls_security_level = may"
postconf -e "smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt"
postconf -e "smtp_tls_loglevel = 1"

if [ -f "/run/postfix/tls/tls.crt" ]; then
    postconf -e "smtpd_tls_cert_file = /run/postfix/tls/tls.crt"
    postconf -e "smtpd_tls_key_file = /run/postfix/tls/tls.key"
    postconf -e "smtpd_tls_security_level = may"
    postconf -e "smtpd_tls_loglevel = 1"
fi

# _sasldb_user <user> <password>: one SASL account in sasldb for smtpd.
_sasldb_user() {
    cat > /etc/postfix/sasl/smtpd.conf << 'SASLCF'
pwcheck_method: auxprop
auxprop_plugin: sasldb
sasldb_path: /etc/sasldb2
mech_list: PLAIN LOGIN
SASLCF
    cp /etc/postfix/sasl/smtpd.conf /etc/sasl2/smtpd.conf
    printf '%s' "$2" | saslpasswd2 -c -f /etc/sasldb2 -u "${MAIL_DOMAIN}" -p "$1"
    [ -f /etc/sasldb2 ] || { echo "FATAL: saslpasswd2 did not create /etc/sasldb2" >&2; exit 1; }
    chown postfix:postfix /etc/sasldb2
    chmod 640 /etc/sasldb2
    postconf -e "smtpd_sasl_type = cyrus"
    postconf -e "smtpd_sasl_path = smtpd"
    postconf -e "smtpd_sasl_security_options = noanonymous"
    postconf -e "cyrus_sasl_config_path = /etc/sasl2"
}
