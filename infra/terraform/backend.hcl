# Remote state in LocalStack S3 (bucket created once by hand, see Part A)
bucket                      = "taskflow-tfstate"
key                         = "lab08/terraform.tfstate"
region                      = "us-east-1"
endpoints                   = { s3 = "http://localstack:4566" }
use_path_style              = true
skip_credentials_validation = true
skip_requesting_account_id  = true
skip_metadata_api_check     = true
skip_region_validation      = true
use_lockfile                = true
