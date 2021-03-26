variable "region" {
  type = string
}

variable "name_prefix" {
  type = string
}

variable "environment_tag" {
  type = string
}

variable "vpc_cidr_block" {
  type = string
}


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
provider "aws" {
  region = var.region
}
















resource "aws_iam_role" "lambda_role" {
  name = "${var.name_prefix}_lambda_role"
  path = "/service-role/"

  tags = {
    Environment = var.environment_tag
  }

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
POLICY
}

resource "aws_iam_policy" "xray_policy" {
  name = "${var.name_prefix}_xray_policy"

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "xray:PutTraceSegments",
        "xray:PutTelemetryRecords"
      ],
      "Resource": [
        "*"
      ]
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "AWSLambdaBasicExecutionRole" {
  role = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "xray_policy" {
  role = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.xray_policy.arn
}

resource "aws_iam_role_policy_attachment" "AWSLambdaVPCAccessExecutionRole" {
  role = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}







resource "aws_vpc" "vpc" {
  cidr_block = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.name_prefix}_vpc"
    Environment = var.environment_tag
  }
}

resource "aws_route_table" "main_rt" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${var.name_prefix}_main_rt"
    Environment = var.environment_tag
  }
}

resource "aws_main_route_table_association" "main_rt_assoc" {
  vpc_id = aws_vpc.vpc.id
  route_table_id = aws_route_table.main_rt.id
}

resource "aws_route_table" "subnet_rt" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${var.name_prefix}_subnet_rt"
    Environment = var.environment_tag
  }
}

resource "aws_subnet" "a" {
  vpc_id = aws_vpc.vpc.id
  cidr_block = cidrsubnet(var.vpc_cidr_block, 8, 1)
  availability_zone = "${var.region}a"

  tags = {
    Name = "${var.name_prefix}_subnet_a"
    Environment = var.environment_tag
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.a.id
  route_table_id = aws_route_table.subnet_rt.id
}

resource "aws_subnet" "b" {
  vpc_id = aws_vpc.vpc.id
  cidr_block = cidrsubnet(var.vpc_cidr_block, 8, 2)
  availability_zone = "${var.region}b"

  tags = {
    Name = "${var.name_prefix}_subnet_b"
    Environment = var.environment_tag
  }
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.b.id
  route_table_id = aws_route_table.subnet_rt.id
}








resource "aws_security_group" "lambda_sg" {
  name = "${var.name_prefix}_lambda_sg"
  vpc_id = aws_vpc.vpc.id

  tags = {
    Environment = var.environment_tag
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "all"
    cidr_blocks = [var.vpc_cidr_block]
  }
}

resource "aws_security_group" "rds_sg" {
  name = "${var.name_prefix}_rds_sg"
  vpc_id = aws_vpc.vpc.id

  tags = {
    Environment = var.environment_tag
  }

  ingress {
    from_port = 5432
    to_port = 5432
    protocol = "tcp"
    cidr_blocks = [var.vpc_cidr_block]
  }
}

resource "aws_security_group" "vpce_sg" {
  name = "${var.name_prefix}_vpce_sg"
  vpc_id = aws_vpc.vpc.id

  tags = {
    Environment = var.environment_tag
  }

  ingress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = [var.vpc_cidr_block]
  }
}






resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id = aws_vpc.vpc.id
  service_name = "com.amazonaws.${var.region}.secretsmanager"
  vpc_endpoint_type = "Interface"
  private_dns_enabled = true
  security_group_ids = [aws_security_group.vpce_sg.id]
  subnet_ids = [aws_subnet.a.id, aws_subnet.b.id]
  auto_accept = true

  tags = {
    Name = "${var.name_prefix}_vpce_secretsmanager"
    Environment = var.environment_tag
  }
}







resource "random_id" "bucket_id" {
  byte_length  = 8
}

resource "aws_s3_bucket" "code" {
  bucket = "${var.name_prefix}-${random_id.bucket_id.hex}-code"
  tags = {
    Environment = var.environment_tag
  }
}

resource "aws_s3_bucket_public_access_block" "code_not_public" {
  bucket = aws_s3_bucket.code.id

  block_public_acls = true
  block_public_policy = true
  ignore_public_acls = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_object" "lambda_zip" {
  bucket = aws_s3_bucket.code.bucket
  key    = "lambda-${filemd5("../out/lambda.zip")}.zip"
  source = "../out/lambda.zip"
}






resource "aws_s3_bucket" "media" {
  bucket = "${var.name_prefix}-${random_id.bucket_id.hex}-media"
  tags = {
    Environment = var.environment_tag
  }
}

resource "aws_s3_bucket_public_access_block" "media_not_public" {
  bucket = aws_s3_bucket.media.id

  block_public_acls = true
  block_public_policy = true
  ignore_public_acls = true
  restrict_public_buckets = true
}







