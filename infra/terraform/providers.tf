provider "aws" {
  region = var.region

  # LocalStack accepts any credentials; they come from AWS_ACCESS_KEY_ID /
  # AWS_SECRET_ACCESS_KEY in the pipeline environment, never from this file.
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    ec2 = var.aws_endpoint
    iam = var.aws_endpoint
    sts = var.aws_endpoint
  }

  default_tags {
    tags = {
      Project   = "taskflow"
      Lab       = "08"
      ManagedBy = "terraform"
    }
  }
}
