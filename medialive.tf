# Input Security Group allowing RTMP push from specified CIDRs
## File-pull input for slate (MP4/TS over HTTPS)
resource "aws_medialive_input" "slate_file" {
  name = "${var.project_name}-slate-file-input"

  # Use MP4_FILE to allow direct file pull over HTTPS (CloudFront URL)
  type = "MP4_FILE"

  # MediaLive expects two sources for redundancy; we can duplicate the same URL
  sources {
    url            = "https://${aws_cloudfront_distribution.dist.domain_name}/${var.content_key_path}"
    username       = "unused"
    password_param = aws_ssm_parameter.url_pull_password.name
  }

  tags = {
    Project = var.project_name
  }
}

# MediaLive Channel with HLS group to S3
resource "aws_medialive_channel" "channel" {
  name         = "${var.project_name}-channel"
  role_arn     = aws_iam_role.medialive_access.arn
  channel_class = "SINGLE_PIPELINE" # keep it simple/cost effective

  input_specification {
    codec            = "AVC"
    maximum_bitrate  = "MAX_10_MBPS"
    input_resolution = "HD"
  }

  input_attachments {
    input_id = aws_medialive_input.slate_file.id
    input_attachment_name = "slate-file-attachment"

    input_settings {
      source_end_behavior = "LOOP"
      audio_selector {
        name = "Audio Selector 1"
      }
    }
  }

  destinations {
    id = "emp-dest"

    media_package_settings {
      channel_id = aws_media_package_channel.emp.id
    }
  }

  encoder_settings {
    timecode_config {
      source = "SYSTEMCLOCK"
    }

    audio_descriptions {
      name = "audio_1"
      audio_selector_name = "Audio Selector 1"
      codec_settings {
        aac_settings {
          bitrate     = 128000
          coding_mode = "CODING_MODE_2_0"
          input_type  = "NORMAL"
          profile     = "LC"
          rate_control_mode = "CBR"
          sample_rate = 48000
          spec        = "MPEG4"
        }
      }
    }

    video_descriptions {
      name = "video_720p"
      height = 720
      width  = 1280
      codec_settings {
        h264_settings {
          bitrate                = 3500000
          framerate_control      = "SPECIFIED"
          framerate_numerator    = 30000
          framerate_denominator  = 1001
          gop_size               = 2
          gop_size_units         = "SECONDS"
          gop_num_b_frames       = 2
          profile                = "HIGH"
          rate_control_mode      = "CBR"
          scan_type              = "PROGRESSIVE"
          scene_change_detect    = "ENABLED"
          entropy_encoding        = "CABAC"
          par_control            = "SPECIFIED"
          par_numerator          = 1
          par_denominator        = 1
        }
      }
    }

    output_groups {
      name = "MediaPackage Group"
      output_group_settings {
        media_package_group_settings {
          destination {
            destination_ref_id = "emp-dest"
          }
        }
      }

      outputs {
        output_settings {
          media_package_output_settings {}
        }
        audio_description_names = ["audio_1"]
        video_description_name  = "video_720p"
        output_name             = "to_emp_720p"
      }
    }
  }

  tags = {
    Project = var.project_name
  }
}

# Optional: start channel automatically
resource "null_resource" "start_channel" {
  count = var.start_channel_on_apply ? 1 : 0

  triggers = {
    channel_id = aws_medialive_channel.channel.id
  }

  provisioner "local-exec" {
    command = "aws medialive start-channel --channel-id ${aws_medialive_channel.channel.id} --region ${var.aws_region}"
  }
}

output "medialive_channel_id" {
  value = aws_medialive_channel.channel.id
}

output "slate_input_type" {
  value = aws_medialive_input.slate_file.type
}

output "mediapackage_channel_id" {
  value = aws_media_package_channel.emp.id
}

