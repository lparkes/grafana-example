
provider "grafana" {
  url  = var.grafana_url
  auth = var.grafana_auth
}

variable "grafana_url" {
  type        = string
  description = "The root URL of the Grafana server"
}

variable "grafana_auth" {
  type        = string
  description = "The username and password in a single string and separated by a colon"
}

resource "grafana_data_source" "ebs-metrics" {
  type       = "cloudwatch"
  name       = "cloudwatch"
  is_default = true

  json_data {
    default_region = "ap-southeast-2"
    auth_type      = "credentials"
  }
}

resource "grafana_dashboard" "ebs-metrics" {
  config_json = file("ebs-dashboard.json")
  depends_on  = [ grafana_data_source.ebs-metrics ]
}
