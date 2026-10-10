# Native release builder: Ubuntu 22.04 / glibc 2.35, ARM64 and x64.
# The compiler baseline also bounds the native adapter's required GLIBC symbols.
FROM ubuntu:22.04@sha256:5ec03bb3441e8b0bf3b4f9cd4629a1ae763010dc3035bb8da3ae6cf026486401
ARG TARGETARCH
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates curl unzip build-essential cmake pkg-config python3 patchelf \
    libssl-dev libudev-dev libcbor-dev zlib1g-dev git \
 && rm -rf /var/lib/apt/lists/*

RUN case "$TARGETARCH" in \
      arm64) arch=arm64; checksum=19a731647c3ed55058ee46dde00330150e6a8729bb6121b4a31e86084c8a3e6d ;; \
      amd64) arch=x64; checksum=ea864bc64df30a6b8bdf30b2e32550f7717d9a890de8f40293aeabb924fe232b ;; \
      *) exit 64 ;; \
    esac \
 && curl -fsSL --retry 3 "https://storage.googleapis.com/dart-archive/channels/stable/release/3.13.5/sdk/dartsdk-linux-${arch}-release.zip" -o /tmp/dart.zip \
 && echo "$checksum  /tmp/dart.zip" | sha256sum -c - \
 && unzip -q /tmp/dart.zip -d /opt && rm /tmp/dart.zip
ENV PATH="/opt/dart-sdk/bin:$PATH"

# Ubuntu's libfido2 is below the adapter's required 1.16 minimum.
RUN curl -fsSL --retry 3 https://github.com/Yubico/libfido2/archive/refs/tags/1.17.0.tar.gz -o /tmp/fido.tar.gz \
 && echo 'ace062d14a482ff9325410ff63d06c8b5fe87e79ebc18dda07add2bc0188c77f  /tmp/fido.tar.gz' | sha256sum -c - \
 && tar -xzf /tmp/fido.tar.gz -C /tmp \
 && cmake -S /tmp/libfido2-1.17.0 -B /tmp/fido-build -DCMAKE_BUILD_TYPE=Release -DBUILD_TOOLS=OFF -DBUILD_EXAMPLES=OFF -DBUILD_MANPAGES=OFF \
 && cmake --build /tmp/fido-build --parallel 4 && cmake --install /tmp/fido-build \
 && ldconfig && rm -rf /tmp/fido.tar.gz /tmp/fido-build /tmp/libfido2-1.17.0

# Temporary RK-distributed SDK command; the installed Dart SDK stays stock.
# The first source release had macOS-only scripts. Use the reviewed Linux
# wrappers from RK #117 until its next helper release includes them.
RUN curl -fsSL --retry 3 https://github.com/danReynolds/release-kit/releases/download/dart-build-patch-3.13.5-1/rk-dart-build-3.13.5-1-source.tar.gz -o /tmp/helper.tar.gz \
 && echo 'e507671d5bb0ef3f34d9e31a69d01a3c19b27e65dc6d74653125b79981783d1c  /tmp/helper.tar.gz' | sha256sum -c - \
 && mkdir /opt/rk-dart-build && tar -xzf /tmp/helper.tar.gz -C /opt/rk-dart-build --strip-components=1 \
 && rm /tmp/helper.tar.gz \
 && curl -fsSL --retry 3 https://raw.githubusercontent.com/danReynolds/release-kit/04f53573d611c7b89c119883d7d1e82f976643f3/tool/dart_build_patch/rebuild.sh -o /opt/rk-dart-build/rebuild.sh \
 && curl -fsSL --retry 3 https://raw.githubusercontent.com/danReynolds/release-kit/04f53573d611c7b89c119883d7d1e82f976643f3/tool/dart_build_patch/rk-dart-build -o /opt/rk-dart-build/rk-dart-build \
 && chmod +x /opt/rk-dart-build/rebuild.sh /opt/rk-dart-build/rk-dart-build \
 && /opt/rk-dart-build/rebuild.sh /opt/dart-sdk \
 && rm -rf /opt/rk-dart-build/packages
ENV PATH="/opt/rk-dart-build:$PATH"
