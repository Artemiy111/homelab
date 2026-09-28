import {
  to = forgejo_repository.homelab
  id = "artemiy/homelab"
}

import {
  to = forgejo_branch_protection.main
  id = "artemiy/homelab/main"
}

import {
  to = forgejo_repository.mirror["checkout"]
  id = "actions/checkout"
}
