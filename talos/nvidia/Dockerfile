FROM scratch as customization
COPY --from=docker.io/maksimkurb/nonfree-kmod-nvidia:v1.4.0-nvidia /lib/modules /lib/modules

FROM ghcr.io/siderolabs/installer:v1.5.4
COPY --from=docker.io/maksimkurb/kernel:v1.4.1-nvidia /boot/vmlinuz /usr/install/linux/amd64/vmlinuz
