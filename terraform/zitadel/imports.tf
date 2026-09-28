import {
  to = zitadel_organization.homelab
  id = "387300886247899139"
}

import {
  to = zitadel_organization_domain.homelab
  id = "387300886247899139:homelab.id.${var.domain}"
}

import {
  to = zitadel_project_v2.homelab
  id = "387300960000540675:387300886247899139"
}

import {
  to = zitadel_project_role.admin
  id = "387300960000540675:admin:387300886247899139"
}

import {
  to = zitadel_project_role.wtf
  id = "387300960000540675:wtf:387300886247899139"
}

import {
  to = zitadel_application_v2.oauth2_proxy
  id = "387301374079008771:387300886247899139"
}

import {
  to = zitadel_application_v2.beszel
  id = "387310556282880003:387300886247899139"
}

import {
  to = zitadel_application_v2.glitchtip
  id = "387557386778312725:387300886247899139"
}

import {
  to = zitadel_application_v2.home_assistant
  id = "387696576803373077:387300886247899139"
}

import {
  to = zitadel_application_v2.seafile
  id = "388456383227363356:387300886247899139"
}

import {
  to = zitadel_application_v2.immich
  id = "388541482971168796:387300886247899139"
}

import {
  to = zitadel_application_v2.zot
  id = "391766932895853502:387300886247899139"
}

import {
  to = zitadel_application_v2.test
  id = "388533596891119644:387300886247899139"
}

import {
  to = zitadel_instance_member.instance_admin
  id = "387300440830181379"
}

import {
  to = zitadel_org_member.instance_admin
  id = "387300440830181379:387300886247899139"
}

import {
  to = zitadel_org_member.homelab_admin
  id = "387308085636497411:387300886247899139"
}

import {
  to = zitadel_org_member.homelab_service
  id = "387704510765596693:387300886247899139"
}

import {
  to = zitadel_user_grant.homelab_admin
  id = "388535640574132252:387308085636497411:387300886247899139"
}

import {
  to = zitadel_user_grant.test
  id = "388550580399767555:388550157697810435:387300886247899139"
}

import {
  to = zitadel_login_policy.homelab
  id = "387300886247899139"
}
