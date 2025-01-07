variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "ami_prefix" {
  type    = string
  default = "veecode-saas-devportal"
}

variable "devportal_chart_version" {
  type    = string
  default = "0.18.4"
}

variable "admin_ui_chart_version" {
  type    = string
  default = "0.5.0"
}
