variable "aws_region" {
  description = "AWS region to deploy MediaLive resources"
  type        = string
  default     = "us-west-2"
}

variable "project_name" {
  description = "Project/name prefix for resources"
  type        = string
  default     = "eml-simple"
}


variable "input_cidrs" {
  description = "List of CIDR blocks allowed to push RTMP"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "start_channel_on_apply" {
  description = "Whether to start the MediaLive channel after apply"
  type        = bool
  default     = false
}

variable "slate_url" {
  description = "HTTPS URL to the slate MP4/TS file (e.g., pre-signed S3 URL) used for file-pull input"
  type        = string
  default     = ""
}

variable "content_bucket_name" {
  description = "S3 bucket name that stores the slate (CloudFront origin)"
  type        = string
  default     = "video-assets-2"
}

variable "content_key_path" {
  description = "Object key path to the slate file within the content bucket (e.g., slates/slate1-sky.mp4)"
  type        = string
  default     = "slates/slate1-sky.mp4"
}

variable "cf_price_class" {
  description = "CloudFront price class (PriceClass_100, PriceClass_200, PriceClass_All)"
  type        = string
  default     = "PriceClass_100"
}

