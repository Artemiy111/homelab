# ZITADEL + HashiCorp Vault + Infisical Integration Research

## 1. Can ZITADEL act as an OIDC provider for Vault's OIDC auth method?

**Yes.** ZITADEL is a certified OIDC provider and can serve as any generic OIDC identity provider for Vault's `jwt`/`oidc` auth method. However, there is **no dedicated ZITADEL guide** in Vault's official documentation.

Vault's OIDC provider list includes ADFS, Auth0, Azure AD, ForgeRock, GitLab, Google, Keycloak, Kubernetes, Okta, SecureAuth, and IBM Verify — but **not ZITADEL**.

- Vault OIDC provider list: https://developer.hashicorp.com/vault/docs/auth/jwt/oidc-providers
- ZITADEL's OIDC discovery endpoint: `https://<your-domain>/.well-known/openid-configuration`

**To configure ZITADEL as Vault's OIDC provider, follow the generic OIDC approach:**

```bash
# 1. Enable OIDC auth method in Vault
vault auth enable oidc

# 2. Configure Vault with ZITADEL's OIDC discovery URL
vault write auth/oidc/config \
    oidc_discovery_url="https://your-zitadel-instance.example.com" \
    oidc_client_id="<ZITADEL_APP_CLIENT_ID>" \
    oidc_client_secret="<ZITADEL_APP_CLIENT_SECRET>" \
    default_role="zitadel"

# 3. Create a Vault role for ZITADEL users
vault write auth/oidc/role/zitadel \
    allowed_redirect_uris="https://vault.example.com/ui/vault/auth/oidc/oidc/callback" \
    allowed_redirect_uris="http://localhost:8250/oidc/callback" \
    user_claim="sub" \
    groups_claim="urn:zitadel:iam:org:project:roles" \
    oidc_scopes="openid,profile,email" \
    token_policies="default" \
    ttl="1h"
```

**Key ZITADEL-side setup (in ZITADEL Console):**
1. Create a Project (e.g., "Vault")
2. Create a Web Application with PKCE or Basic Auth
3. Set Redirect URIs to match Vault's callback URLs
4. Enable "User Info inside ID Token" in Token Settings (so Vault receives claims)

## 2. Are there any documented ZITADEL + Vault integration guides?

**No official step-by-step guide exists** from either ZITADEL or HashiCorp. The closest resources are:

| Resource | URL | Notes |
|----------|-----|-------|
| Vault JWT/OIDC Auth Method Docs | https://developer.hashicorp.com/vault/docs/auth/jwt | Generic OIDC setup, applicable to ZITADEL |
| Vault OIDC Auth Tutorial | https://developer.hashicorp.com/vault/tutorials/auth-methods/oidc-auth | Uses Auth0; same pattern works with ZITADEL |
| HashiCorp Discuss: ZITADEL + HCP SSO | https://discuss.hashicorp.com/t/sso-setup-oidc-with-zitadel-cloud/72366 | User attempted ZITADEL Cloud as OIDC for HCP (not Vault specifically), had issues with generic error |
| ZITADEL OIDC Docs | https://zitadel.com/docs/guides/integrate/login/oidc | ZITADEL as OIDC provider |
| ZITADEL Claims Reference | https://zitadel.com/docs/apis/openidoauth/claims | All claims ZITADEL can emit |
| ZITADEL Partner Page on HashiCorp | https://www.hashicorp.com/en/partners/tech/zitadel | Lists Terraform integration only; no Vault-specific integration |

## 3. Can Vault authenticate users against ZITADEL via OIDC?

**Yes.** Vault's OIDC auth method works with any standards-compliant OIDC provider. The setup flow is:

1. **In ZITADEL Console:** Create Project → Add OIDC Application (Web type) → configure redirect URIs → copy Client ID/Secret
2. **In Vault:** Enable `oidc` auth method → configure with ZITADEL's discovery URL, client ID, and secret → create roles mapping claims to policies

