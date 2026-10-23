resource "tailscale_acl" "tailnet" {
  acl = jsonencode({
    tagOwners = {
      "tag:k8s" = ["autogroup:admin"]
    }

    grants = [
      {
        src = ["*"]
        dst = ["*"]
        ip  = ["*"]
      },
    ]

    ssh = [
      {
        action = "check"
        src    = ["autogroup:member"]
        dst    = ["autogroup:self"]
        users  = ["autogroup:nonroot", "root"]
      },
    ]

    nodeAttrs = [
      {
        target = ["autogroup:member", "tag:k8s"]
        attr   = ["funnel"]
      },
    ]

    autoApprovers = {
      services = {
        "tag:k8s" = ["tag:k8s"]
      }
    }
  })
}
