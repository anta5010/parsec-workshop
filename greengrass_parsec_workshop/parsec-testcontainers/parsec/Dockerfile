ARG REGISTRY
FROM amazonlinux:2 as builder

RUN set -e -x; \
    yum install -y git shadow-utils cmake3 make build-essential pkgconfig \
        clang automake autoconf-archive libtool protobuf-compiler \
        openssl-devel doxygen curl-devel ;\
    rm -rf /root/.cache && \
    yum clean all && \
    rm -rf /var/cache/yum && \
    rpm --rebuilddb && \
    ln -s /usr/bin/cmake3 /usr/bin/cmake

RUN git clone https://github.com/tpm2-software/tpm2-tss.git --branch 2.3.3
RUN cd tpm2-tss \
    && ./bootstrap \
    && ./configure --disable-doxygen-doc --disable-doxygen-man --prefix=/usr --libdir=/usr/lib64 \
    && make -j$(nproc) \
    && make install \
    && ldconfig
RUN rm -rf tpm2-tss

RUN git clone https://github.com/tpm2-software/tpm2-tools.git --branch 4.1.1
RUN cd tpm2-tools \
    && ./bootstrap \
    && ./configure --prefix=/usr \
    && make -j$(nproc) \
    && make install
RUN rm -rf tpm2-tools

RUN curl https://sh.rustup.rs -sSf | sh -s -- -y

# Workaround for incorrect aarch64 entry in cargo build
RUN ln -s /usr/bin/gcc /usr/bin/aarch64-linux-gnu-gcc

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

ARG PARSEC_BRANCH=0.8.1
ARG PARSEC_FEATURES="tpm-provider,mbed-crypto-provider,unix-peer-credentials-authenticator,direct-authenticator"
RUN set -e -x; \
    source $HOME/.cargo/env; \
    git clone https://github.com/parallaxsecond/parsec; \
    cd parsec; \
    git checkout ${PARSEC_BRANCH}; \
    cargo install --features "${PARSEC_FEATURES}" --path .; \
    cd ..; \
    rm -rf parsec

ARG PARSEC_UID=4000
ARG PARSEC_GID=4000
RUN set -e -x; \
    groupadd -g ${PARSEC_GID} parsec; \
    useradd -u ${PARSEC_UID} -g ${PARSEC_GID} -d /home/parsec parsec; \
    mkdir -p /var/lib/parsec /home/parsec /run/parsec /etc/parsec /usr/libexec/parsec; \
    chmod 700 /var/lib/parsec /etc/parsec /usr/libexec/parsec; \
    chmod 755 /run/parsec;

FROM amazonlinux:2 as run
ENV RUST_LOG=info
ARG PARSEC_UID=4000
ARG PARSEC_GID=4000
ARG PARSEC_CONFIG=config.toml

RUN yum install -y socat openssl which && \
    rm -rf /root/.cache && \
    yum clean all && \
    rm -rf /var/cache/yum && \
    rpm --rebuilddb

COPY --from=builder /usr/lib64/libtss2* /usr/lib64/
#COPY --from=builder /usr/lib64/pkgconfig/tss2* /usr/lib64/
#COPY --from=builder /usr/include/tss2 /usr/include
COPY --from=builder /usr/lib64/udev/rules.d/tpm-udev.rules /usr/lib64/udev/rules.d/
COPY --from=builder /usr/bin/tpm2* /usr/bin/

COPY --from=builder /etc/passwd /etc/passwd
COPY --from=builder /etc/group /etc/group
COPY --from=builder /root/.cargo/bin/parsec* /usr/bin/
COPY --from=builder /usr/bin/parsec-cli-tests.sh /usr/bin/

COPY ${PARSEC_CONFIG} /etc/parsec/config.toml
COPY --from=builder --chown=${PARSEC_UID}:${PARSEC_GID} /usr/libexec/parsec /usr/libexec/parsec
COPY --from=builder --chown=${PARSEC_UID}:${PARSEC_GID} /var/lib/parsec /var/lib/parsec
COPY --from=builder --chown=${PARSEC_UID}:${PARSEC_GID} /home/parsec /home/parsec
COPY --from=builder --chown=${PARSEC_UID}:${PARSEC_GID} /run/parsec /run/parsec
COPY --from=builder --chown=${PARSEC_UID}:${PARSEC_GID} /etc/parsec /etc/parsec

# FIXME volume mount problem
# Volumes are mounted as root first
#USER parsec:parsec
WORKDIR "/home/parsec"
CMD ["parsec", "-c", "/etc/parsec/config.toml"]