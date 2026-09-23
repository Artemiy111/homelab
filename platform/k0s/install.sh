#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== k0s Installation Script ==="
echo "Config: ${SCRIPT_DIR}/k0s.yaml"
echo ""

# --- Check prerequisites ---
if [[ $EUID -ne 0 ]]; then
  echo "Error: run as root (sudo)" >&2
  exit 1
fi

if ! command -v firewall-cmd &>/dev/null; then
  echo "Error: firewalld not found" >&2
  exit 1
fi

# --- DNS prerequisite check ---
# containerd должен резолвить registry (quay.io, registry.k8s.io) ДО старта k0s,
# иначе image pull падает с "lookup quay.io: Try again".
echo "Checking DNS resolution for container registries..."
if ! getent hosts quay.io >/dev/null 2>&1; then
  echo "WARNING: quay.io не резолвится прямо сейчас."
  echo "  DNS-цепочка сервера: systemd-resolved -> <router-ip> (роутер) -> Technitium (Docker)."
  echo "  Если Docker/Technitium остановлен, временно пропиши на роутере 1.1.1.1,"
  echo "  либо подними Technitium перед установкой k0s."
  echo "  Продолжаем, но образы Calico могут не скачаться."
else
  echo "DNS OK."
fi

# --- Docker coexistence check ---
# k0s и Docker оба пишут в nftables. Если Docker уже запущен, его правила (сотни
# строк) могут сломать сеть k0s. Рекомендуемый порядок: сначала k0s, потом Docker.
if systemctl is-active --quiet docker 2>/dev/null; then
  echo "WARNING: Docker уже запущен. k0s и Docker конфликтуют по nftables."
  echo "  Рекомендуется: sudo systemctl stop docker docker.socket containerd"
  echo "  затем дождаться поднятия k0s, и только потом запускать Docker."
  read -r -p "Продолжить установку k0s поверх работающего Docker? [y/N] " reply
  if [[ "${reply,,}" != "y" ]]; then
    echo "Aborted."
    exit 1
  fi
fi

# --- Install k0s binary ---
if command -v k0s &>/dev/null; then
  echo "k0s already installed: $(k0s version)"
else
  echo "Installing k0s..."
  curl --proto '=https' --tlsv1.2 -sSf https://get.k0s.sh | sh
  echo "k0s installed: $(k0s version)"
fi

# --- Configure firewalld ---
echo ""
echo "Configuring firewalld..."

# Проверка совместимости бэкендов (k0s -> nftables, firewalld -> nftables на Fedora).
# k0s линкует /var/lib/k0s/bin/iptables на xtables-{nft,legacy}-multi — бэкенд
# определяем по цели симлинка и приводим к словарю firewalld.
case "$(readlink -f /var/lib/k0s/bin/iptables 2>/dev/null)" in
  *-nft-multi) K0S_IPTABLES=nftables ;;
  *-legacy-multi) K0S_IPTABLES=iptables ;;
  *) K0S_IPTABLES=unknown ;;
esac
FW_BACKEND=$(grep FirewallBackend /etc/firewalld/firewalld.conf 2>/dev/null | awk '{print $3}' || echo "unknown")

if [[ "$K0S_IPTABLES" != "unknown" && "$FW_BACKEND" != "unknown" && "$K0S_IPTABLES" != "$FW_BACKEND" ]]; then
  echo "WARNING: k0s uses $K0S_IPTABLES but firewalld uses $FW_BACKEND"
  echo "This may cause networking issues. Consider updating /etc/firewalld/firewalld.conf"
fi

cp "${SCRIPT_DIR}/firewalld/k0s-controller.xml" /etc/firewalld/services/
cp "${SCRIPT_DIR}/firewalld/k0s-worker.xml" /etc/firewalld/services/

firewall-cmd --permanent --add-service=k0s-controller
firewall-cmd --permanent --add-service=k0s-worker
firewall-cmd --permanent --add-masquerade
firewall-cmd --permanent --add-source=10.244.0.0/16   # podCIDR
firewall-cmd --permanent --add-source=10.96.0.0/12    # serviceCIDR
firewall-cmd --reload

echo "Firewalld configured."

