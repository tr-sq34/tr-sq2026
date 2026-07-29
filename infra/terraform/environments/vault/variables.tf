variable "vpc_cidr" {
  type    = string
  default = "10.44.0.0/16"
}
variable "postgres_version" {
  type    = string
  default = null
}
variable "db_instance_class" {
  type    = string
  default = "db.t4g.medium"
}
variable "enable_stripe_egress" {
  type        = bool
  default     = false
  description = "Creates the controlled NAT egress required by Stripe. Must be true before starting ECS tasks."
}
variable "service_desired_count" {
  type    = number
  default = 0
}
variable "identity_jwt_signing_kms_key_arn" {
  type    = string
  default = "arn:aws:kms:us-east-1:342998331436:key/replace-at-apply"
}
variable "community_capability_queue_url" {
  type      = string
  default   = ""
  sensitive = true
}
variable "community_capability_queue_arn" {
  type      = string
  default   = ""
  sensitive = true
}
variable "verification_return_url" {
  type    = string
  default = "https://verify.turksquare.com/complete"
}
variable "verification_domain_name" {
  type    = string
  default = "verify.turksquare.com"
}
