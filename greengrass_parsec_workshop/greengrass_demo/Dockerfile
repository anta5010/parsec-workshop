FROM parallaxsecond/greengrass_patched:latest as from_source_builder
COPY aws-greengrass-parsec-provider /project/aws-greengrass-parsec-provider
RUN cd /project/aws-greengrass-parsec-provider && \
     ./mvnw clean install -DskipTests=true -Dcontainers.skip=true

RUN curl https://sh.rustup.rs -sSf | sh -s -- -y

RUN yum install -y git gcc

ARG PARSEC_TOOL_VERSION=0.5.2
RUN set -e -x; \
    source $HOME/.cargo/env; \
    git clone https://github.com/parallaxsecond/parsec-tool; \
    cd parsec-tool; \
    git checkout ${PARSEC_TOOL_VERSION}; \
    cargo install --path .; \
    cp tests/parsec-cli-tests.sh /usr/bin/; \
    cd ..; \
    rm -rf parsec-tool

FROM parallaxsecond/greengrass_patched:latest
RUN yum install -y which openssl

COPY --from=from_source_builder /project/aws-greengrass-parsec-provider/parsec-greengrass-plugin/target/aws.greengrass.crypto.ParsecProvider.jar /provider.jar
COPY --from=from_source_builder /root/.cargo/bin/parsec-tool /usr/bin/
COPY --from=from_source_builder /usr/bin/parsec-cli-tests.sh /usr/bin/

COPY greengrass_demo/config.yml /greengrass/
COPY greengrass_demo/*.sh /greengrass/

ENTRYPOINT ["/greengrass/demo_start.sh"]
