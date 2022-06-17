FROM parallaxsecond/greengrass_patched:latest as from_source_builder

RUN apt-get update && \
    apt-get install -y git gcc autoconf automake libtool curl make g++ unzip coreutils

RUN git clone https://github.com/protocolbuffers/protobuf.git &&\
    cd protobuf &&\
    git submodule update --init --recursive &&\
    ./autogen.sh &&\
    ./configure --prefix=/usr &&\
    make -j$(nproc) &&\
    make install &&\
    ldconfig

COPY aws-greengrass-parsec-provider /project/aws-greengrass-parsec-provider
RUN cd /project/aws-greengrass-parsec-provider && \
    ./mvnw install:install-file -DgroupId=com.google.protobuf -DartifactId=protoc \
    -Dversion=3.18.0 -Dclassifier=linux-arm_32 -Dpackaging=exe -Dfile=$(which protoc) &&\
    ./mvnw clean install -DskipTests=true -Dcontainers.skip=true

RUN curl https://sh.rustup.rs -sSf | sh -s -- -y

ARG PARSEC_TOOL_VERSION=0.5.2
RUN set -e -x; \
    . $HOME/.cargo/env; \
    git clone https://github.com/parallaxsecond/parsec-tool; \
    cd parsec-tool; \
    git checkout ${PARSEC_TOOL_VERSION}; \
    cargo install --path .; \
    cp tests/parsec-cli-tests.sh /usr/bin/; \
    cd ..; \
    rm -rf parsec-tool

FROM parallaxsecond/greengrass_patched:latest
RUN apt-get update && \
    apt-get install -y debianutils openssl

COPY --from=from_source_builder /project/aws-greengrass-parsec-provider/parsec-greengrass-plugin/target/aws.greengrass.crypto.ParsecProvider.jar /provider.jar
COPY --from=from_source_builder /root/.cargo/bin/parsec-tool /usr/bin/
COPY --from=from_source_builder /usr/bin/parsec-cli-tests.sh /usr/bin/

COPY greengrass_demo/config.yml /greengrass/
COPY greengrass_demo/*.sh /greengrass/

ENTRYPOINT ["/greengrass/demo_start.sh"]
