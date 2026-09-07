# Shared local environment for the Linux and Flatpak regression scripts.
FROM dart@sha256:f48c691889e1ef78bc48a7036ee505e95921a413b35f01c950d0108c9537daee AS dart
FROM ubuntu:24.04@sha256:33ceb71981b602c1a7443a53469e4dba065f7503eab3078a2d7a57a2ab987517
ENV DEBIAN_FRONTEND=noninteractive CI=true DART_SUPPRESS_ANALYTICS=true
RUN apt-get update -qq && apt-get install -y --no-install-recommends ca-certificates flatpak xdg-desktop-portal gnome-keyring dbus libglib2.0-bin python3 sudo procps bubblewrap gcr xvfb xdotool && rm -rf /var/lib/apt/lists/*
COPY --from=dart /usr/lib/dart /usr/lib/dart
ENV PATH="/usr/lib/dart/bin:${PATH}"
RUN useradd --create-home --uid 10001 keybay-test && printf 'keybay-test ALL=(ALL) NOPASSWD: ALL\n' > /etc/sudoers.d/keybay-test && chmod 440 /etc/sudoers.d/keybay-test
