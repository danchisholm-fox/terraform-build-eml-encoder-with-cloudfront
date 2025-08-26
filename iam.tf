data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

resource "aws_iam_role" "medialive_access" {
  name = "${var.project_name}-MediaLiveAccessRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "medialive.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Project = var.project_name
  }
}

# Minimal inline policy granting MediaLive ability to write HLS to S3 and send logs to CloudWatch Logs
resource "aws_iam_role_policy" "medialive_policy" {
  name = "${var.project_name}-MediaLiveDestLogsPolicy"
  role = aws_iam_role.medialive_access.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CWLogsWrite"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      },
      {
        Sid    = "MediaPackageAccess"
        Effect = "Allow"
        Action = [
          "mediapackage:DescribeChannel"
        ]
        Resource = "*"
      },
      {
        Sid    = "SSMReadPasswordParam"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = [
          aws_ssm_parameter.url_pull_password.arn
        ]
      },
      {
        Sid    = "EC2ENIForVPCOutputs"
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:CreateNetworkInterfacePermission",
          "ec2:DeleteNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:AssociateAddress",
          "ec2:DescribeAddresses"
        ]
        Resource = "*"
      }
    ]
  })
}

