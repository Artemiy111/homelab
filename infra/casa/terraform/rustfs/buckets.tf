resource "aws_s3_bucket" "mirror" {
  bucket = "mirror"
}

resource "aws_s3_bucket_policy" "mirror" {
  bucket = aws_s3_bucket.mirror.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicRead"
        Effect    = "Allow"
        Principal = "*"
        Action    = ["s3:GetObject"]
        Resource  = ["arn:aws:s3:::mirror/*"]
      }
    ]
  })
}
