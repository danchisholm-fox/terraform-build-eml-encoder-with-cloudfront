resource "aws_media_package_channel" "emp" {
  channel_id = "${var.project_name}-emp"

  tags = {
    Project = var.project_name
  }
}

output "mediapackage_endpoints_info" {
  description = "EMP ingest and playback info (ingest provided to MediaLive via destination ref)"
  value       = aws_media_package_channel.emp.hls_ingest
}

resource "aws_cloudformation_stack" "emp_hls_endpoint" {
  name = "${var.project_name}-emp-hls-endpoint"

  template_body = <<YAML
AWSTemplateFormatVersion: '2010-09-09'
Description: MediaPackage HLS OriginEndpoint for Terraform-managed channel
Parameters:
  ChannelId:
    Type: String
  EndpointId:
    Type: String
Resources:
  HlsEndpoint:
    Type: AWS::MediaPackage::OriginEndpoint
    Properties:
      ChannelId: !Ref ChannelId
      Id: !Ref EndpointId
      HlsPackage:
        SegmentDurationSeconds: 6
        PlaylistWindowSeconds: 60
Outputs:
  EndpointUrl:
    Value: !GetAtt HlsEndpoint.Url
YAML

  parameters = {
    ChannelId  = aws_media_package_channel.emp.id
    EndpointId = "${var.project_name}-hls1"
  }
}

output "mediapackage_hls_url" {
  description = "EMP HLS playback URL"
  value       = aws_cloudformation_stack.emp_hls_endpoint.outputs["EndpointUrl"]
}

