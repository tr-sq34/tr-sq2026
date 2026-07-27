bucket         = "turksquare-terraform-state-626300432889"
key            = "backup/terraform.tfstate"
region         = "us-east-1"
dynamodb_table = "turksquare-terraform-lock"
encrypt        = true
kms_key_id     = "arn:aws:kms:us-east-1:626300432889:key/bc05d6ec-8e88-498d-b8ec-2bc18e10fb60"

assume_role {
  role_arn = "arn:aws:iam::626300432889:role/TerraformStateAccessBackup"
}
