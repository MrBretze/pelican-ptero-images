FROM        --platform=$TARGETOS/$TARGETARCH amazoncorretto:25

LABEL       author="Michael Parker and MrBretzel" maintainer="parker@pelican.dev"

LABEL       org.opencontainers.image.source="https://github.com/pelican-eggs/yolks"
LABEL       org.opencontainers.image.licenses=MIT

RUN dnf update -y \
 && dnf install -y \
      ca-certificates \
      openssl \
      git \
      tar \
      sqlite \
      fontconfig \
      freetype \
      freetype-devel \
      lsof \
      tzdata \
      iproute \
      gcc \
      gcc-c++ \
      automake \
      make \
      libtool \
      libstdc++ \
 && dnf clean all \
 && rm -rf /var/cache/dnf \
 && useradd -m -d /home/container container

## Setup user and working directory
ENV LC_ALL=en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US.UTF-8

USER container
ENV USER=container HOME=/home/container
WORKDIR /home/container

COPY        --chown=container:container ./entrypoint.sh /entrypoint.sh
RUN         chmod +x /entrypoint.sh
CMD [ "/bin/bash", "/entrypoint.sh" ]
