variable "vpc_cidr" {
  type        = string
  description = "Dedicated Identity VPC CIDR; validate against the organization address plan before apply."
  default     = "10.42.0.0/16"
}

variable "postgres_version" {
  type    = string
  default = null
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.medium"
}
variable "api_domain_name" {
  type    = string
  default = "api.turksquare.com"
}

variable "email_domain" {
  type        = string
  description = "Verified SES domain used for transactional Identity email."
  default     = "turksquare.com"
}

variable "email_from_local_part" {
  type        = string
  description = "Local part of the transactional sender address."
  default     = "noreply"
}

variable "community_profile_projection_queue_arn" {
  type        = string
  default     = null
  nullable    = true
  description = "Community SQS queue ARN, set after Community foundation is applied."
}

variable "community_profile_projection_queue_url" {
  type        = string
  default     = null
  nullable    = true
  description = "Community SQS queue URL, set after Community foundation is applied."
}
