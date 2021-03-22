variable "region" {
  type = string
}

variable "code_bucket" {
  type = string
}

variable "media_bucket" {
  type = string
}

variable "lambda_name" {
  type = string
}

variable "role_name" {
  type = string
}

variable "apigw_name" {
  type = string
}

variable "cwgroup_name" {
  type = string
}

variable "xray_policy_name" {
  type = string
}

variable "secret_name" {
  type = string
}

variable "django_settings_module" {
  type = string
}









terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      # version = "~> 3.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.region
}
















resource "aws_iam_role" "wagtail" {
  name = var.role_name
  path = "/service-role/"
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

resource "aws_iam_policy" "wagtail_xray" {
  name = var.xray_policy_name
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
  role = aws_iam_role.wagtail.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "wagtail_xray" {
  role = aws_iam_role.wagtail.name
  policy_arn = aws_iam_policy.wagtail_xray.arn
}
















resource "aws_s3_bucket" "code_bucket" {
  bucket = var.code_bucket
}

resource "aws_s3_bucket_public_access_block" "code_bucket" {
  bucket = aws_s3_bucket.code_bucket.id

  block_public_acls = true
  block_public_policy = true
  ignore_public_acls = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_object" "wagtail_lambda_zip" {
  bucket = aws_s3_bucket.code_bucket.bucket
  key    = "wagtail_lambda.zip"
  source = "../out/lambda.zip"
  etag   = filemd5("../out/lambda.zip")
}

resource "aws_lambda_function" "wagtail" {
  function_name = var.lambda_name
  role = aws_iam_role.wagtail.arn
  handler = "lambda_function.lambda_handler"
  s3_bucket = aws_s3_bucket_object.wagtail_lambda_zip.bucket
  s3_key = aws_s3_bucket_object.wagtail_lambda_zip.key
  s3_object_version = aws_s3_bucket_object.wagtail_lambda_zip.version_id
  memory_size = "256"
  publish = false
  timeout = "180"
  runtime = "python3.8"

  environment {
    variables = {
      # "DJANGO_SETTINGS_MODULE" = vars.django_settings_module
      "ENV_SECRET_ID" = aws_secretsmanager_secret.env.arn
      # "DJANGO_DB_ENGINE" = "django.db.backends.postgresql_psycopg2"
      # "DJANGO_DB_NAME" = "wagtail"
      # "DJANGO_DB_USER" = "lambda"
      # # DJANGO_DB_PASSWORD is in the secret
      # "DJANGO_DB_HOST" = 
      # "DJANGO_DB_PORT" = "5432"

      # "PYPICLOUD_CONF_REGION" = var.region
      # "AUTH_SECRET_ID" = aws_secretsmanager_secret.auth.arn
      # "BUCKET" = var.package_bucket
      # "BUCKET_REGION" = var.region
      # "DYNAMO_REGION" = var.region
    }
  }

  tracing_config {
    mode = "Active"
  }
}

resource "aws_lambda_permission" "wagtail" {
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.wagtail.arn
  principal = "apigateway.amazonaws.com"
  source_arn = "${aws_apigatewayv2_api.wagtail.execution_arn}/*/${aws_apigatewayv2_stage.wagtail_default.name}"
}















resource "aws_cloudwatch_log_group" "wagtail" {
  name = var.cwgroup_name
}

resource "aws_apigatewayv2_api" "wagtail" {
  name = var.apigw_name
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "wagtail" {
  api_id = aws_apigatewayv2_api.wagtail.id
  integration_type = "AWS_PROXY"

  connection_type = "INTERNET"
  // content_handling_strategy = "CONVERT_TO_TEXT"
  // description               = "Lambda example"
  integration_method = "POST"
  integration_uri = aws_lambda_function.wagtail.arn
  passthrough_behavior = "WHEN_NO_MATCH"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "wagtail" {
  api_id = aws_apigatewayv2_api.wagtail.id
  route_key = "$default"
  target = "integrations/${aws_apigatewayv2_integration.wagtail.id}"
}

resource "aws_apigatewayv2_stage" "wagtail_default" {
  api_id = aws_apigatewayv2_api.wagtail.id
  name = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.wagtail.arn
    format = "$context.identity.sourceIp - - [$context.requestTime] \"$context.httpMethod $context.routeKey $context.protocol\" $context.status $context.responseLength $context.requestId $context.integrationErrorMessage"
  }
}
















resource "aws_secretsmanager_secret" "env" {
  name = var.secret_name
  recovery_window_in_days = 30
  description = "Secret env vars for the Wagtail Lambda function"
}

resource "aws_secretsmanager_secret_policy" "env" {
  secret_arn = aws_secretsmanager_secret.env.arn
  policy = <<POLICY
{
  "Version" : "2012-10-17",
  "Statement" : [ {
    "Effect" : "Allow",
    "Principal" : {
      "AWS" : "${aws_iam_role.wagtail.arn}"
    },
    "Action" : [ "secretsmanager:GetSecretValue" ],
    "Resource" : "*"
  } ]
}
POLICY
}





















resource "aws_s3_bucket" "media_bucket" {
  bucket = var.media_bucket
}

resource "aws_s3_bucket_public_access_block" "media_bucket" {
  bucket = aws_s3_bucket.media_bucket.id

  block_public_acls = true
  block_public_policy = true
  ignore_public_acls = true
  restrict_public_buckets = true
}

