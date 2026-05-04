# Format conversion for genoa disk images
# Wraps qemu-img for format conversion.
# qemu-img is GPL-2 — invoked as external subprocess only, never linked or vendored.

def check-qemu-img [] {
  if ($env.PATH | split row (char esep) | any { |p| ($p | path join "qemu-img" | path exists) }) {
    return "qemu-img"
  }

  if ("/opt/homebrew/bin/qemu-img" | path exists) {
    return "/opt/homebrew/bin/qemu-img"
  }

  null
}

export def convert_to_qcow2 [input: string, output: string, dry_run: bool = false] {
  let qemu_img = check-qemu-img

  if $qemu_img == null {
    return {
      action: "failed"
      reason: "qemu-img not found"
      suggestion: "brew install qemu  # or: pkg install qemu on FreeBSD"
    }
  }

  let cmd = [$qemu_img "convert" "-O" "qcow2" "-c" $input $output]

  if $dry_run {
    return {
      action: "would-run"
      command: ($cmd | str join " ")
      format: "qcow2"
      input: $input
      output: $output
    }
  }

  try {
    ^$qemu_img convert -O qcow2 -c $input $output
    return {
      action: "completed"
      format: "qcow2"
      input: $input
      output: $output
      exit_code: 0
    }
  } catch { |err|
    return {
      action: "failed"
      error: ($err | tostring)
      exit_code: 1
    }
  }
}

export def convert_to_vhd [input: string, output: string, dry_run: bool = false] {
  let qemu_img = check-qemu-img

  if $qemu_img == null {
    return {
      action: "failed"
      reason: "qemu-img not found"
      suggestion: "brew install qemu  # or: pkg install qemu on FreeBSD"
    }
  }

  # VHD gotcha: must be aligned to 1 MiB minus 1 byte for Azure
  # Use -o subformat=fixed for Azure compatibility
  let cmd = [$qemu_img "convert" "-O" "vpc" "-o" "subformat=fixed" $input $output]

  if $dry_run {
    return {
      action: "would-run"
      command: ($cmd | str join " ")
      format: "vhd-fixed"
      input: $input
      output: $output
      note: "Output must be 1 MiB aligned for Azure"
    }
  }

  try {
    ^$qemu_img convert -O vpc -o subformat=fixed $input $output
    return {
      action: "completed"
      format: "vhd-fixed"
      input: $input
      output: $output
      exit_code: 0
    }
  } catch { |err|
    return {
      action: "failed"
      error: ($err | tostring)
      exit_code: 1
    }
  }
}

export def convert_to_vmdk [input: string, output: string, dry_run: bool = false] {
  let qemu_img = check-qemu-img

  if $qemu_img == null {
    return {
      action: "failed"
      reason: "qemu-img not found"
      suggestion: "brew install qemu  # or: pkg install qemu on FreeBSD"
    }
  }

  # VMDK gotcha: use streamOptimized for vSphere import
  let cmd = [$qemu_img "convert" "-O" "vmdk" "-o" "subformat=streamOptimized" $input $output]

  if $dry_run {
    return {
      action: "would-run"
      command: ($cmd | str join " ")
      format: "vmdk-streamOptimized"
      input: $input
      output: $output
    }
  }

  try {
    ^$qemu_img convert -O vmdk -o subformat=streamOptimized $input $output
    return {
      action: "completed"
      format: "vmdk-streamOptimized"
      input: $input
      output: $output
      exit_code: 0
    }
  } catch { |err|
    return {
      action: "failed"
      error: ($err | tostring)
      exit_code: 1
    }
  }
}

export def convert_to_gcstar [input: string, output: string, dry_run: bool = false] {
  # GCE tar: cp disk.raw disk.raw && tar -czvf image.tar.gz disk.raw
  # Google Cloud's importer looks for a file named exactly disk.raw

  let tmp_dir = $output | path dirname
  let tar_base = $output | path basename | str replace ".tar.gz" ""
  let disk_name = $"($tmp_dir)/disk.raw"

  let cmds = [
    $"cp ($input) ($disk_name)"
    $"tar -czvf ($output) -C ($tmp_dir) disk.raw"
    $"rm ($disk_name)"
  ]

  if $dry_run {
    return {
      action: "would-run"
      commands: $cmds
      format: "gce-tar"
      input: $input
      output: $output
      note: "Disk must be named exactly 'disk.raw' inside tar.gz"
    }
  }

  try {
    cp $input $disk_name
    tar -czvf $output -C $tmp_dir disk.raw
    rm $disk_name
    return {
      action: "completed"
      format: "gce-tar"
      input: $input
      output: $output
      exit_code: 0
    }
  } catch { |err|
    return {
      action: "failed"
      error: ($err | tostring)
      exit_code: 1
    }
  }
}
