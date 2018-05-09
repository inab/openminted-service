FROM crystallang/crystal:0.24.2

USER root

RUN mkdir -p /var/www && \
      mkdir -p /home/paradise/NERs/ && \
      ln -s /var/www/NLProt /home/paradise/NERs/
ADD http://inb.bsc.es/service/files/NLProt.tar.xz /var/www
WORKDIR /var/www/NLProt
RUN apt update && \
      apt install -y pixz gcc-multilib && \
      cd /var/www/ && \
      pixz -d < NLProt.tar.xz | tar x
#RUN chown -R root:root /var/www/NLProt/**/* && chmod -R 755 /var/www/NLProt/**/*
RUN ./install

RUN apt update && apt install -y libarchive-dev libicu-dev liblzma-dev libxml2-dev poppler-utils

RUN mkdir -p /var/www/nlprot

WORKDIR /var/www/nlprot

COPY . .

RUN shards install

RUN crystal build src/nlprot-service.cr

#RUN crystal build --link-flags="-static" src/nlprot-service.cr
ENTRYPOINT ["./nlprot-service"]
