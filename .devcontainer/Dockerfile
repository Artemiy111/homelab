FROM ubuntu:26.04

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
ARG TERRAFORM_VERSION=1.16.4
ARG ANSIBLE_CORE_VERSION=2.20.10
ARG ANSIBLE_LINT_VERSION=26.8.0
ARG COMMUNITY_GENERAL_VERSION=12.6.2
ARG ANSIBLE_POSIX_VERSION=2.2.0

ENV BUN_INSTALL=/usr/local
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl git jq kustomize python3-venv shellcheck sudo unzip zsh \
 && rm -rf /var/lib/apt/lists/*

RUN usermod --login vscode --home /home/vscode --move-home ubuntu \
 && groupmod --new-name vscode ubuntu \
 && printf 'vscode ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/vscode \
 && chmod 0440 /etc/sudoers.d/vscode

COPY tools.tsv /tmp/tools.tsv
COPY --chmod=0755 install-tool.sh /tmp/install-tool.sh

RUN arch="$(dpkg --print-architecture)"; \
    /tmp/install-tool.sh "kubectl/${KUBECTL_VERSION}/kubectl-linux-${arch}" \
      "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/${arch}/kubectl" \
      /usr/local/bin/kubectl

RUN arch="$(dpkg --print-architecture)"; \
    /tmp/install-tool.sh "helm/${HELM_VERSION}/helm-${HELM_VERSION}-linux-${arch}.tar.gz" \
      "https://get.helm.sh/helm-v${HELM_VERSION}-linux-${arch}.tar.gz" \
      /usr/local/bin/helm "linux-${arch}/helm"

RUN arch="$(dpkg --print-architecture)"; \
    /tmp/install-tool.sh "kubeconform/${KUBECONFORM_VERSION}/kubeconform-linux-${arch}.tar.gz" \
      "https://github.com/yannh/kubeconform/releases/download/v${KUBECONFORM_VERSION}/kubeconform-linux-${arch}.tar.gz" \
      /usr/local/bin/kubeconform kubeconform

RUN case "$(dpkg --print-architecture)" in \
      amd64) asset="kube-linter-linux.tar.gz" ;; \
      arm64) asset="kube-linter-linux_arm64.tar.gz" ;; \
      *) echo "неподдерживаемая архитектура" >&2; exit 1 ;; \
    esac; \
    /tmp/install-tool.sh "kube-linter/${KUBE_LINTER_VERSION}/${asset}" \
      "https://github.com/stackrox/kube-linter/releases/download/v${KUBE_LINTER_VERSION}/${asset}" \
      /usr/local/bin/kube-linter kube-linter

RUN arch="$(dpkg --print-architecture)"; \
    /tmp/install-tool.sh "actionlint/${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_${arch}.tar.gz" \
      "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_${arch}.tar.gz" \
      /usr/local/bin/actionlint actionlint

RUN case "$(dpkg --print-architecture)" in \
      amd64) arch="x64" ;; \
      arm64) arch="arm64" ;; \
      *) echo "неподдерживаемая архитектура" >&2; exit 1 ;; \
    esac; \
    /tmp/install-tool.sh "gitleaks/${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_${arch}.tar.gz" \
      "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_${arch}.tar.gz" \
      /usr/local/bin/gitleaks gitleaks

RUN arch="$(dpkg --print-architecture)"; \
    /tmp/install-tool.sh "yq/${YQ_VERSION}/yq_linux_${arch}" \
      "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${arch}" \
      /usr/local/bin/yq

RUN case "$(dpkg --print-architecture)" in \
      amd64) arch="x64" ;; \
      arm64) arch="aarch64" ;; \
      *) echo "неподдерживаемая архитектура" >&2; exit 1 ;; \
    esac; \
    /tmp/install-tool.sh "bun/${BUN_VERSION}/bun-linux-${arch}.zip" \
      "https://github.com/oven-sh/bun/releases/download/bun-v${BUN_VERSION}/bun-linux-${arch}.zip" \
      /usr/local/bin/bun "bun-linux-${arch}/bun"

RUN bun add -g "@commitlint/cli@${COMMITLINT_VERSION}" "@commitlint/config-conventional@${COMMITLINT_VERSION}" \
 && printf '#!/bin/sh\nexec bun "%s" "$@"\n' "$(readlink -f /usr/local/bin/commitlint)" > /tmp/commitlint.sh \
 && install -m 0755 /tmp/commitlint.sh /usr/local/bin/commitlint

RUN arch="$(dpkg --print-architecture)"; \
    /tmp/install-tool.sh "terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${arch}.zip" \
      "https://hashicorp-releases.yandexcloud.net/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${arch}.zip" \
      /usr/local/bin/terraform terraform

RUN python3 -m venv /opt/ansible \
 && /opt/ansible/bin/pip install --quiet --no-cache-dir \
      "ansible-core==${ANSIBLE_CORE_VERSION}" "ansible-lint==${ANSIBLE_LINT_VERSION}" \
 && /opt/ansible/bin/ansible-galaxy collection install \
      --collections-path /usr/share/ansible/collections \
      "community.general:${COMMUNITY_GENERAL_VERSION}" "ansible.posix:${ANSIBLE_POSIX_VERSION}" \
 && for binary in ansible ansible-playbook ansible-galaxy ansible-vault ansible-doc ansible-config ansible-inventory ansible-console ansible-lint; do \
      ln -sf "/opt/ansible/bin/${binary}" "/usr/local/bin/${binary}"; \
    done \
 && rm -rf /root/.ansible

RUN rm -f /tmp/tools.tsv /tmp/install-tool.sh /tmp/commitlint.sh

USER vscode
