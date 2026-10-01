resource "forgejo_branch_protection" "main" {
  branch_name   = "main"
  repository_id = forgejo_repository.homelab.id

  enable_push = false

  enable_status_check = true
  status_check_contexts = [
    "meta / commitlint (pull_request)",
    "security / gitleaks (pull_request)",
  ]

  required_approvals = 0

  block_on_rejected_reviews         = false
  block_on_official_review_requests = false
  block_on_outdated_branch          = false
  dismiss_stale_approvals           = false
  require_signed_commits            = false

  protected_file_patterns   = ""
  unprotected_file_patterns = ""
}
