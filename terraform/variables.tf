variable "access_key" {
  description = "The AWS access key."
}

variable "secret_key" {
  description = "The AWS secret key."
}

variable "region" {
  description = "The region to create resources."
  default     = "us-east-1"
}

variable "namespace" {
  description = "In case running multiple demos."
}

variable "cidr_block" {
  default = "10.1.0.0/16"
}

variable "vault_address" {
  description = "The address where Vault will reside"
  default     = "vault.demo"
}

variable "vault_version" {
  description = "The version of Vault to install (server and client)"
  default     = "0.6.2"
}

variable "certbot_email" {
  description = "The Let's Encrypt email address"
}

variable "dnsimple_domain" {
  description = "The root domain to use"
}

variable "dnsimple_email" {
  description = "The email to authenticate with"
}

variable "dnsimple_token" {
  description = "The token to authenticate with"
}
