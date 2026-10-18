resource "zitadel_login_policy" "homelab" {
  org_id = zitadel_organization.homelab.id

  allow_register                = true
  allow_external_idp            = true
  user_login                    = true
  force_mfa                     = false
  force_mfa_local_only          = false
  hide_password_reset           = false
  ignore_unknown_usernames      = false
  allow_domain_discovery        = true
  disable_login_with_email      = false
  disable_login_with_phone      = true
  default_redirect_uri          = ""
  passwordless_type             = "PASSWORDLESS_TYPE_ALLOWED"
  second_factors                = ["SECOND_FACTOR_TYPE_OTP", "SECOND_FACTOR_TYPE_U2F"]
  multi_factors                 = ["MULTI_FACTOR_TYPE_U2F_WITH_VERIFICATION"]
  password_check_lifetime       = "240h0m0s"
  external_login_check_lifetime = "240h0m0s"
  mfa_init_skip_lifetime        = "720h0m0s"
  second_factor_check_lifetime  = "18h0m0s"
  multi_factor_check_lifetime   = "12h0m0s"

  lifecycle {
    prevent_destroy = true
  }
}
