FROM amazon/aws-cli:2.38.5@sha256:c8156a0e74e13929a42d7e60f0d4e14e7d28d980cd21822505d4bff80e5460c1

RUN dnf install -y git tar gzip \
    && dnf clean all \
    && rm -rf /var/cache/dnf
