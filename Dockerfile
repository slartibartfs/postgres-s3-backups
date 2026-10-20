ARG ALPINE_VERSION
FROM alpine:${ALPINE_VERSION} as alpine

ARG POSTGRES_VERSION
# coreutils: GNU-date fuer "date -d '+400 days'" (Busybox kann das nicht)
# curl:      Lebenszeichen an den Waechter (HEALTHCHECK_URL)
RUN apk add --no-cache postgresql$POSTGRES_VERSION-client \
      aws-cli coreutils curl
WORKDIR /scripts

COPY backup.sh .
ENTRYPOINT [ "sh", "backup.sh" ]
