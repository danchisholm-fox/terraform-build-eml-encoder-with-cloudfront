resource "aws_ssm_parameter" "url_pull_password" {
  name  = "/medialive/url-pull/password"
  type  = "String"
  value = "unused"
  tier  = "Standard"
}

