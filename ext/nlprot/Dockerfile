#FROM ubuntu:16.04
FROM crystallang/crystal:0.23.1

USER root

RUN mkdir -p /var/www && \
      mkdir -p /home/paradise/NERs/ && \
      ln -s /var/www/NLProt /home/paradise/NERs/
COPY NLProt.tar.xz /var/www
WORKDIR /var/www/NLProt
RUN apt update && \
      apt install -y pixz gcc-multilib && \
      cd /var/www/ && \
      pixz -d < NLProt.tar.xz | tar x
#RUN chown -R root:root /var/www/NLProt/**/* && chmod -R 755 /var/www/NLProt/**/*
RUN ./install
#RUN ./nlprot -i test_input.txt -o test_well_done.txt

RUN apt install -y libarchive-dev libicu-dev liblzma-dev libxml2-dev

#ENV CRYSTAL_MAJOR_VERSION="0.23.1"
#ENV CRYSTAL_MINOR_VERSION="2"

RUN mkdir -p /var/www/nlprot

WORKDIR /var/www/nlprot

COPY . .

RUN shards install

RUN crystal build src/nlprot-service.cr

#RUN crystal build --link-flags="-static" src/nlprot-service.cr
#ENTRYPOINT ["./nlprot-service"]
CMD ["./nlprot-service"]
