# SPDX-License-Identifier: Apache-2.0
# AWS EC2 VM Import/Export deploy adapter (stub)
# Path: upload raw image to S3 -> aws ec2 import-snapshot -> register AMI -> launch instance

def check-aws-cli [] {
  if ("/usr/local/bin/aws" | path exists) {
    return "/usr/local/bin/aws"
  }

  if ($env.PATH | split row (char esep) | any { |p| ($p | path join "aws" | path exists) }) {
    return "aws"
  }

  null
}

export def aws_deploy [manifest: record, dry_run: bool = false] {
  if $dry_run {
    return {
      action: "would-run"
      provider: "aws_ec2"
      steps: ["upload-to-s3", "import-snapshot", "register-ami", "launch-instance"]
      note: "AWS VM Import requires vmimport IAM role"
    }
  }

  # Real run: not yet implemented
  {
    action: "not-implemented"
    provider: "aws_ec2"
    note: "AWS deploy requires manual vmimport setup"
  }
}
