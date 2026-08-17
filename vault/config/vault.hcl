ui = true
disable_mlock = true

storage "raft" {
  path = "/vault/data"
  node_id = "vault-1"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = "true"
}

cluster_addr = "http://vault:8201"
