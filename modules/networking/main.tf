# =============================================================================
# MODULE: networking  |  The foundation every other module sits on
# =============================================================================
# WHAT THIS IS
#   A three-tier Virtual Private Cloud (VPC): your own isolated slice of the
#   AWS network. Think of the VPC as a private building, subnets as floors,
#   and route tables as the rules for which floors have a door to the street.
#
# WHY IT IS DESIGNED THIS WAY (the zero-trust core)
#   - Public subnets HAVE a route to the internet gateway (a door to the street).
#   - Private subnets DO NOT. The absence of a 0.0.0.0/0 route is the single
#     most important security decision in this whole project: a database in a
#     subnet with no street door cannot be reached from the internet, and
#     cannot reach out to it, no matter what else is misconfigured.
#   - We still create public subnets (with no workloads) to DEMONSTRATE tier
#     separation - a teaching and marking decision, documented as such.
#
# THE ENDPOINT PROBLEM AND WHY WE SOLVE IT WITH ENDPOINTS
#   A private instance with no internet route still needs to talk to AWS
#   services (SSM to allow login, S3 to install packages). Three ways exist:
#     1. NAT Gateway  - gives the instance outbound access to the WHOLE
#                       internet. Works, but ~$32/month + data charges, and it
#                       widens the attack surface (the instance can now reach
#                       anywhere). Rejected: violates least privilege.
#     2. Interface/Gateway VPC Endpoints (CHOSEN) - private tunnels to SPECIFIC
#                       AWS services only. The instance can reach SSM and S3 and
#                       NOTHING else. Least privilege applied to networking.
#     3. Instance in a public subnet - simplest, but exposes the instance.
#                       Rejected outright.
#   Interview soundbite: "I used VPC endpoints instead of a NAT gateway because
#   the instance only needed three AWS services, not the whole internet - that
#   is least privilege at the network layer, and it is cheaper."
#
# ALTERNATIVE ARCHITECTURES YOU SHOULD KNOW
#   - AWS Transit Gateway: for connecting MANY VPCs (enterprise scale). Overkill
#     for one VPC but name-drop it as the scaling path.
#   - IPv6 / dual-stack: modern option; we use IPv4 for simplicity.
# =============================================================================

# Three-tier VPC: public (kept for design completeness), private-app
# (EC2 client, no internet path), private-db (RDS only).

#checkov:skip=CKV2_AWS_11:VPC Flow Logs omitted for cost; network visibility is provided by GuardDuty (which consumes flow logs internally) - named in Recommendations
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true # required by VPC interface endpoints
  tags                 = { Name = "${var.project}-vpc" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.project}-igw" }
}

resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 1)
  availability_zone = var.azs[count.index]
  tags              = { Name = "${var.project}-public-${var.azs[count.index]}", Tier = "public" }
}

resource "aws_subnet" "private_app" {
  count             = 2
  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 11)
  availability_zone = var.azs[count.index]
  tags              = { Name = "${var.project}-app-${var.azs[count.index]}", Tier = "private-app" }
}

resource "aws_subnet" "private_db" {
  count             = 2
  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 21)
  availability_zone = var.azs[count.index]
  tags              = { Name = "${var.project}-db-${var.azs[count.index]}", Tier = "private-db" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
  tags = { Name = "${var.project}-public-rt" }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private route table has NO default route: no internet path in or out.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.project}-private-rt" }
}

resource "aws_route_table_association" "private_app" {
  count          = 2
  subnet_id      = aws_subnet.private_app[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_db" {
  count          = 2
  subnet_id      = aws_subnet.private_db[count.index].id
  route_table_id = aws_route_table.private.id
}

# VPC endpoints so a fully private instance can reach SSM.
locals {
  ssm_services = var.enable_ssm_endpoints ? ["ssm", "ssmmessages", "ec2messages", "secretsmanager", "logs"] : []
  # secretsmanager endpoint: REQUIRED by RDS Proxy. The proxy ENIs live in the
  # private subnets (no internet route) and must fetch the DB secret from
  # Secrets Manager at connection time. Without this endpoint the proxy
  # deploys but its target stays permanently UNAVAILABLE.
}

resource "aws_vpc_endpoint" "ssm" {
  for_each            = toset(local.ssm_services)
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.eu-west-2.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_app[0].id] # one AZ keeps cost down; both in production
  security_group_ids  = [var.endpoint_security_group_id]
  private_dns_enabled = true
  tags                = { Name = "${var.project}-vpce-${each.value}" }
}

# S3 GATEWAY endpoint (free). Required so a no-internet AL2023 instance
# can reach the Amazon Linux package repositories, which are hosted in
# regional S3. Gateway endpoints attach to route tables, not subnets.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.eu-west-2.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]
  tags              = { Name = "${var.project}-vpce-s3" }
}

# DEFECT FIX (final review): the app SG allowed egress 443 only to the VPC CIDR.
# A GATEWAY endpoint routes to S3's PUBLIC IP ranges, which are outside the VPC
# CIDR, so dnf (AL2023 repos live in regional S3) was silently blocked even
# though the endpoint existed. Gateway endpoints are matched in SG rules by
# PREFIX LIST, never by CIDR. Interface endpoints (SSM) have in-VPC IPs, which
# is why SSM worked while dnf failed.
resource "aws_security_group_rule" "app_https_to_s3_gateway" {
  type              = "egress"
  description       = "HTTPS to regional S3 via gateway endpoint (AL2023 dnf repos)"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  prefix_list_ids   = [aws_vpc_endpoint.s3.prefix_list_id]
  security_group_id = var.app_security_group_id
}

# Zero-trust hygiene + CKV2_AWS_12: the VPC default SG must hold no rules so
# any resource accidentally launched without an explicit SG can talk to nothing.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.project}-default-sg-locked" }
}
