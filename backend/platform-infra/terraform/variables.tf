variable "environment" { type = string }
variable "primary_region" { type = string default = "us-east-1" }
variable "dr_region" { type = string default = "us-west-2" }
variable "name_prefix" { type = string default = "turksquare" }
variable "vpc_id" { type = string description = "Existing private service VPC; no public DB subnet is permitted." }
variable "private_subnet_ids" { type = list(string) }
variable "db_security_group_ids" { type = list(string) }
variable "service_role_arns" { type = map(string) description = "Least-privilege runtime roles for identity, community and vault." }
variable "backup_account_id" { type = string }
