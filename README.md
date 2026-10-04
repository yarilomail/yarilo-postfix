# yarilo-postfix

Postfix relay stack for the yarilo mail platform. Ships three independent deployment types from a single Docker image, each controlled by `RELAY_TYPE`.

## Architecture

rspamd integrates with Postfix via the **milter protocol** (TCP `:11332`). Postfix calls rspamd during SMTP session processing — rspamd is not a proxy in the delivery chain. Each type has its own rspamd instance with a type-specific config.

```
MX
  Internet ──► Postfix :25
                  │  milter
                  ├──────────► rspamd-mx :11332
                  │            (spam scan, RBL checks)
                  │            returns: accept / reject / add_header
                  │
                  └── accept ──► yarilo-lmtp :24

MTA
  User ──► Postfix :587
            │  SASL auth
            ├──────────────────► yarilo-sasl-login :12345
            │  milter
            ├──────────► rspamd-mta :11332
            │            (outbound scan, DKIM sign)
            │
            ├── local domain ──► yarilo-lmtp :24
            └── external     ──► relayhost / direct

FWD
  yarilo Sieve ──► Postfix :25
  (redirect)         │  SRS rewrite
                     ├──────────────► postsrsd :10001/:10002
                     │  milter
                     ├──────────► rspamd-fwd :11332
                     │            (DKIM sign)
                     │
                     └──────────────► external MX
```

## Components

| Deployment | Port | Function |
|:---|:---|:---|
| `relay-mx` | 25 | Inbound MX — spam/RBL scan, LMTP delivery to yarilo |
| `relay-mta` | 25/587 | Submission — SASL auth via yarilo-sasl-login, DKIM sign |
| `relay-fwd` | 25 | Sieve forward — SRS rewrite via postsrsd, DKIM sign |
| `relay-rspamd-mx` | 11332/11334 | rspamd instance for MX |
| `relay-rspamd-mta` | 11332/11334 | rspamd instance for MTA |
| `relay-rspamd-fwd` | 11332/11334 | rspamd instance for FWD |
| `relay-postsrsd` | 10001/10002 | SRS forward/reverse lookup |

## Docker image

One image, behaviour controlled by `RELAY_TYPE`:

```sh
docker run -e RELAY_TYPE=mx   ghcr.io/yarilomail/yarilo-postfix:latest
docker run -e RELAY_TYPE=mta  ghcr.io/yarilomail/yarilo-postfix:latest
docker run -e RELAY_TYPE=fwd  ghcr.io/yarilomail/yarilo-postfix:latest
```

## Environment variables

### Common (all types)

| Variable | Default | Description |
|:---|:---|:---|
| `MAIL_DOMAIN` | `example.com` | Primary domain |
| `MAIL_HOSTNAME` | `mail.example.com` | SMTP banner hostname |
| `MAIL_MYNETWORKS` | `127.0.0.0/8 10.0.0.0/8` | Trusted networks |
| `MAIL_DOMAINS` | `$MAIL_DOMAIN` | Space-separated virtual domains |
| `MYSQL_HOST` | `localhost` | MySQL host |
| `MYSQL_USER` | `postfix` | MySQL user |
| `MYSQL_PASSWORD` | — | MySQL password |
| `MYSQL_DBNAME` | `yarilo` | MySQL database name |

### MX

| Variable | Default | Description |
|:---|:---|:---|
| `LMTP_HOST` | `yarilo-lmtp` | yarilo-lmtp service hostname |
| `LMTP_PORT` | `24` | yarilo-lmtp port |
| `RSPAMD_ADDR` | `localhost:11332` | rspamd milter address |
| `RBL_RESTRICTIONS` | — | Extra `smtpd_recipient_restrictions` entries |

### MTA

| Variable | Default | Description |
|:---|:---|:---|
| `LMTP_HOST` | `yarilo-lmtp` | yarilo-lmtp service hostname |
| `LMTP_PORT` | `24` | yarilo-lmtp port |
| `SASL_LOGIN_ADDR` | `yarilo-sasl-login:12345` | yarilo-sasl-login address |
| `RSPAMD_ADDR` | `localhost:11332` | rspamd milter address |

### FWD

| Variable | Default | Description |
|:---|:---|:---|
| `RSPAMD_ADDR` | `localhost:11332` | rspamd milter address |
| `POSTSRSD_ADDR` | `yarilo-postsrsd:10001` | postsrsd forward address |
| `POSTSRSD_REVERSE_ADDR` | `yarilo-postsrsd:10002` | postsrsd reverse address |
| `LMTP_HOST` | — | If set, enables local delivery to yarilo |
| `LMTP_PORT` | `24` | yarilo-lmtp port (used when `LMTP_HOST` is set) |

## MySQL schema

The following tables are read from the yarilo MySQL database:

```sql
-- virtual mailbox domains
SELECT domain FROM domain WHERE domain='%s' AND active=1

-- alias expansion
SELECT goto FROM alias WHERE address='%s' AND active=1
```

Required tables: `domain (domain, active)`, `alias (address, goto, active)`.

## Helm

```sh
# Deploy to yarilo-relay namespace
helm upgrade --install yarilo-relay helm/ \
  -n yarilo-relay --create-namespace \
  -f helm_values/values-sandbox.yaml
```

### Key values

| Path | Default | Description |
|:---|:---|:---|
| `mx.enabled` | `false` | Enable MX deployment |
| `mta.enabled` | `false` | Enable MTA deployment |
| `fwd.enabled` | `false` | Enable FWD deployment |
| `postsrsd.enabled` | `false` | Enable postsrsd deployment |
| `yarilo.lmtpHost` | — | yarilo-lmtp hostname |
| `yarilo.lmtpPort` | `24` | yarilo-lmtp port |
| `yarilo.saslLoginAddr` | — | yarilo-sasl-login address |
| `mysql.secretName` | — | Secret with `MYSQL_HOST/USER/PASSWORD/DBNAME` keys |
| `tls.secretName` | — | TLS secret for STARTTLS |
| `dkim.secretName` | — | Secret with DKIM private key files |
| `dkim.selector` | `mail` | DKIM selector |
| `mx.rblRestrictions` | — | Extra Postfix RBL restriction entries |

### MySQL secret

```sh
kubectl create secret generic yarilo-postfix-mysql \
  --from-literal=MYSQL_HOST=yarilo-mysql \
  --from-literal=MYSQL_USER=yarilo \
  --from-literal=MYSQL_PASSWORD=<password> \
  --from-literal=MYSQL_DBNAME=yarilo \
  -n yarilo-relay
```

### DKIM secret

The secret must contain key files named `<domain>.<selector>.key`:

```sh
kubectl create secret generic yarilo-postfix-dkim \
  --from-file=example.com.mail.key=./example.com.mail.key \
  -n yarilo-relay
```

## Release

Bumping `appVersion` in `helm/Chart.yaml` triggers a GitHub Release and pushes a versioned image tag to GHCR.
