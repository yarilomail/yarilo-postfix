#!/usr/bin/env bash
# Render checks on the chart: which DKIM signer each relay is given, and the
# combinations that must refuse to render.
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

fails=0
base=(--set fwd.enabled=true --set mta.enabled=true --set mail.domain=example.org)

# signer <relay> <helm args...>: DKIM_MILTER_ADDR of that relay's Deployment, or "none".
signer() {
  local relay="$1"; shift
  helm template t helm/ "${base[@]}" "$@" \
    | awk -v d="name: $relay" '$0 ~ "^kind: Deployment" {k=1} k && $0 ~ "^  "d"$" {in_d=1} /^---/ {k=0; in_d=0}
        in_d && /name: DKIM_MILTER_ADDR/ {getline; gsub(/.*value: |"/, ""); print; found=1; exit}
        END {if (!found) print "none"}'
}
# envvar <deployment> <NAME> <helm args...>: that variable's value, or "none".
envvar() {
  local dep="$1" var="$2"; shift 2
  helm template t helm/ "${base[@]}" "$@" \
    | awk -v d="name: $dep" -v v="name: $var" '$0 ~ "^kind: Deployment" {k=1} k && $0 ~ "^  "d"$" {in_d=1} /^---/ {k=0; in_d=0}
        in_d && $0 ~ v"$" {getline; if ($0 ~ /value:/) {gsub(/.*value: |"/, ""); print} else print "secret"; found=1; exit}
        END {if (!found) print "none"}'
}
want() {
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got '$2', want '$3'"; fails=$((fails + 1)); fi
}
refuses() {
  local name="$1" msg="$2"; shift 2
  local out
  if out=$(helm template t helm/ "${base[@]}" "$@" 2>&1); then
    echo "FAIL $name: rendered"; fails=$((fails + 1))
  elif [[ "$out" == *"$msg"* ]]; then echo "ok   $name"
  else echo "FAIL $name: $out"; fails=$((fails + 1)); fi
}

want "no signer: relay-fwd" "$(signer relay-fwd)" none
want "mailfrom-milter off by default" "$(envvar relay-mta MAILFROM_MILTER_ADDR)" none
want "mailfrom-milter on relay-mta" "$(envvar relay-mta MAILFROM_MILTER_ADDR --set mta.mailfromMilter.addr=mailfrom-milter:10031)" mailfrom-milter:10031
want "mailfrom-milter not on relay-fwd" "$(envvar relay-fwd MAILFROM_MILTER_ADDR --set mta.mailfromMilter.addr=mailfrom-milter:10031)" none
want "shared addr: relay-mta" "$(signer relay-mta --set dkimMilter.addr=dkim-milter:8891)" dkim-milter:8891
want "shared addr: relay-fwd" "$(signer relay-fwd --set dkimMilter.addr=dkim-milter:8891)" dkim-milter:8891
want "fwd addr: relay-fwd" "$(signer relay-fwd --set dkimMilter.addr=dkim-milter:8891 --set fwd.dkimMilter.addr=dkim-milter-fwd:8891)" dkim-milter-fwd:8891
want "fwd addr: relay-mta keeps the shared one" "$(signer relay-mta --set dkimMilter.addr=dkim-milter:8891 --set fwd.dkimMilter.addr=dkim-milter-fwd:8891)" dkim-milter:8891
want "fwd addr alone: relay-fwd" "$(signer relay-fwd --set fwd.dkimMilter.addr=dkim-milter-fwd:8891)" dkim-milter-fwd:8891
want "opendkim: relay-fwd" "$(signer relay-fwd --set opendkim.enabled=true)" relay-opendkim:8891
refuses "dkimMilter.addr with opendkim" "dkimMilter.addr and opendkim.enabled both set" \
  --set dkimMilter.addr=dkim-milter:8891 --set opendkim.enabled=true
refuses "fwd.dkimMilter.addr with opendkim" "fwd.dkimMilter.addr and opendkim.enabled both set" \
  --set fwd.dkimMilter.addr=dkim-milter-fwd:8891 --set opendkim.enabled=true

out=(--set fwdOut.enabled=true --set fwdOut.saslUser=fwd_out --set fwdOut.saslSecretName=s
  --set fwdOut.tls.secretName=out-tls --set fwd.tls.secretName=fwd-tls --set postsrsd.enabled=true
  --set dkimMilter.addr=dkim-milter:8891 --set fwdOut.dkimMilter.addr=dkim-milter-fwd:8891)
want "fwd-out: relay-fwd-out signs" "$(signer relay-fwd-out "${out[@]}")" dkim-milter-fwd:8891
want "fwd-out: relay-fwd does not sign" "$(signer relay-fwd "${out[@]}")" none
want "fwd-out: relay-fwd does not rewrite" "$(envvar relay-fwd POSTSRSD_HOST "${out[@]}")" none
want "fwd-out: relay-fwd hands over" "$(envvar relay-fwd FWD_OUT_ADDR "${out[@]}")" relay-fwd-out.default.svc.cluster.local:587
want "fwd-out: relay-fwd-out rewrites" "$(envvar relay-fwd-out POSTSRSD_HOST "${out[@]}")" relay-postsrsd
want "fwd-out: relay-mta keeps its signer" "$(signer relay-mta "${out[@]}")" dkim-milter:8891
want "postsrsd: relay-mx turns bounces back" "$(envvar relay-mx SRS_DOMAIN "${out[@]}" --set postsrsd.domain=fwd.example.org --set mx.enabled=true)" fwd.example.org
want "postsrsd: relay-mx checks recipients with postsrsd" "$(envvar relay-mx POSTSRSD_HOST "${out[@]}" --set mx.enabled=true)" relay-postsrsd
want "no postsrsd: relay-mx leaves SRS alone" "$(envvar relay-mx SRS_DOMAIN --set mx.enabled=true)" none
want "no fwd-out: relay-fwd rewrites as before" "$(envvar relay-fwd POSTSRSD_HOST)" relay-postsrsd
refuses "fwd.dkimMilter.addr with fwdOut" "relay-fwd-out signs, set fwdOut.dkimMilter.addr" \
  "${out[@]}" --set fwd.dkimMilter.addr=dkim-milter-fwd:8891
refuses "fwdOut without its login" "fwdOut.enabled needs fwdOut.saslUser and fwdOut.saslSecretName" \
  "${out[@]}" --set fwdOut.saslSecretName=
refuses "fwdOut without fwd" "fwdOut.enabled needs fwd.enabled" "${out[@]}" --set fwd.enabled=false
refuses "fwdOut without its TLS secret" "fwdOut.enabled needs fwdOut.tls.secretName" "${out[@]}" --set fwdOut.tls.secretName=
refuses "fwdOut without relay-fwd's CA" "fwdOut.enabled needs fwd.tls.secretName" "${out[@]}" --set fwd.tls.secretName=
refuses "fwdOut.dkimMilter.addr with opendkim" "fwdOut.dkimMilter.addr and opendkim.enabled both set" \
  "${out[@]}" --set dkimMilter.addr= --set opendkim.enabled=true

[ "$fails" -eq 0 ] || { echo "$fails render check(s) failed"; exit 1; }
