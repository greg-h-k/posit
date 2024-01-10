variable "region" {
  type    = string
  default = "eu-west-1"
}

variable "ami_build_instance_profile_name" {
    type = string
    default = "SSMInstanceProfile"
}

variable "rstudio_workbench_deb_url" {
    type = string
    default = "https://download2.rstudio.org/server/jammy/amd64/rstudio-workbench-2023.12.0-amd64.deb"
}