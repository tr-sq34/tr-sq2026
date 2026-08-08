terraform {
  required_version = ">= 1.8.0, < 2.0.0"

  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }

  backend "s3" {}
}

provider "aws" {
  region = "us-east-1"
  default_tags { tags = { ManagedBy = "Terraform", Project = "TurkSquare", Environment = "backup" } }
}

data "aws_caller_identity" "current" {}
output "plan_account_id" { value = data.aws_caller_identity.current.account_id }