Vault supports both **UI login** (browser redirect to ZITADEL) and **CLI login** (`vault login -method=oidc role=zitadel`).

Vault OIDC auth method docs: https://developer.hashicorp.com/vault/docs/auth/jwt

## 4. What claims/roles does ZITADEL pass to Vault?

ZITADEL emits standard OIDC claims plus custom reserved claims. When configured to include role information:

### Standard OIDC Claims (always available)
| Claim | Example |
|-------|---------|
| `sub` | `77776025198584418` |
| `email` | `user@example.com` |
| `email_verified` | `true` |
| `name` | `Road Runner` |
| `given_name` | `Road` |
| `family_name` | `Runner` |
| `preferred_username` | `road.runner@acme.ch` |
| `aud` | `69234237810729019` |
| `iss` | `https://your-zitadel-instance.example.com` |

### Reserved/ZITADEL-Specific Claims (require specific scopes or settings)
| Claim | Scope Required | Description |
|-------|---------------|-------------|
| `urn:zitadel:iam:org:project:roles` | `openid` + role assertion enabled | **Key claim for Vault role mapping** — contains project roles per user |
| `urn:zitadel:iam:org:project:{projectid}:roles` | scope or assertion | Roles for a specific project |
| `urn:zitadel:iam:org:domain:primary:{domainname}` | profile | Organization domain |
| `urn:zitadel:iam:user:metadata` | profile | User metadata (base64-encoded) |
| `urn:zitadel:iam:user:resourceowner:id` | profile | User's organization ID |
| `urn:zitadel:iam:user:resourceowner:name` | profile | Organization name |

### How to map ZITADEL roles to Vault policies:

ZITADEL's role claim format is a nested JSON object:
```json
{
  "urn:zitadel:iam:org:project:roles": {
    "projectId1": {
      "orgId1": "orgDomain.com"
    }
  }
}
```

For Vault, you can:
- Use `groups_claim` pointing to the ZITADEL role claim
- Use ZITADEL Actions to flatten the role claim into a simple array (recommended for Vault compatibility)
- Use `bound_claims` to restrict access to users with specific ZITADEL roles

**ZITADEL Actions example to flatten roles for Vault:**
```javascript
function flatRoles(ctx, api) {
  if (ctx.v1.user.grants == undefined || ctx.v1.user.grants.count == 0) {
    return;
  }
  let grants = [];
  ctx.v1.user.grants.grants.forEach(claim => {
    claim.roles.forEach(role => {
      grants.push(claim.projectId + ':' + role)
    })
  })
  api.v1.claims.setClaim('zitadel:roles', grants)
}
```
This produces a flat array claim `"zitadel:roles": ["projectId:admin", "projectId:reader"]` that Vault can consume.

### Custom Claims via Actions
ZITADEL Actions (complement token flow) allow you to add any custom claims:
- Static values: `api.v1.claims.setClaim('division', 'engineering')`
- User metadata: `api.v1.user.appendMetadata('add', 'me')`
- Role transformations: flatten ZITADEL's nested role structure

Source: https://zitadel.com/docs/apis/openidoauth/claims

## 5. Blog posts or community guides about ZITADEL + Vault

**Very limited community content exists:**

| Resource | URL | Type |
|----------|-----|------|
| HashiCorp Discuss: SSO with ZITADEL Cloud | https://discuss.hashicorp.com/t/sso-setup-oidc-with-zitadel-cloud/72366 | Forum post (HCP SSO, not Vault-specific, unresolved) |
| ZITADEL as Grafana OIDC Provider | https://schoenwald.aero/posts/2025-02-12_integrating_zitadel_as_an_oidc_provider_in_grafana | Blog (Grafana, not Vault, but shows ZITADEL OIDC pattern) |
| ZITADEL + Psono OIDC Guide | https://doc.psono.com/admin/configuration/oidc-zitadel.html | Docs (shows ZITADEL as IdP pattern) |
| Dashy + ZITADEL OIDC | https://dashy.to/docs/authentication/zitadel | Docs (includes Actions for role mapping — useful pattern for Vault) |

