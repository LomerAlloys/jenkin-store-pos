resource "aws_key_pair" "deployer" {
  key_name   = "${var.name_prefix}-key"
  public_key = var.ssh_public_key
}

resource "aws_security_group" "app" {
  name        = "${var.name_prefix}-sg"
  description = "taskflow-api host"

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "app" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.app.id]

  tags = {
    Name = "${var.name_prefix}-host"
  }
}
