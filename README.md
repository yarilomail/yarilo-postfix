# yarilo-postfix

Postfix relay stack for the yarilo mail platform. Ships four deployment types from a single Docker image, each controlled by `RELAY_TYPE`.

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

FWD (with relay-fwd-out)
  yarilo Sieve ──► relay-fwd :587 (SASL, TLS)
                     │  milter
                     ├──────────► rspamd :11332 (spam, viruses)
                     │
                     ├── local domain ──► yarilo-lmtp :24 (no signature, no SRS)
                     └── other ──► relay-fwd-out :587 (SASL, TLS from the internal CA)
                                     │  milter
                                     ├──────────► dkim-milter-fwd :8891 (signHopsBefore 1)
                                     │  sender_canonical_maps
                                     ├──────────► local domains: kept; others: postsrsd :10003
                                     └──────────► external MX

  Bounce to SRS0=...@<postsrsd.domain> ──► relay-mx :25 ──► postsrsd reverse ──► original sender
```

## Components

| Deployment | Port | Function |
|:---|:---|:---|
| `relay-mx` | 25 | Inbound MX — spam/RBL scan, LMTP delivery to yarilo |
| `relay-mta` | 587 | Submission — SASL auth via yarilo-sasl-login, DKIM sign |
| `relay-fwd` | 587 | Sieve sender's entry: rspamd, local domains by LMTP; with `fwdOut.enabled` the rest to relay-fwd-out, otherwise it signs and rewrites itself |
| `relay-fwd-out` | 587 | Forwarded mail out: DKIM sign (dkim-milter-fwd), SRS for senders outside the local domains, rate limit; relay-fwd is its only client |
| `relay-rspamd-mx` | 11332/11334 | rspamd instance for MX |
| `relay-rspamd-mta` | 11332/11334 | rspamd instance for MTA |
| `relay-rspamd-fwd` | 11332/11334 | rspamd instance for FWD |
| `relay-postsrsd` | 10001/10003 | SRS forward/reverse lookup (socketmap 10003) |

## Docker image

One image, behaviour controlled by `RELAY_TYPE`:

```sh
docker run -e RELAY_TYPE=mx   ghcr.io/yarilomail/yarilo-postfix:latest
docker run -e RELAY_TYPE=mta  ghcr.io/yarilomail/yarilo-postfix:latest
docker run -e RELAY_TYPE=fwd  ghcr.io/yarilomail/yarilo-postfix:latest
docker run -e RELAY_TYPE=fwd-out ghcr.io/yarilomail/yarilo-postfix:latest
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
| `MAILFROM_MILTER_ADDR` | — | mailfrom-milter, after rspamd and before the signer, `default_action=tempfail` |
| `DKIM_MILTER_ADDR` | — | DKIM signer, `default_action=tempfail` |

`smtpd_sender_restrictions` is `reject_authenticated_sender_login_mismatch` alone, so an authenticated client in `mynetworks` is held to it too. `smtpd_sender_login_maps` reads the MySQL tables: a login owns its own `mailbox` address and every active `alias` row that names it in `goto` (a list counts, a `goto` that is another alias is not followed, a catch-all gives nothing). Sending as an alias stays within the login's domain: a `goto` naming a login in another domain passes this map, and mailfrom-milter refuses it. yarilo's `identity_aliases` should be built by the same rule, in the login's domain, so a JMAP identity is never refused here.

### FWD

| Variable | Default | Description |
|:---|:---|:---|
| `RSPAMD_ADDR` | `localhost:11332` | rspamd milter address |
| `POSTSRSD_HOST` | — | postsrsd host; SRS socketmap on 10003. Must be empty with `FWD_OUT_ADDR` |
| `DKIM_MILTER_ADDR` | — | DKIM signer; must be empty with `FWD_OUT_ADDR` |
| `LMTP_ADDR` | — | `host:port` of yarilo's LMTP; if set, local domains are delivered there |
| `SASL_USER`, `SASL_PASSWORD` | — | the Sieve sender's login on 587 |
| `FWD_OUT_ADDR` | — | `host:port` of relay-fwd-out; mail for other domains goes there |
| `FWD_OUT_SASL_USER`, `FWD_OUT_SASL_PASSWORD` | — | relay-fwd's login on relay-fwd-out; the certificate is verified against `ca.crt` of relay-fwd's own TLS secret |

