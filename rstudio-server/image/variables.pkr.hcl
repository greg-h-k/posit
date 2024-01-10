variable "region" {
  type    = string
  default = "eu-west-1"
}

variable "build_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "source_ami_filter_name" {
  type    = string
  default = "ubuntu/images/*ubuntu-jammy-22.04-amd64-server-*"
}

variable "ami_build_instance_profile_name" {
    type = string
    default = "SSMInstanceProfile"
}

variable "rstudio_server_deb_url" {
    type = string
    default = "https://download2.rstudio.org/server/jammy/amd64/rstudio-server-2023.12.0-369-amd64.deb"
}

variable "shiny_server_deb_url" {
    type = string
    default = "https://download3.rstudio.org/ubuntu-18.04/x86_64/shiny-server-1.5.20.1002-amd64.deb"
}



