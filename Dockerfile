FROM ubuntu:22.04
ENV KAFKA_USER=kafka \
KAFKA_DATA_DIR=/var/lib/kafka/data \
JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64 \
KAFKA_HOME=/opt/kafka \
PATH=$PATH:/opt/kafka/bin

ARG KAFKA_VERSION=3.3.2
ARG SCALA_VERSION=2.13


RUN set -x \
    && apt-get update \
    && apt-get install -y openjdk-8-jre-headless wget gpg vim curl\
    && wget -q "https://downloads.apache.org/kafka/$KAFKA_VERSION/kafka_$SCALA_VERSION-$KAFKA_VERSION.tgz" \
    && wget -q "https://downloads.apache.org/kafka/$KAFKA_VERSION/kafka_$SCALA_VERSION-$KAFKA_VERSION.tgz.asc" \
    && wget -q "https://downloads.apache.org/kafka/KEYS" \
    && export GNUPGHOME="$(mktemp -d)" \
    && gpg --import KEYS \
    && gpg --batch --verify "kafka_$SCALA_VERSION-$KAFKA_VERSION.tgz.asc" "kafka_$SCALA_VERSION-$KAFKA_VERSION.tgz"\
    && tar -xzf "kafka_$SCALA_VERSION-$KAFKA_VERSION.tgz" -C /opt \
    && rm -r "$GNUPGHOME" "kafka_$SCALA_VERSION-$KAFKA_VERSION.tgz" "kafka_$SCALA_VERSION-$KAFKA_VERSION.tgz.asc"

COPY config/log4j.properties /opt/kafka_$SCALA_VERSION-$KAFKA_VERSION/config/
COPY config/kafka_client_jaas.conf /opt/kafka_$SCALA_VERSION-$KAFKA_VERSION/config/
COPY config/kafka_server_jaas.conf /opt/kafka_$SCALA_VERSION-$KAFKA_VERSION/config/
COPY config/consumer.properties /opt/kafka_$SCALA_VERSION-$KAFKA_VERSION/config/
COPY config/producer.properties /opt/kafka_$SCALA_VERSION-$KAFKA_VERSION/config/
COPY bin/kafka-console-consumer.sh /opt/kafka_$SCALA_VERSION-$KAFKA_VERSION/bin/
COPY bin/kafka-console-producer.sh /opt/kafka_$SCALA_VERSION-$KAFKA_VERSION/bin/

RUN set -x \
    && ln -s /opt/kafka_$SCALA_VERSION-$KAFKA_VERSION $KAFKA_HOME \
    && useradd $KAFKA_USER \
    && mkdir -p $KAFKA_DATA_DIR \
    && chown -R "$KAFKA_USER:$KAFKA_USER"  $KAFKA_HOME \
    && chown -R "$KAFKA_USER:$KAFKA_USER"  $KAFKA_DATA_DIR

WORKDIR $KAFKA_HOME