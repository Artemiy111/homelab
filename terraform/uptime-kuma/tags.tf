resource "uptimekuma_tag" "group" {
  for_each = { for group in local.groups : group.key => group }

  name  = each.value.title
  color = each.value.color
}
