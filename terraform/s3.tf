resource "aws_s3_bucket" "data_bucket" {
  bucket = "Spatial-Ingest-Pipeline-data-bucket-${random_id.suffix.hex}"
}

# You will need this for the bucket name to be unique
resource "random_id" "suffix" {
  byte_length = 4
}

# Allow S3 service to invoke our specific Lambda function
resource "aws_lambda_permission" "allow_bucket" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.data_bucket.arn
}

# Trigger Lambda function when a GeoJSON file lands in the bucket
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.data_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".geojson"
  }

  depends_on = [aws_lambda_permission.allow_bucket]
}