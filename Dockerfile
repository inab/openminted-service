FROM crystallang/crystal

USER root

ENV CRYSTAL_MAJOR_VERSION="0.23.1"
ENV CRYSTAL_MINOR_VERSION="2"

WORKDIR /tmp

COPY . .


RUN shards install

#RUN crystal build --no-debug --link-flags="-static" --release src/openminted-service.cr
#RUN crystal build --link-flags="-static" src/openminted-service.cr
RUN crystal build src/openminted-service.cr

#FROM alpine:latest
#FROM scratch

#RUN apk --no-cache add ca-certificates

#WORKDIR /tmp/
#RUN mkdir -p /tmp/public/

#COPY --from=0 /tmp/openminted-service .
#COPY public public

ENTRYPOINT ["./openminted-service"]
