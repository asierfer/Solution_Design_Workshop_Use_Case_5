variable "my_prefix" {
  description = "Prefix to add to the resources name"
  type = string
  default = "afe-tf-"
}

variable "confluent_cloud_api_key" {
  description = "Confluent Cloud API Key"
  type = string
  default = "<the key>"
}

variable "confluent_cloud_api_secret" {
  description = "Confluent Cloud API Secret"
  type = string
  default = "<the secret>"
}

variable "aws_key" {
  description = "AWS access key"
  type = string
  default = "<the key>"
}

variable "aws_secret" {
  description = "SFDC token"
  type = string
  default = "<the token>"
}