### FWD-OUT

| Variable | Default | Description |
|:---|:---|:---|
| `SASL_USER`, `SASL_PASSWORD` | required | the one account allowed in on 587 (relay-fwd's) |
| `DKIM_MILTER_ADDR` | — | DKIM signer (dkim-milter-fwd), `default_action=tempfail` |
| `POSTSRSD_HOST` | — | postsrsd host; a sender of an active domain in the `domain` table keeps its address |
| `RATE_LIMIT` | `0` | messages per minute from relay-fwd, all mailboxes together; 0 is off |

Port 25 is not opened; a TLS secret is required.

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
| `postsrsd.enabled` | `false` | Enable postsrsd deployment; relay-mx then accepts the SRS domain, reverses its addresses and refuses at RCPT one postsrsd does not reverse |
| `postsrsd.domain` | `mail.domain` | SRS domain. With relay-fwd-out it must equal dkim-milter-fwd's `signDomain` (the other chart), and its MX must point at relay-mx |
| `fwdOut.enabled` | `false` | Deploy relay-fwd-out; needs `fwd.enabled`, `fwd.tls.secretName`, `fwdOut.saslUser`, `fwdOut.saslSecretName` and `fwdOut.tls.secretName`. `fwd.dkimMilter.addr` beside it refuses to render |
| `fwdOut.saslUser`, `fwdOut.saslSecretName` | --- | relay-fwd's login on relay-fwd-out; the Secret's `password` key is read by both relays |
| `fwdOut.dkimMilter.addr` | --- | relay-fwd-out's signer, e.g. `dkim-milter-fwd:8891`; with `opendkim.enabled` it refuses to render |
| `fwdOut.tls.secretName`, `fwdOut.tls.certificate.*` | --- | relay-fwd-out's certificate, as `fwd.tls`; its names must cover `relay-fwd-out.<namespace>.svc.cluster.local` |
| `fwdOut.rateLimit.messagesPerMinute` | `0` | forwarded messages per minute through relay-fwd-out; over it relay-fwd gets 4xx and retries from its queue |
| `fwdOut.service.port` | `587` | relay-fwd-out's port |
| `yarilo.lmtpHost` | — | yarilo-lmtp hostname |
| `yarilo.lmtpPort` | `24` | yarilo-lmtp port |
| `yarilo.saslLoginAddr` | — | yarilo-sasl-login address |
| `mysql.secretName` | — | Secret with `MYSQL_HOST/USER/PASSWORD/DBNAME` keys |
| `tls.secretName` | — | TLS secret for STARTTLS. relay-mta and relay-fwd listen on 587 with STARTTLS only, so each needs this or its own `mta.tls.secretName` / `fwd.tls.secretName`; without one the chart refuses to render |
| `tls.certificate.enabled` | `false` | cert-manager writes `tls.secretName` (a `Certificate` of that name) |
| `tls.certificate.issuerRef.name` / `.kind` | — / `ClusterIssuer` | Issuer of that certificate |
| `tls.certificate.dnsNames` / `.renewBefore` | `[]` / `720h` | Names and renewal margin |
| `mta.tls.secretName` | — | relay-mta's own TLS secret in place of `tls.secretName` |
| `mta.tls.certificate.*` | off; `kind: Issuer` | cert-manager writes `mta.tls.secretName`; same fields as `tls.certificate` |
| `mta.tls.issuer.enabled` / `.caSecretName` | `false` / — | Create the CA `Issuer` named by `mta.tls.certificate.issuerRef.name` on that CA secret |
| `fwd.tls.secretName` | — | relay-fwd's own TLS secret in place of `tls.secretName` |
| `fwd.tls.certificate.*` | off; `kind: Issuer` | cert-manager writes `fwd.tls.secretName`; same fields as `tls.certificate`, the Issuer from `mta.tls.issuer` |
| `dkim.secretName` | — | Secret with DKIM private key files |
| `dkim.selector` | `mail` | DKIM selector |
| `opendkim.enabled` | `false` | run the bundled OpenDKIM (`relay-opendkim`) as the DKIM signer |
| `dkimMilter.addr` | --- | the DKIM signer as `host:port`, e.g. `dkim-milter:8891` ([yarilomail/dkim-milter](https://github.com/yarilomail/dkim-milter)), added after rspamd to `smtpd_milters` and `non_smtpd_milters` of `relay-mta` and `relay-fwd` (`DKIM_MILTER_ADDR`) with `default_action=tempfail`, so mail waits in the queue while the signer is down; rspamd keeps `milter_default_action = accept`. Set with `opendkim.enabled` it refuses to render |
| `mta.mailfromMilter.addr` | --- | mailfrom-milter as `host:port`, e.g. `mailfrom-milter:10031` ([yarilomail/mailfrom-milter](https://github.com/yarilomail/mailfrom-milter)), added to `relay-mta` only (`MAILFROM_MILTER_ADDR`) between rspamd and the signer with `default_action=tempfail`: an authenticated message whose `MAIL FROM` domain is not the login's, or whose `From:` domain is not the `MAIL FROM` domain, is refused before it is signed |
| `fwd.dkimMilter.addr` | --- | `relay-fwd`'s DKIM signer in place of `dkimMilter.addr`, e.g. `dkim-milter-fwd:8891`, the dkim-milter release with `SIGN_DOMAIN` that signs forwarded mail with the forwarder's domain; empty takes `dkimMilter.addr`. Set with `opendkim.enabled` it refuses to render |
| `mx.rblRestrictions` | — | Extra Postfix RBL restriction entries |
| `mx.clientAddress.from` | `[]` | With `networkPolicy.enabled`: the pods that dial `mx.clientAddress.xclientPort` and `.proxyPort`, as NetworkPolicy peers; a set port with no peer refuses to render |
| `networkPolicy.enabled` | `false` | One ingress NetworkPolicy per relay pod, see [NetworkPolicy](#networkpolicy) |
| `networkPolicy.submissionFrom` | `[]` | The pods that dial relay-mta:587 (yarilo's Submission and JMAP sending) |
| `networkPolicy.forwardFrom` | `[]` | The pods that dial relay-fwd:587 (yarilo's Sieve redirect and vacation) |

### relay-mta's and relay-fwd's certificates from an internal CA

yarilo dials both by their service names: Submission to relay-mta, the Sieve sender (vacation, redirect, notify) to relay-fwd:587. Each gets its own certificate on those names (`mta.tls`, `fwd.tls`) from one CA `Issuer`, so yarilo verifies both against its internal CA. relay-fwd-out (`fwdOut.tls`) takes its certificate from the same `Issuer`, and relay-fwd verifies it with the `ca.crt` of its own secret. relay-mx keeps `tls.secretName`.

With `mta.tls.issuer` on, the chart creates the CA `Issuer`; the CA's secret it reads is the one thing copied by hand, once, into the release's namespace. For the stand, from yarilo's internal CA:

```sh
kubectl -n yarilo-sb get secret yarilo-internal-ca -o json \
  | jq '{apiVersion, kind, type, data, metadata: {name: "yarilo-internal-ca", namespace: "yarilo-relay"}}' \
  | kubectl apply -f -
```

The copy follows the CA's own lifetime (renewed a year before 2036-07-23); copy it again when the CA is renewed.

### relay-fwd-out's login

relay-fwd logs in to relay-fwd-out with `fwdOut.saslUser` and the `password` key of `fwdOut.saslSecretName`, made once:

```sh
kubectl -n yarilo-relay create secret generic fwd-out-sasl-secret \
  --from-literal=password="$(openssl rand -base64 32 | tr -d '\n')"
```

### NetworkPolicy

With `networkPolicy.enabled` each relay pod gets an ingress policy that opens only the ports something dials:

| Pod | Port | From |
|:---|:---|:---|
| relay-mx | 25 | anywhere |
| relay-mx | `mx.clientAddress.xclientPort`, `.proxyPort` | `mx.clientAddress.from` only: these listeners take the client address from the peer |
| relay-mta | 587 | `networkPolicy.submissionFrom` |
| relay-fwd | 587 | `networkPolicy.forwardFrom` |
| relay-fwd-out | 587 | relay-fwd, by its labels |

relay-mta and relay-fwd have no listener on 25: nothing dials it, and one there would take mail from `mail.mynetworks` without a login. A peer is `{podSelector, namespaceSelector}`; an empty list, or a peer whose `podSelector` is empty, refuses to render, so a slip never opens a port to a whole namespace. The milters, rspamd and postsrsd run in pods of their own that these policies do not select, so their ports are not covered here. Egress is not restricted.

```yaml
networkPolicy:
  enabled: true
  submissionFrom: &yarilo-backend
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: yarilo
      podSelector:
        matchLabels:
          app.kubernetes.io/component: backend
  forwardFrom: *yarilo-backend
```

### DNS records

For a mail domain `example.com` and the forwarding (SRS) domain `fwd.example.com`:

| Name | Type | Value |
|:---|:---|:---|
| `example.com` | MX | the public name of relay-mx, e.g. `10 mx.example.com.` |
| `example.com` | TXT | `v=spf1 ip4:<relay-mta egress IP> -all` |
| `<selector>._domainkey.example.com` | TXT | `v=DKIM1; k=rsa; p=<public key>` of dkim-milter's key for `example.com` |
| `_dmarc.example.com` | TXT | `v=DMARC1; p=quarantine; rua=mailto:dmarc@example.com` |
| `<relay-mta egress IP>` | PTR | the relay's hostname (`mail.hostname`), which resolves back to that IP |

Forwarded mail leaves relay-fwd-out with the sender rewritten to `fwd.example.com` (`postsrsd.domain`), so that domain needs records of its own:

| Name | Type | Value |
|:---|:---|:---|
| `fwd.example.com` | TXT | `v=spf1 ip4:<relay-fwd-out egress IP> -all` |
| `<selector>._domainkey.fwd.example.com` | TXT | `v=DKIM1; k=rsa; p=<public key>` of dkim-milter-fwd's key (`d=fwd.example.com`) |
| `fwd.example.com` | MX | relay-mx, which turns bounces to `SRS0=...@fwd.example.com` back to the sender |
| `<relay-fwd-out egress IP>` | PTR | a name that resolves back to that IP |

### SRS

postsrsd rewrites the envelope sender of forwarded mail on relay-fwd-out only, and only for senders outside the active domains of the `domain` table: a local sender's own domain already passes SPF from the relay. The SRS domain (`postsrsd.domain`) needs an MX at relay-mx, which accepts it as a relay domain and turns `SRS0=...@<domain>` back into the original sender, so a bounce of forwarded mail reaches the sender who wrote it. An address in that domain postsrsd does not reverse (forged, or past its lifetime) is refused at RCPT (`relay_recipient_maps` on the same lookup): relayed, it would come back to relay-mx through the domain's MX.

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

`test/render.sh` (run in CI after `helm lint`) checks which DKIM signer each relay renders with, that a signer address set beside `opendkim.enabled` refuses to render, and which ports each NetworkPolicy opens to whom.

## Release

Bumping `appVersion` in `helm/Chart.yaml` triggers a GitHub Release and pushes a versioned image tag to GHCR.
