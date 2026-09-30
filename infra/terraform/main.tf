resource "aws_key_pair" "deployer" {
  key_name   = "${var.name_prefix}-key"
  public_key = var.ssh_public_key
}

resource "aws_security_group" "app" {
  name        = "${var.name_prefix}-sg"
  description = "taskflow-api host: app port and SSH from the private CI network only"

  # FIX (tfsec aws-ec2-no-public-ingress-sgr / checkov CKV_AWS_24, CKV_AWS_23):
  # was 0.0.0.0/0 with no description
  ingress {
    description = "taskflow-api HTTP from private network"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  ingress {
    description = "SSH for Ansible from the Jenkins network"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  # FIX: was "all protocols, all ports, anywhere". Now only what the host needs.
  egress {
    description = "Pull images from the private registry (kind-registry:5000)"
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  # ACCEPTED RISK: the host must download apt packages and Node.js from the internet.
  # tfsec:ignore:aws-ec2-no-public-egress-sgr
  egress {
    description = "HTTPS to package mirrors and nodejs.org"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # tfsec:ignore:aws-ec2-no-public-egress-sgr
  egress {
    description = "HTTP to Ubuntu apt mirrors"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "DNS"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = [var.allowed_cidr]
  }

  #checkov:skip=CKV_AWS_382:Egress is limited to 80/443 (package downloads), 53 and 5000 inside the private CIDR
}

resource "aws_instance" "app" {
  #checkov:skip=CKV2_AWS_41:The host calls no AWS APIs, so it gets no IAM role (least privilege)
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.app.id]

  # FIX (tfsec aws-ec2-enforce-http-token-imds / checkov CKV_AWS_79): IMDSv2 only
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  # FIX (tfsec aws-ec2-enable-at-rest-encryption / checkov CKV_AWS_8): encrypted root disk
  root_block_device {
    encrypted   = true
    volume_type = "gp3"
  }

  monitoring    = true # checkov CKV_AWS_126
  ebs_optimized = true # checkov CKV_AWS_135

  tags = {
    Name = "${var.name_prefix}-host"
  }
}