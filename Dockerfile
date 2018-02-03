FROM crystallang/crystal:0.23.1

USER root

#RUN apt-get update && apt-get install --install-suggests -y \
#RUN apt-get update && apt-get install -y \
  #libbsd-dev \
  #libedit-dev \
  #libevent-core-2.0-5 \
  #libevent-dev \
  #libevent-extra-2.0-5 \
  #libevent-openssl-2.0-5 \
  #libevent-pthreads-2.0-5 \
  #libgmp-dev \
  #libgmpxx4ldbl \
  #libssl-dev \
  #libxml2-dev \
  #libyaml-dev \
  #libreadline-dev \
  #automake \
  #libtool \
  #git \
  #llvm \
  #libpcre3-dev \
  #build-essential \
  #libgc-dev

#RUN apt-get install --install-suggests -y liblzma-dev lzma-dev libc6-dev zlib1g-dev libicu-dev gcc-5 gcc-5-multilib

#RUN ld --verbose | grep SEARCH_DIR | tr -s ' ;'

#RUN apt-cache search gcc

#ENV LIBRARY_PATH=/opt/crystal/embedded/lib/

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
