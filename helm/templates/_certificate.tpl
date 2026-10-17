{{/*
A cert-manager Certificate writing secretName. Args: dict "secretName" "cert" "app".
*/}}
{{- define "yarilo-postfix.certificate" -}}
{{- if not .cert.issuerRef.name }}
{{- fail (printf "%s: certificate.issuerRef.name is required" .secretName) }}
{{- end }}
{{- if not .cert.dnsNames }}
{{- fail (printf "%s: certificate.dnsNames is required" .secretName) }}
{{- end }}
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: {{ .secretName }}
  labels:
    app: {{ .app }}
spec:
  secretName: {{ .secretName }}
  renewBefore: {{ .cert.renewBefore }}
  issuerRef:
    name: {{ .cert.issuerRef.name }}
    kind: {{ .cert.issuerRef.kind }}
    group: cert-manager.io
  dnsNames:
    {{- toYaml .cert.dnsNames | nindent 4 }}
{{- end }}