locals {
  lambda_variables = {
    "ENV_SECRET_ID" = aws_secretsmanager_secret.env_secret.arn
    "DJANGO_SETTINGS_MODULE" = "mysite.settings.production"
    "DJANGO_DB_ENGINE" = "django.db.backends.postgresql_psycopg2"
    "DJANGO_DB_NAME" = "appdb"
    "DJANGO_DB_USER" = "appuser"
    # DJANGO_DB_PASSWORD is in the secret
    "DJANGO_DB_HOST" = aws_rds_cluster.rds.endpoint
    "DJANGO_DB_PORT" = aws_rds_cluster.rds.port
  }
}






resource "aws_lambda_function" "wsgi" {
  function_name = "${var.name_prefix}_wsgi"
  role = aws_iam_role.lambda_role.arn
  handler = "lambda_function.lambda_handler"
  s3_bucket = aws_s3_bucket_object.lambda_zip.bucket
  s3_key = aws_s3_bucket_object.lambda_zip.key
  s3_object_version = aws_s3_bucket_object.lambda_zip.version_id
  memory_size = "256"
  publish = false
  timeout = "180"
  runtime = "python3.8"

  environment {
    variables = local.lambda_variables
  }

  tracing_config {
    mode = "Active"
  }

  vpc_config {
    subnet_ids = [aws_subnet.a.id, aws_subnet.b.id]
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  tags = {
    Environment = var.environment_tag
  }
}

resource "aws_lambda_permission" "wsgi_perm" {
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.wsgi.arn
  principal = "apigateway.amazonaws.com"
  source_arn = "${aws_apigatewayv2_api.apigw.execution_arn}/*/${aws_apigatewayv2_stage.default.name}"
}








resource "aws_lambda_function" "manage" {
  function_name = "${var.name_prefix}_manage"
  role = aws_iam_role.lambda_role.arn
  handler = "lambda_function.manage"
  s3_bucket = aws_s3_bucket_object.lambda_zip.bucket
  s3_key = aws_s3_bucket_object.lambda_zip.key
  s3_object_version = aws_s3_bucket_object.lambda_zip.version_id
  memory_size = "512"
  publish = false
  timeout = "60"
  runtime = "python3.8"

  environment {
    variables = local.lambda_variables
  }

  tracing_config {
    mode = "Active"
  }

  vpc_config {
    subnet_ids = [aws_subnet.a.id, aws_subnet.b.id]
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  tags = {
    Environment = var.environment_tag
  }
}






resource "aws_lambda_function" "hello" {
  function_name = "${var.name_prefix}_hello"
  role = aws_iam_role.lambda_role.arn
  handler = "lambda_function.hello"
  s3_bucket = aws_s3_bucket_object.lambda_zip.bucket
  s3_key = aws_s3_bucket_object.lambda_zip.key
  s3_object_version = aws_s3_bucket_object.lambda_zip.version_id
  memory_size = "256"
  publish = false
  timeout = "5"
  runtime = "python3.8"

  environment {
    variables = local.lambda_variables
  }

  tracing_config {
    mode = "Active"
  }

  vpc_config {
    subnet_ids = [aws_subnet.a.id, aws_subnet.b.id]
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  tags = {
    Environment = var.environment_tag
  }
}














resource "aws_cloudwatch_log_group" "log_group" {
  name = "${var.name_prefix}_log_group"

  tags = {
    Environment = var.environment_tag
  }
}

resource "aws_apigatewayv2_api" "apigw" {
  name = "${var.name_prefix}_apigw"
  protocol_type = "HTTP"

  tags = {
    Environment = var.environment_tag
  }
}

resource "aws_apigatewayv2_integration" "integration" {
  api_id = aws_apigatewayv2_api.apigw.id
  integration_type = "AWS_PROXY"

  connection_type = "INTERNET"
  // content_handling_strategy = "CONVERT_TO_TEXT"
  // description               = "Lambda example"
  integration_method = "POST"
  integration_uri = aws_lambda_function.wsgi.arn
  passthrough_behavior = "WHEN_NO_MATCH"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "route" {
  api_id = aws_apigatewayv2_api.apigw.id
  route_key = "$default"
  target = "integrations/${aws_apigatewayv2_integration.integration.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id = aws_apigatewayv2_api.apigw.id
  name = "${var.name_prefix}_apigw_stage"  # "$default" ?
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.log_group.arn
    format = "$context.identity.sourceIp - - [$context.requestTime] \"$context.httpMethod $context.routeKey $context.protocol\" $context.status $context.responseLength $context.requestId $context.integrationErrorMessage"
  }

  tags = {
    Environment = var.environment_tag
  }
}
















resource "aws_secretsmanager_secret" "env_secret" {
  name = "${var.name_prefix}_env_secret"
  recovery_window_in_days = 30

  tags = {
    Environment = var.environment_tag
  }
}

resource "aws_secretsmanager_secret_policy" "env_secret" {
  secret_arn = aws_secretsmanager_secret.env_secret.arn
  policy = <<POLICY
{
  "Version" : "2012-10-17",
  "Statement" : [ {
    "Effect" : "Allow",
    "Principal" : {
      "AWS" : "${aws_iam_role.lambda_role.arn}"
    },
    "Action" : [ "secretsmanager:GetSecretValue" ],
    "Resource" : "*"
  } ]
}
POLICY
}

resource "random_password" "django_secret_key" {
  length  = 64
  special = false
}

resource "aws_secretsmanager_secret_version" "env_secret" {
  secret_id = aws_secretsmanager_secret.env_secret.id
  secret_string = jsonencode({
    "DJANGO_SECRET_KEY": random_password.django_secret_key.result
    "DJANGO_DB_PASSWORD": random_password.app_db_password.result
  })
}

















resource "random_password" "master_password" {
  length  = 32
  special = false
}

resource "aws_db_subnet_group" "subnet_group" {
  name = "${var.name_prefix}_subnet_group"
  subnet_ids = [aws_subnet.a.id, aws_subnet.b.id]

  tags = {
    Environment = var.environment_tag
  }
}

resource "aws_rds_cluster" "rds" {
  cluster_identifier      = "${var.name_prefix}-rds"
  engine                  = "aurora-postgresql"
#  availability_zones      = ["${var.region}a", "${var.region}b"]
  master_username         = "postgres"
  master_password         = random_password.master_password.result
  apply_immediately       = true
  engine_mode             = "serverless"
  deletion_protection     = true
  db_subnet_group_name    = aws_db_subnet_group.subnet_group.name
  vpc_security_group_ids  = [aws_security_group.rds_sg.id]
  enable_http_endpoint    = true

  scaling_configuration {
    auto_pause            = true
    min_capacity          = 2
    max_capacity          = 4
    seconds_until_auto_pause = 300
  }

  tags = {
    Environment = var.environment_tag
  }
}

resource "aws_secretsmanager_secret" "rds_master_credentials" {
  name = "${var.name_prefix}_rds_master_credentials"
  tags = {
    Environment = var.environment_tag
  }
}

resource "aws_secretsmanager_secret_version" "rds_master_credentials" {
  secret_id = aws_secretsmanager_secret.rds_master_credentials.id
  secret_string = jsonencode({
    "dbInstanceIdentifier" = aws_rds_cluster.rds.cluster_identifier
    "engine" = aws_rds_cluster.rds.engine
    "host" = aws_rds_cluster.rds.endpoint
    "port" = aws_rds_cluster.rds.port
    "resourceId" = aws_rds_cluster.rds.cluster_resource_id
    "username" = aws_rds_cluster.rds.master_username
    "password" = aws_rds_cluster.rds.master_password
  })
}







# provider "postgresql" {
#   host = aws_rds_cluster.rds.endpoint
#   username = aws_rds_cluster.rds.master_username
#   password = aws_rds_cluster.rds.master_password
# }

resource "random_password" "app_db_password" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "rds_app_credentials" {
  name = "${var.name_prefix}_rds_app_credentials"
  tags = {
    Environment = var.environment_tag
  }
}

resource "aws_secretsmanager_secret_version" "rds_app_credentials" {
  secret_id = aws_secretsmanager_secret.rds_app_credentials.id
  secret_string = jsonencode({
    "dbInstanceIdentifier" = aws_rds_cluster.rds.cluster_identifier
    "engine" = aws_rds_cluster.rds.engine
    "host" = aws_rds_cluster.rds.endpoint
    "port" = aws_rds_cluster.rds.port
    "resourceId" = aws_rds_cluster.rds.cluster_resource_id
    "username" = "appuser"
    "password" = random_password.app_db_password.result
  })
}









# THIS WORKS:
# create role appuser with password '...' login inherit;
# create database appdb owner appuser;
# -- grant appuser to postgres;

# provider "rdsdataservice" {
#   region  = var.region
#   # profile = var.aws_profile
# }

# THIS DOESN'T WORK YET:
# resource "rdsdataservice_postgres_role" "app_db_role" {
#   name         = "appuser"
#   resource_arn = aws_rds_cluster.rds.arn
#   secret_arn   = aws_secretsmanager_secret.rds_master_credentials.arn
#   password     = random_password.app_db_password.result
#   login        = true
#   create_database = false
#   create_role  = false
#   inherit      = true
#   superuser    = false
# }

# THIS WORKS, BUT DEPENDS ON THE ROLE:
# resource "rdsdataservice_postgres_database" "appdb" {
#   name         = "appdb"
#   resource_arn = aws_rds_cluster.rds.arn
#   secret_arn   = aws_secretsmanager_secret.rds_master_credentials.arn
#   owner        = "appuser"
# }
