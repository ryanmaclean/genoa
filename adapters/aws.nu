# adapters/aws.nu — AWS EC2 VM Import/Export deploy adapter
# Path: S3 upload -> import-snapshot -> register-image (AMI) -> run-instances
# SPDX-License-Identifier: Apache-2.0

export def aws_deploy [
  manifest: record
  image_path: string
  --dry-run
] {
  let region     = ($manifest | get deploy?.region?         | default "us-east-1")
  let inst_type  = ($manifest | get deploy?.instance_type?  | default "t3.micro")
  let arch       = ($manifest | get target?.arch?           | default "amd64")
  let ec2_arch   = if $arch == "aarch64" { "arm64" } else { "x86_64" }
  let bucket     = ($manifest | get deploy?.s3_bucket?      | default "genoa-images")
  let img_name   = ($manifest | get image?.name?            | default "genoa-freebsd")
  let filename   = ($image_path | path basename)

  if $dry_run {
    return {
      action:        "would-run"
      provider:      "aws_ec2"
      method:        "vm-import"
      region:        $region
      arch:          $ec2_arch
      instance_type: $inst_type
      steps: [
        "upload-to-s3"
        "import-snapshot"
        "wait-import-complete"
        "register-ami"
        "run-instance"
        "verify-ssh"
      ]
      s3_cmd:        $"aws s3 cp ($image_path) s3://($bucket)/($filename) --region ($region)"
      import_cmd:    $"aws ec2 import-snapshot --region ($region) --disk-container 'Format=RAW,UserBucket={S3Bucket=($bucket),S3Key=($filename)}'"
      register_cmd:  $"aws ec2 register-image --region ($region) --name ($img_name) --architecture ($ec2_arch) --boot-mode uefi --root-device-name /dev/sda1 --block-device-mappings 'DeviceName=/dev/sda1,Ebs={SnapshotId=<snap-id>}'"
      run_cmd:       $"aws ec2 run-instances --region ($region) --image-id <ami-id> --instance-type ($inst_type)"
      note:          "Requires vmimport IAM role (https://docs.aws.amazon.com/vm-import/latest/userguide/required-permissions.html). FreeBSD is community-supported on EC2; use Nitro instance types (t3/t4g/m5) for UEFI boot."
      warnings: [
        "vmimport-iam-role-required"
        "import-snapshot-is-async-can-take-10min+"
        "uefi-boot-mode-requires-nitro-instances"
      ]
    }
  }

  # Live path
  let aws = find_bin "aws"
  if $aws == null {
    return {action: "failed", reason: "aws CLI not found — install: brew install awscli", provider: "aws_ec2"}
  }
  if not ($image_path | path exists) {
    return {action: "failed", reason: $"image not found: ($image_path)", provider: "aws_ec2"}
  }

  # Step 1: upload to S3
  let s3_key = $filename
  let upload = try {
    ^$aws s3 cp $image_path $"s3://($bucket)/($s3_key)" --region $region | complete
  } catch { |e|
    return {action: "failed", step: "s3_upload", error: $e.msg, provider: "aws_ec2"}
  }
  if $upload.exit_code != 0 {
    return {action: "failed", step: "s3_upload", stderr: $upload.stderr, provider: "aws_ec2"}
  }

  # Step 2: import-snapshot (async — returns ImportTaskId)
  let disk_container = $"Format=RAW,UserBucket={S3Bucket=($bucket),S3Key=($s3_key)}"
  let import_res = try {
    ^$aws ec2 import-snapshot --region $region --disk-container $disk_container --output json | from json
  } catch { |e|
    return {action: "failed", step: "import_snapshot", error: $e.msg, provider: "aws_ec2"}
  }

  let task_id = ($import_res | get ImportTaskId? | default null)

  # Fail fast if the API response lacked an ImportTaskId — otherwise the
  # next_steps would instruct the caller to poll a null task and fail later.
  if $task_id == null {
    return {action: "failed", step: "import_snapshot_parse", reason: "ImportTaskId not present in import-snapshot response", detail: $import_res, provider: "aws_ec2"}
  }

  {
    action:          "import-started"
    provider:        "aws_ec2"
    region:          $region
    import_task_id:  $task_id
    s3_location:     $"s3://($bucket)/($s3_key)"
    next_steps: [
      $"Poll: aws ec2 describe-import-snapshot-tasks --region ($region) --import-task-ids ($task_id)"
      $"When complete, register AMI: aws ec2 register-image --region ($region) --name ($img_name) --architecture ($ec2_arch) --boot-mode uefi --root-device-name /dev/sda1 --block-device-mappings DeviceName=/dev/sda1,Ebs={SnapshotId=<snap-id>}"
      $"Launch: aws ec2 run-instances --region ($region) --image-id <ami-id> --instance-type ($inst_type)"
    ]
    note: "import-snapshot is async (~10min). Poll before registering AMI."
  }
}