# --- Configure SELinux ---
echo ""
echo "Configuring SELinux..."

if command -v getenforce &>/dev/null && [[ "$(getenforce)" == "Enforcing" ]]; then
  dnf install -y container-selinux policycoreutils-python-utils

  DATA_DIR="/var/lib/k0s"

  if [[ -d "$DATA_DIR" ]]; then
    semanage fcontext -a -t container_runtime_exec_t "${DATA_DIR}/bin/containerd.*" 2>/dev/null || true
    semanage fcontext -a -t container_runtime_exec_t "${DATA_DIR}/bin/runc" 2>/dev/null || true
    restorecon -R -v "${DATA_DIR}/bin" 2>/dev/null || true

    semanage fcontext -a -t container_var_lib_t "${DATA_DIR}/containerd(/.*)?" 2>/dev/null || true
    restorecon -R -v "${DATA_DIR}/containerd" 2>/dev/null || true
  fi

  mkdir -p /etc/k0s/containerd.d
  cp "${SCRIPT_DIR}/selinux/containerd-selinux.toml" /etc/k0s/containerd.d/

  echo "SELinux configured."
else
  echo "SELinux not enforcing, skipping."
fi

# --- Install k0s ---
echo ""
echo "Installing k0s..."

mkdir -p /etc/k0s
cp "${SCRIPT_DIR}/k0s.yaml" /etc/k0s/k0s.yaml

if k0s status 2>/dev/null | grep -q "Version"; then
  echo "k0s already installed. To reinstall: k0s reset && reboot"
else
  k0s install controller \
    -c /etc/k0s/k0s.yaml \
    --enable-worker \
    --no-taints
  k0s start
  echo "k0s installed and started."
fi

# --- Setup kubectl ---
echo ""
echo "Setting up kubectl..."

# root kubeconfig
ROOT_KUBECONFIG="/root/.kube/config"
mkdir -p "$(dirname "$ROOT_KUBECONFIG")"
k0s kubeconfig admin create > "$ROOT_KUBECONFIG"
chmod 600 "$ROOT_KUBECONFIG"
echo "kubectl configured for root: $ROOT_KUBECONFIG"

# kubeconfig для пользователя, вызвавшего sudo (если есть)
if [[ -n "${SUDO_USER:-}" ]]; then
  USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
  USER_KUBECONFIG="${USER_HOME}/.kube/config"
  mkdir -p "$(dirname "$USER_KUBECONFIG")"
  k0s kubeconfig admin create > "$USER_KUBECONFIG"
  chown "$SUDO_USER":"$(id -gn "$SUDO_USER")" "$USER_KUBECONFIG"
  chmod 600 "$USER_KUBECONFIG"
  echo "kubectl configured for ${SUDO_USER}: $USER_KUBECONFIG"

  # алиас kubectl -> k0s kubectl (нативный kubectl от k0s не умеет __complete,
  # поэтому делаем алиас + KUBECONFIG вместо отдельного wrapper-файла)
  ZSHRC="${USER_HOME}/.zshrc"
  if [[ -f "$ZSHRC" ]] && ! grep -q "alias kubectl='k0s kubectl'" "$ZSHRC"; then
    {
      echo ""
      echo "# k0s kubectl alias (KUBECONFIG берётся из окружения)"
      echo "export KUBECONFIG=${USER_KUBECONFIG}"
      echo "alias kubectl='k0s kubectl'"
      echo "alias k='kubectl'"
    } >> "$ZSHRC"
    chown "$SUDO_USER":"$(id -gn "$SUDO_USER")" "$ZSHRC"
    echo "Added kubectl alias to ${ZSHRC}"
  fi
fi

# --- Verify ---
echo ""
echo "=== Verification ==="
k0s status
echo ""
export KUBECONFIG="$ROOT_KUBECONFIG"
kubectl get nodes
echo ""
kubectl get pods -A
echo ""
echo "=== Done ==="
echo "Calico уже работает (задан в k0s.yaml)."
echo "Если pod'ы висят в ImagePullBackOff — проверь DNS (см. README.md)."
echo "Docker можно запускать ПОСЛЕ того, как k0s поднялся."
