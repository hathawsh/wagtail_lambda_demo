terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      # version = "~> 3.0"
    }

    # rdsdataservice = {
    #   source = "awsiv/rdsdataservice"
    # }
  }
}

# Configure the AWS Provider
provider aws {
  region = var.region
}
