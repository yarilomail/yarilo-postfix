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
