# Pinned by digest, the same base as the other yarilomail images; dependabot
# moves it. apk upgrade takes the security fixes newer than the base.
FROM alpine:3.24@sha256:f59abe656b692d901e184be3445e084786602108599d2a51d229c0f5a48c71bf
RUN apk upgrade --no-cache \
    && apk add --no-cache \
    postfix \
    postfix-mysql \
    postfix-pcre \
    ca-certificates \
    cyrus-sasl \
    cyrus-sasl-login \
    db \
    && mkdir -p /etc/postfix/sasl /etc/sasl2
COPY scripts/entrypoint.sh /entrypoint.sh
COPY scripts/common.sh /common.sh
COPY scripts/own-ar-regexp.sh /own-ar-regexp.sh
COPY scripts/configure-mx.sh /configure-mx.sh
COPY scripts/configure-mta.sh /configure-mta.sh
COPY scripts/configure-fwd.sh /configure-fwd.sh
COPY scripts/configure-fwd-out.sh /configure-fwd-out.sh
RUN chmod +x /entrypoint.sh /configure-mx.sh /configure-mta.sh /configure-fwd.sh /configure-fwd-out.sh
ENTRYPOINT ["/entrypoint.sh"]
