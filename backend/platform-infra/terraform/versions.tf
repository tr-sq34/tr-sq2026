terraform {
  required_version = ">= 1.8.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.primary_region
  default_tags { tags = { Application = "turksquare", Environment = var.environment, ManagedBy = "terraform" } }
}

provider "aws" {
  alias  = "dr"
  region = var.dr_region
  default_tags { tags = { Application = "turksquare", Environment = var.environment, ManagedBy = "terraform" } }
}
