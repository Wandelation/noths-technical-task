terraform {
  backend "s3" {
    bucket = "noths-lab-recruitment-terraform"
    key    = "states/orange-ritual/terraform.state"
    region = "eu-west-1"
    shared_config_files = ["~/.aws/config"]
    shared_credentials_files = ["~/.aws/credentials"]
    profile = "noths"
  }
}