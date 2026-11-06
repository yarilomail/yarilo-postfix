{{/*
Mail domains: mail.domain + extraDomains (if set).
*/}}
{{- define "yarilo-postfix.mailDomains" -}}
{{- if .Values.mail.extraDomains -}}
{{ .Values.mail.domain }} {{ .Values.mail.extraDomains }}
{{- else -}}
{{ .Values.mail.domain }}
{{- end -}}
{{- end -}}

{{/*
MySQL env vars from secret.
*/}}
{{- define "yarilo-postfix.mysqlEnv" -}}
- name: MYSQL_HOST
  value: {{ .mysql.host | quote }}
{{- if .mysql.secretName }}
- name: MYSQL_USER
  valueFrom:
    secretKeyRef:
      name: {{ .mysql.secretName }}
      key: MYSQL_USER
- name: MYSQL_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .mysql.secretName }}
      key: MYSQL_PASSWORD
- name: MYSQL_DBNAME
  valueFrom:
    secretKeyRef:
      name: {{ .mysql.secretName }}
      key: MYSQL_DATABASE
{{- end }}
{{- end -}}

{{/*
TLS volume mount — no-op when secretName is empty.
*/}}
{{- define "yarilo-postfix.tlsMount" -}}
{{- if . -}}
- name: tls
  mountPath: /etc/postfix/tls
  readOnly: true
{{- end -}}
{{- end -}}

{{/*
TLS volume — no-op when secretName is empty.
*/}}
{{- define "yarilo-postfix.tlsVolume" -}}
{{- if . -}}
- name: tls
  secret:
    secretName: {{ . }}
    defaultMode: 0440
{{- end -}}
{{- end -}}

{{/*
The DKIM signing milter both relays add: dkim-milter at dkimMilter.addr, or
the bundled OpenDKIM. Both at once would sign every message twice.
*/}}
{{- define "yarilo-postfix.dkimSigner" -}}
{{- if and .Values.dkimMilter.addr .Values.opendkim.enabled -}}
{{- fail "dkimMilter.addr and opendkim.enabled both set: pick one DKIM signer" -}}
{{- else if .Values.dkimMilter.addr -}}
{{- .Values.dkimMilter.addr -}}
{{- else if .Values.opendkim.enabled -}}
relay-opendkim:8891
{{- end -}}
{{- end }}

{{/*
relay-fwd's signer: fwd.dkimMilter.addr (the release that signs forwarded
mail with the forwarder's domain), else the one both relays share.
*/}}
{{- define "yarilo-postfix.fwdDkimSigner" -}}
{{- if and .Values.fwd.dkimMilter.addr .Values.opendkim.enabled -}}
{{- fail "fwd.dkimMilter.addr and opendkim.enabled both set: pick one DKIM signer" -}}
{{- else if .Values.fwd.dkimMilter.addr -}}
{{- .Values.fwd.dkimMilter.addr -}}
{{- else -}}
{{- include "yarilo-postfix.dkimSigner" . -}}
{{- end -}}
{{- end }}

{{/*
The SRS domain: postsrsd.domain, else mail.domain. It must equal
dkim-milter-fwd's signDomain, which lives in the other chart.
*/}}
{{- define "yarilo-postfix.srsDomain" -}}
{{- .Values.postsrsd.domain | default .Values.mail.domain -}}
{{- end }}

{{/*
relay-fwd-out's signer: fwdOut.dkimMilter.addr; OpenDKIM beside it refuses.
*/}}
{{- define "yarilo-postfix.fwdOutDkimSigner" -}}
{{- if and .Values.fwdOut.dkimMilter.addr .Values.opendkim.enabled -}}
{{- fail "fwdOut.dkimMilter.addr and opendkim.enabled both set: pick one DKIM signer" -}}
{{- end -}}
{{- .Values.fwdOut.dkimMilter.addr -}}
{{- end }}

{{/*
NetworkPolicy peers for one port: each needs a non-empty podSelector, so a
slip in values never opens the port to every pod of a namespace.
Call with (list "<values key>" <peers>).
*/}}
{{- define "yarilo-postfix.peers" -}}
{{- $key := index . 0 -}}
{{- $peers := index . 1 -}}
{{- if not $peers -}}
{{- fail (printf "%s is empty: name the pods that dial this port" $key) -}}
{{- end -}}
{{- range $peers -}}
{{- if not .podSelector -}}
{{- fail (printf "%s: every peer needs a non-empty podSelector" $key) -}}
{{- end }}
- podSelector:
    {{- toYaml .podSelector | nindent 4 }}
  {{- with .namespaceSelector }}
  namespaceSelector:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end -}}
{{- end }}
