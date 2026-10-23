#!/usr/bin/env python3
import json
import subprocess
from pathlib import Path

cluster = Path(__file__).resolve().parent.parent / "terraform" / "cluster"

nodes = json.loads(
    subprocess.check_output(
        ["terraform", f"-chdir={cluster}", "output", "-json", "nodes"], text=True
    )
)

hosts = "\n".join(
    f"    yc-{key}:\n"
    f"      ansible_host: {node['public_ip']}\n"
    f"      ip: {node['internal_ip']}\n"
    f"      access_ip: {node['internal_ip']}"
    for key, node in nodes.items()
)
members = "\n".join(f"        yc-{key}:" for key in nodes)

print(f"""---
all:
  hosts:
{hosts}
  children:
    kube_control_plane:
      hosts:
{members}
    kube_node:
      hosts:
{members}
    etcd:
      hosts:
{members}
    k8s_cluster:
      children:
        kube_control_plane:
        kube_node:
    calico_rr:
      hosts: {{}}
""")
