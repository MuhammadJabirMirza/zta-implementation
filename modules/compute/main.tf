# =============================================================================
# MODULE: compute  |  The app-tier client - and a lesson in what to LEAVE OUT
# =============================================================================
# This instance is defined as much by what is ABSENT as what is present:
#   - NO key_name        -> no SSH key pair exists, so SSH is impossible.
#   - NO public IP        -> associate_public_ip_address = false.
#   - NO inbound SG rules  -> nothing can connect to it.
#   Access is exclusively SSM Session Manager. The most secure server is one
#   with no doors; you reach it only by having it phone home to AWS for you.
#
# TWO HARDENING CONTROLS WORTH EXPLAINING:
#   - metadata_options http_tokens = required -> forces IMDSv2. IMDSv1 was the
#     vector in the 2019 Capital One breach (SSRF read the instance metadata and
#     stole credentials). IMDSv2 requires a session token, defeating that class
#     of attack. Interviewers LOVE this one - know the story.
#   - root_block_device encrypted = true -> the boot volume is encrypted too,
#     not just the database.
#
# ALTERNATIVES:
#   - Fargate/containers instead of EC2: no instance to patch at all. The modern
#     direction; EC2 chosen here because the migration needs a shell with mysql
#     client tools. Name Fargate in Recommendations.
# =============================================================================

# Minimal app-tier client. Note what is ABSENT:
#   - no key_name (no SSH key pair exists)
#   - no public IP (private subnet, no internet route)
#   - no inbound security group rules
# Access is exclusively via SSM Session Manager.

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-x86_64"]
  }
}

resource "aws_instance" "app" {
  #checkov:skip=CKV_AWS_126:Detailed monitoring omitted for cost on a short-lived demo instance
  #checkov:skip=CKV_AWS_135:EBS optimisation is not applicable/beneficial on t3.micro
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t3.micro"
  subnet_id                   = var.private_app_subnet_id
  vpc_security_group_ids      = [var.app_sg_id]
  iam_instance_profile        = var.instance_profile_name
  associate_public_ip_address = false

  metadata_options {
    http_tokens = "required" # IMDSv2 only (CIS-aligned)
  }

  root_block_device {
    encrypted = true
  }

  user_data = <<-EOT
    #!/bin/bash
    dnf install -y mariadb105
  EOT

  tags = { Name = "${var.project}-app" }
}
