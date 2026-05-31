# 1. This tells Terraform to look for your code and zip it automatically
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../src/backend" 
  output_path = "${path.module}/lambda_function_payload.zip"
}

# 2. Define the IAM Role
resource "aws_iam_role" "lambda_exec" {
  name = "lambda_exec_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# 2.1 Attach Managed Policy for VPC Access
resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# 2.2 Attach Managed Policy for CloudWatch Logging
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# 2.3 Create Inline Policy for S3 Data Bucket Access
resource "aws_iam_role_policy" "lambda_s3_read" {
  name = "lambda_s3_read_policy"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject"]
      Resource = ["${aws_s3_bucket.data_bucket.arn}/*"]
    }]
  })
}

# 3. Define the Lambda Function (placed securely in the VPC private subnets)
resource "aws_lambda_function" "processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "geo_processor"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "app.lambda_handler"
  runtime          = "python3.9"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  # Timeout and Memory allocations tailored for data processing
  timeout     = 60
  memory_size = 256

  vpc_config {
    subnet_ids         = [aws_subnet.private_1.id, aws_subnet.private_2.id]
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  environment {
    variables = {
      DB_HOST     = split(":", aws_db_instance.default.endpoint)[0]
      DB_USER     = aws_db_instance.default.username
      DB_PASSWORD = var.db_password
      DB_NAME     = "postgres"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_vpc_access,
    aws_iam_role_policy_attachment.lambda_logs
  ]
}