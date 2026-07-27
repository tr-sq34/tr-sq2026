variable "vpc_cidr" {
  type        = string
  description = "Dedicated Identity VPC CIDR; validate against the organization address plan before apply."
  default     = "10.42.0.0/16"
}

variable "postgres_version" {
  type    = string
  default = "16.6"
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.medium"
}