FROM mcr.microsoft.com/devcontainers/base:ubuntu26.04

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

USER root

ARG KUBECTL_VERSION=1.36.3
ARG HELM_VERSION=4.3.0
ARG KUBECONFORM_VERSION=0.8.0
ARG KUBE_LINTER_VERSION=0.8.3
ARG ACTIONLINT_VERSION=1.7.12
ARG GITLEAKS_VERSION=8.30.1
ARG YQ_VERSION=4.54.1
ARG BUN_VERSION=1.4.0
ARG COMMITLINT_VERSION=21.2.3

ENV BUN_INSTALL=/usr/local

RUN apt-get update \
 && apt-get install -y --no-install-recommends shellcheck kustomize \
 && rm -rf /var/lib/apt/lists/*

COPY tools.tsv /tmp/tools.tsv

RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
      amd64) go_arch="amd64"; gl_arch="x64"; bun_arch="x64"; linter_asset="kube-linter-linux.tar.gz" ;; \
      arm64) go_arch="arm64"; gl_arch="arm64"; bun_arch="aarch64"; linter_asset="kube-linter-linux_arm64.tar.gz" ;; \
      *) echo "неподдерживаемая архитектура: $arch" >&2; exit 1 ;; \
    esac; \
    fetch() { \
      asset="$1"; url="$2"; out="$3"; \
      curl -fsSL --retry 3 -o "$out" "$url"; \
      expected="$(awk -v p="$asset" '$1 == p { print $2 }' /tmp/tools.tsv)"; \
      [ -n "$expected" ] || { echo "нет хэша для $asset" >&2; exit 1; }; \
      echo "$expected  $out" | sha256sum -c -; \
    }; \
    fetch "kubectl/${KUBECTL_VERSION}/kubectl-linux-${go_arch}" \
      "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/${go_arch}/kubectl" /tmp/kubectl; \
    install -m 0755 /tmp/kubectl /usr/local/bin/kubectl; \
    fetch "helm/${HELM_VERSION}/helm-${HELM_VERSION}-linux-${go_arch}.tar.gz" \
      "https://get.helm.sh/helm-v${HELM_VERSION}-linux-${go_arch}.tar.gz" /tmp/helm.tar.gz; \
    tar -xzf /tmp/helm.tar.gz -C /tmp "linux-${go_arch}/helm"; \
    install -m 0755 "/tmp/linux-${go_arch}/helm" /usr/local/bin/helm; \
    fetch "kubeconform/${KUBECONFORM_VERSION}/kubeconform-linux-${go_arch}.tar.gz" \
      "https://github.com/yannh/kubeconform/releases/download/v${KUBECONFORM_VERSION}/kubeconform-linux-${go_arch}.tar.gz" /tmp/kubeconform.tar.gz; \
    tar -xzf /tmp/kubeconform.tar.gz -C /tmp kubeconform; \
    install -m 0755 /tmp/kubeconform /usr/local/bin/kubeconform; \
    fetch "kube-linter/${KUBE_LINTER_VERSION}/${linter_asset}" \
      "https://github.com/stackrox/kube-linter/releases/download/v${KUBE_LINTER_VERSION}/${linter_asset}" /tmp/kube-linter.tar.gz; \
    tar -xzf /tmp/kube-linter.tar.gz -C /tmp kube-linter; \
    install -m 0755 /tmp/kube-linter /usr/local/bin/kube-linter; \
    fetch "actionlint/${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_${go_arch}.tar.gz" \
      "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_${go_arch}.tar.gz" /tmp/actionlint.tar.gz; \
    tar -xzf /tmp/actionlint.tar.gz -C /tmp actionlint; \
    install -m 0755 /tmp/actionlint /usr/local/bin/actionlint; \
    fetch "gitleaks/${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_${gl_arch}.tar.gz" \
      "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_${gl_arch}.tar.gz" /tmp/gitleaks.tar.gz; \
    tar -xzf /tmp/gitleaks.tar.gz -C /tmp gitleaks; \
    install -m 0755 /tmp/gitleaks /usr/local/bin/gitleaks; \
    fetch "yq/${YQ_VERSION}/yq_linux_${go_arch}" \
      "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${go_arch}" /tmp/yq; \
    install -m 0755 /tmp/yq /usr/local/bin/yq; \
    fetch "bun/${BUN_VERSION}/bun-linux-${bun_arch}.zip" \
      "https://github.com/oven-sh/bun/releases/download/bun-v${BUN_VERSION}/bun-linux-${bun_arch}.zip" /tmp/bun.zip; \
    unzip -q /tmp/bun.zip -d /tmp; \
    install -m 0755 "/tmp/bun-linux-${bun_arch}/bun" /usr/local/bin/bun; \
    bun add -g "@commitlint/cli@${COMMITLINT_VERSION}" "@commitlint/config-conventional@${COMMITLINT_VERSION}"; \
    printf '#!/bin/sh\nexec bun "%s" "$@"\n' "$(readlink -f /usr/local/bin/commitlint)" > /tmp/commitlint.sh; \
    install -m 0755 /tmp/commitlint.sh /usr/local/bin/commitlint; \
    rm -rf /tmp/*

USER vscode
