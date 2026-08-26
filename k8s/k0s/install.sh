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

# --- Install k0s binary ---
if command -v k0s &>/dev/null; then
  echo "k0s already installed: $(k0s version)"
  echo "To upgrade, run: k0s stop && curl -sSLf https://get.k0s.sh | sudo sh && k0s start"
else
  echo "Installing k0s..."
  curl --proto '=https' --tlsv1.2 -sSf https://get.k0s.sh | sh
  echo "k0s installed: $(k0s version)"
fi

# --- Configure firewalld ---
echo ""
echo "Configuring firewalld..."

# Check backend compatibility
K0S_IPTABLES=$(ls -la /var/lib/k0s/bin/iptables 2>/dev/null | grep -o 'nftables\|iptables' || echo "unknown")
FW_BACKEND=$(grep FirewallBackend /etc/firewalld/firewalld.conf 2>/dev/null | awk '{print $3}' || echo "unknown")

if [[ "$K0S_IPTABLES" != "unknown" && "$FW_BACKEND" != "unknown" && "$K0S_IPTABLES" != "$FW_BACKEND" ]]; then
  echo "WARNING: k0s uses $K0S_IPTABLES but firewalld uses $FW_BACKEND"
  echo "This may cause networking issues. Consider updating /etc/firewalld/firewalld.conf"
fi

# Install service definitions
cp "${SCRIPT_DIR}/firewalld/k0s-controller.xml" /etc/firewalld/services/
cp "${SCRIPT_DIR}/firewalld/k0s-worker.xml" /etc/firewalld/services/

# Apply rules (controller+worker on single node)
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

  # Wait for k0s to create its directories
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

KUBECONFIG_PATH="/root/.kube/config"
mkdir -p "$(dirname "$KUBECONFIG_PATH")"
k0s kubeconfig create > "$KUBECONFIG_PATH"
chmod 600 "$KUBECONFIG_PATH"

echo "kubectl configured: $KUBECONFIG_PATH"

# --- Verify ---
echo ""
echo "=== Verification ==="
k0s status
echo ""
kubectl get nodes
echo ""
kubectl get pods -A
echo ""
echo "=== Done ==="
echo "Next: install Calico, MetalLB, ingress-nginx (see README.md)"