**No dedicated blog post or tutorial exists for ZITADEL + Vault specifically.**

## 6. ZITADEL + Infisical Integration

**Yes, this works via Infisical's "General OIDC" SSO configuration.** There is no ZITADEL-specific guide, but the generic OIDC flow applies.

### Setup Steps

**In ZITADEL Console:**
1. Create a Project (e.g., "Infisical")
2. Add an OIDC Application:
   - Type: **Web**
   - Auth method: **Basic** (client_secret_post or client_secret_basic)
   - Redirect URI: `https://app.infisical.com/api/v1/sso/oidc/callback` (Cloud US)
     - EU: `https://eu.infisical.com/api/v1/sso/oidc/callback`
     - Self-hosted: `https://your-infisical-domain/api/v1/sso/oidc/callback`
   - Post Logout URI: `https://app.infisical.com` (or your domain)
3. In Token Settings, enable **"User Info inside ID Token"**
4. Copy Client ID and Client Secret

**In Infisical Console:**
1. Go to **Organization Settings → SSO & Provisioning → SSO** tab
2. Click **Add Provider → OIDC**
3. Fill in:
   - **Discovery Document URL**: `https://your-zitadel-instance.example.com/.well-known/openid-configuration`
   - **Client ID**: from ZITADEL
   - **Client Secret**: from ZITADEL
   - **JWT Signature Algorithm**: RS256 (default for ZITADEL)
4. Click **Configure OIDC**
5. Enable OIDC SSO
6. Test login (user must have `email` and `given_name` claims)

### Prerequisites for Infisical
- Infisical Cloud (Pro Tier) or self-hosted with license
- Email domain verification in Infisical
- Self-hosted requires `AUTH_SECRET` and `SITE_URL` env vars

### Key Requirements
- ZITADEL must emit `email` and `given_name` in the ID token (ensure "User Info inside ID Token" is enabled)
- Scopes needed: `openid`, `profile`, `email`
- Supported JWT algorithms: RS256, RS512, HS256, EdDSA (ZITADEL uses RS256 by default)

### Documentation URLs
| Resource | URL |
|----------|-----|
| Infisical General OIDC SSO | https://infisical.com/docs/documentation/platform/sso/general-oidc/overview |
| Infisical SSO Overview | https://infisical.com/docs/documentation/platform/sso/overview |
| Infisical Email Domain Verification | https://infisical.com/docs/documentation/platform/email-domain |
| ZITADEL OIDC Endpoints | https://zitadel.com/docs/apis/openidoauth/endpoints |
| Infisical Self-Hosted Config | https://infisical.com/docs/self-hosting/configuration/envars |

## Summary

| Integration | Works? | Official Guide? | Notes |
|-------------|--------|-----------------|-------|
| ZITADEL → Vault OIDC Auth | ✅ Yes | ❌ No | Use generic OIDC config; no ZITADEL-specific provider page in Vault docs |
| ZITADEL → Infisical SSO | ✅ Yes | ❌ No | Use Infisical's "General OIDC" provider; standard OIDC flow |
| Vault → ZITADEL claims mapping | ✅ Yes | ⚠️ Partial | ZITADEL Actions needed to flatten nested role claims for Vault |

### Recommended Approach for Both Integrations
Since neither HashiCorp nor Infisical has ZITADEL-specific guides, the integration pattern is:
1. Configure ZITADEL as a standard OIDC provider (create Project + App)
2. Use the ZITADEL OIDC discovery URL (`/.well-known/openid-configuration`) in the consuming application
3. Enable "User Info inside ID Token" in ZITADEL app token settings
4. Use ZITADEL Actions to customize claims (especially role mapping) to match the consuming application's expectations
