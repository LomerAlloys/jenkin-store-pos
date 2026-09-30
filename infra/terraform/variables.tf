variable "region" {
  description = "AWS region (LocalStack ignores it but the provider needs one)"
  type        = string
  default     = "us-east-1"
}

variable "aws_endpoint" {
  description = "AWS API endpoint. LocalStack on jenkins-net = http://localstack:4566"
  type        = string
  default     = "http://localstack:4566"
}

variable "name_prefix" {
  description = "Prefix for every resource name"
  type        = string
  default     = "taskflow-lab08"
}

variable "ami_id" {
  description = "AMI to boot. Check yours with: awslocal ec2 describe-images"
  type        = string
  default     = "ami-61ad6e59d7b0"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "ssh_public_key" {
  description = "OpenSSH public key injected into the instance (from the Jenkins SSH credential)"
  type        = string
}

variable "allowed_cidr" {
  description = "Private CIDR allowed to reach the host (jenkins-net lives inside 172.16.0.0/12)"
  type        = string
  default     = "172.16.0.0/12"
}
