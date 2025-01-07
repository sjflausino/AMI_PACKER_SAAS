source "amazon-ebs" "devportal-admin-ui" {
  ami_name      = "${var.ami_prefix}-${local.timestamp}-arm64"
  instance_type = "t4g.medium"
  region        = "${var.aws_region}"
  ssh_username  = "ec2-user"

  source_ami_filter {
    filters = {
      name                = "al2023-ami-*-arm64"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["amazon"]
  }

  tags = {
    Name    = "${var.ami_prefix}-${local.timestamp}-arm64"
    Project = "devportal-admin-ui"
    Owner   = "Veecode Platform"
    Temporary = "true"
  }

  launch_block_device_mappings {
    device_name           = "/dev/xvda"
    volume_size           = 30
    volume_type           = "gp3"
    delete_on_termination = true
  }

}
