variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.micro"
}

variable "public_key_path" {
  description = "Path to your SSH public key"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "admin_cidr" {
  description = "Your IP address in CIDR format, e.g. 1.2.3.4/32"
  type        = string
}

variable "app_port" {
  description = "Port exposed by the app"
  type        = number
  default     = 8080
}