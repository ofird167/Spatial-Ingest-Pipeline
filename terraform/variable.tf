variable "region" {
  description = "The AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "The instance type for the EC2 servers"
  type        = string
  default     = "t3.micro"
}

variable "db_password" {
  description = "The password for the RDS database"
  type        = string
  sensitive   = true # Terraform will hide this in logs
}

variable "key_name" {
  description = "The AWS key pair name for SSH access"
  type        = string
}