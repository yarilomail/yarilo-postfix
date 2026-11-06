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

[ "$fails" -eq 0 ] || { echo "$fails render check(s) failed"; exit 1; }
