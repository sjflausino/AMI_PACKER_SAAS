build {
  name    = "ami-packer"
  sources = ["source.amazon-ebs.devportal-admin-ui"]

  provisioner "shell" {
    environment_vars = [
      "DEVPORTAL_CHART_VERSION=${var.devportal_chart_version}",
      "ADMIN_UI_CHART_VERSION=${var.admin_ui_chart_version}",
    ]
    script       = "./script-install.sh"
    pause_before = "10s"
    timeout      = "10s"
  }
}