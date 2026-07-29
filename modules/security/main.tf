# =============================================================================
# MODULE: security  |  Who can talk to whom, and who can do what
# =============================================================================
# TWO KINDS OF CONTROL LIVE HERE - do not confuse them (interviewers test this):
#   1. SECURITY GROUPS = network firewall. Control which TRAFFIC can flow
#      (protocol + port + source). Stateful: if you allow inbound, the reply
#      is automatically allowed out.
#   2. IAM ROLES/POLICIES = identity permissions. Control which AWS API ACTIONS
#      an identity may call. Nothing to do with network traffic.
#   A packet must pass the security group; an API call must pass IAM. Different
#   planes, both enforced.
#
# THE SG-TO-SG PATTERN (the heart of micro-segmentation)
#   The database SG allows port 3306 FROM THE APP SECURITY GROUP, referenced by
#   its ID - not from an IP range (CIDR). Why this matters: membership, not
#   location, grants access. A compromised host elsewhere in the VPC, even in
#   the same subnet with an allowed IP, is NOT in the app SG, so it cannot open
#   a connection. This is how you stop lateral movement after a breach.
#   Weaker alternative (do not use): cidr_blocks = ["10.0.0.0/16"] would let
#   ANY host in the VPC reach the DB - convenient, and exactly the flat-network
#   mistake zero trust exists to prevent.
#
# THE ZERO-INBOUND INSTANCE
#   The app SG has NO ingress rules at all. The instance is administered through
#   SSM over OUTBOUND https, so nothing ever needs to connect inward. An
#   instance you cannot connect TO is an instance an attacker cannot connect to.
#
# LEAST-PRIVILEGE IAM
#   The instance role carries exactly ONE managed policy:
#   AmazonSSMManagedInstanceCore. Not AdministratorAccess, not PowerUser - the
#   minimum that lets SSM function. If this instance is ever compromised, the
#   stolen credentials can do almost nothing.
#   Alternative for stricter shops: write a customer-managed policy listing only
#   the exact SSM actions, tighter than the AWS-managed one. Named in Recommendations.
# =============================================================================

# Zero-trust security groups and IAM.
# Design rules enforced here:
#   1. The app instance has NO inbound rules at all. SSM works entirely
#      over outbound HTTPS, so nothing ever connects "in" to the instance.
#   2. The database accepts MySQL only from the app security group,
#      referenced by SG id, never by CIDR.
#   3. The instance role carries exactly one managed policy:
#      AmazonSSMManagedInstanceCore. No SSH key pair exists anywhere.

resource "aws_security_group" "app" {
  name        = "${var.project}-app-sg"
  description = "App tier - no inbound, outbound HTTPS + MySQL only"
  vpc_id      = var.vpc_id

  egress {
    description = "HTTPS to VPC endpoints for SSM"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "MySQL to the database tier"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = { Name = "${var.project}-app-sg" }
}

resource "aws_iam_role_policy" "session_logging" {
  name = "${var.project}-session-logging"
  role = aws_iam_role.app_instance.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:DescribeLogGroups"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
        Resource = "arn:aws:logs:*:*:log-group:/${var.project}/ssm-sessions:*"
      }
    ]
  })
}

resource "aws_security_group" "db" {
  name        = "${var.project}-db-sg"
  description = "DB tier - MySQL from app SG only, no egress needed"
  vpc_id      = var.vpc_id

  ingress {
    description     = "MySQL from app tier only (SG reference, no CIDR)"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  ingress {
    description     = "MySQL from RDS Proxy tier only (SG reference)"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.proxy.id]
  }

  tags = { Name = "${var.project}-db-sg" }
}

resource "aws_security_group" "vpce" {
  name        = "${var.project}-vpce-sg"
  description = "Allow HTTPS from inside the VPC to SSM endpoints"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = { Name = "${var.project}-vpce-sg" }
}

# ----- IAM: least privilege for the app instance -----
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app_instance" {
  name               = "${var.project}-app-instance-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.app_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.project}-app-profile"
  role = aws_iam_role.app_instance.name
}

# DEFECT FIX (final review): the proxy previously reused the app SG, which has
# ZERO ingress rules - so the app could never connect to the proxy on 3306, and
# the PEP demonstration would have failed. Security groups do not permit
# intra-group traffic unless a self-referencing rule exists. The proxy gets its
# own SG: one door in (app tier), two doors out (DB, and Secrets Manager via
# the interface endpoint).
resource "aws_security_group" "proxy" {
  name        = "${var.project}-proxy-sg"
  description = "RDS Proxy PEP - MySQL from app SG in, MySQL to DB + HTTPS to Secrets Manager out"
  vpc_id      = var.vpc_id

  ingress {
    description     = "MySQL from app tier only (SG reference)"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    description = "MySQL to the database tier"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "HTTPS to the Secrets Manager interface endpoint"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = { Name = "${var.project}-proxy-sg" }
}
