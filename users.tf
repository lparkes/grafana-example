variable "saml_metadata_url" {
  default     = ""
  type        = string
  description = "The URL of the federation metadata. Use an empty string to skip configuration of an identity provider"
}

locals {
  not_for_saml  = var.saml_metadata_url == "" ? 1 : 0
  only_for_saml = var.saml_metadata_url == "" ? 0 : 1
}

resource "aws_cognito_user_pool" "pool" {
  name = "grafana-example"

  password_policy {
    require_symbols = false
    minimum_length                   = 8
    temporary_password_validity_days = 7
  }
}


resource "aws_cognito_user_pool_client" "grafana" {
  name            = "grafana"
  user_pool_id    = aws_cognito_user_pool.pool.id
  generate_secret = true
  callback_urls   = [ "https://${local.domain_name}/login/generic_oauth" ]

  allowed_oauth_flows                  = [
          "code",
          "implicit",
        ]

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = [
          "email",
          "openid",
          "profile",
        ]
  explicit_auth_flows                  = [
          "ALLOW_CUSTOM_AUTH",
          "ALLOW_REFRESH_TOKEN_AUTH",
          "ALLOW_USER_SRP_AUTH",
        ]
  supported_identity_providers         = [ "COGNITO" ]
}

resource "aws_cognito_user_pool_domain" "main" {
  count        = local.not_for_saml
  
  domain       = "grafana-demo"
  user_pool_id = aws_cognito_user_pool.pool.id
}
