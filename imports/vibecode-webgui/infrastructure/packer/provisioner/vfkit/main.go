package main

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/hashicorp/packer-plugin-sdk/packer"
	"github.com/hashicorp/packer-plugin-sdk/template/config"
	"github.com/hashicorp/packer-plugin-sdk/template/interpolate"
)

// Config represents the configuration for the vfkit provisioner
type Config struct {
	// VM configuration
	VMName     string `mapstructure:"vm_name"`
	Memory     int    `mapstructure:"memory"`
	CPUs       int    `mapstructure:"cpus"`
	DiskSize   string `mapstructure:"disk_size"`
	MacOSVersion string `mapstructure:"macos_version"`
	
	// vfkit specific options
	Bootloader string `mapstructure:"bootloader"`
	Network   string `mapstructure:"network"`
	Display   string `mapstructure:"display"`
	LogLevel  string `mapstructure:"log_level"`
	
	// Output configuration
	OutputDir string `mapstructure:"output_dir"`
	
	ctx interpolate.Context
}

// Provisioner represents the vfkit provisioner
type Provisioner struct {
	config Config
}

// Prepare validates and prepares the configuration
func (p *Provisioner) Prepare(raws ...interface{}) error {
	err := config.Decode(&p.config, &config.DecodeOpts{
		Interpolate:        true,
		InterpolateContext: &p.config.ctx,
		InterpolateFilter: &interpolate.RenderFilter{
			Exclude: []string{},
		},
	}, raws...)
	if err != nil {
		return err
	}

	// Set defaults
	if p.config.VMName == "" {
		p.config.VMName = "vibecode-macos-vfkit"
	}
	if p.config.Memory == 0 {
		p.config.Memory = 8192
	}
	if p.config.CPUs == 0 {
		p.config.CPUs = 4
	}
	if p.config.DiskSize == "" {
		p.config.DiskSize = "64G"
	}
	if p.config.MacOSVersion == "" {
		p.config.MacOSVersion = "14.0"
	}
	if p.config.Bootloader == "" {
		p.config.Bootloader = "macos"
	}
	if p.config.Network == "" {
		p.config.Network = "nat"
	}
	if p.config.Display == "" {
		p.config.Display = "gui"
	}
	if p.config.LogLevel == "" {
		p.config.LogLevel = "debug"
	}
	if p.config.OutputDir == "" {
		p.config.OutputDir = "output-vibecode-macos-vfkit"
	}

	return nil
}

// Provision creates the vfkit VM
func (p *Provisioner) Provision(ctx context.Context, ui packer.Ui, comm packer.Communicator, generatedData map[string]interface{}) error {
	ui.Say("Starting vfkit macOS VM creation...")

	// Check prerequisites
	if err := p.checkPrerequisites(ui); err != nil {
		return err
	}

	// Create output directory
	outputDir := p.config.OutputDir
	if err := os.MkdirAll(outputDir, 0755); err != nil {
		return fmt.Errorf("failed to create output directory: %v", err)
	}

	vmDir := filepath.Join(outputDir, "vm-files")
	if err := os.MkdirAll(vmDir, 0755); err != nil {
		return fmt.Errorf("failed to create VM directory: %v", err)
	}

	// Create VM files
	if err := p.createVMFiles(vmDir, ui); err != nil {
		return err
	}

	// Create management scripts
	if err := p.createManagementScripts(vmDir, ui); err != nil {
		return err
	}

	// Create installation script
	if err := p.createInstallationScript(vmDir, ui); err != nil {
		return err
	}

	// Create README
	if err := p.createREADME(vmDir, ui); err != nil {
		return err
	}

	ui.Say(fmt.Sprintf("✅ vfkit macOS VM created successfully in %s", vmDir))
	return nil
}

// checkPrerequisites verifies that required tools are available
func (p *Provisioner) checkPrerequisites(ui packer.Ui) error {
	ui.Say("Checking prerequisites...")

	// Check vfkit
	if _, err := exec.LookPath("vfkit"); err != nil {
		return fmt.Errorf("vfkit not found. Install with: brew install vfkit")
	}

	// Check qemu-img
	if _, err := exec.LookPath("qemu-img"); err != nil {
		return fmt.Errorf("qemu-img not found. Install with: brew install qemu")
	}

	// Check if running on Apple Silicon
	cmd := exec.Command("uname", "-m")
	output, err := cmd.Output()
	if err != nil {
		return fmt.Errorf("failed to check architecture: %v", err)
	}

	if !strings.Contains(string(output), "arm64") {
		return fmt.Errorf("vfkit requires Apple Silicon Mac")
	}

	ui.Say("✅ Prerequisites check passed")
	return nil
}

// createVMFiles creates the necessary VM files
func (p *Provisioner) createVMFiles(vmDir string, ui packer.Ui) error {
	ui.Say("Creating VM files...")

	// Create disk image
	diskPath := filepath.Join(vmDir, fmt.Sprintf("%s.qcow2", p.config.VMName))
	cmd := exec.Command("qemu-img", "create", "-f", "qcow2", diskPath, p.config.DiskSize)
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("failed to create disk image: %v", err)
	}

	// Create hardware model file
	hardwareModelPath := filepath.Join(vmDir, "hardware-model")
	cmd = exec.Command("sysctl", "-n", "hw.model")
	output, err := cmd.Output()
	if err != nil {
		return fmt.Errorf("failed to get hardware model: %v", err)
	}
	if err := os.WriteFile(hardwareModelPath, output, 0644); err != nil {
		return fmt.Errorf("failed to write hardware model file: %v", err)
	}

	// Create machine identifier
	machineIDPath := filepath.Join(vmDir, "machine-id")
	cmd = exec.Command("uuidgen")
	output, err = cmd.Output()
	if err != nil {
		return fmt.Errorf("failed to generate machine ID: %v", err)
	}
	if err := os.WriteFile(machineIDPath, output, 0644); err != nil {
		return fmt.Errorf("failed to write machine ID file: %v", err)
	}

	// Create auxiliary image
	auxImagePath := filepath.Join(vmDir, "aux-image")
	if err := os.WriteFile(auxImagePath, []byte{}, 0644); err != nil {
		return fmt.Errorf("failed to create auxiliary image: %v", err)
	}

	ui.Say("✅ VM files created")
	return nil
}

// createManagementScripts creates the VM management scripts
func (p *Provisioner) createManagementScripts(vmDir string, ui packer.Ui) error {
	ui.Say("Creating management scripts...")

	// Start script
	startScript := fmt.Sprintf(`#!/bin/bash
echo 'Starting VibeCode macOS VM with vfkit...'
vfkit \
  --cpus %d \
  --memory %d \
  --bootloader '%s' \
  --device 'virtio-blk,path=%s.qcow2' \
  --device 'virtio-net,%s' \
  --%s \
  --log-level '%s' &
echo $! > vm.pid
echo 'VM started with PID: $(cat vm.pid)'
`, p.config.CPUs, p.config.Memory, p.config.Bootloader, p.config.VMName, p.config.Network, p.config.Display, p.config.LogLevel)

	startPath := filepath.Join(vmDir, "start-vm.sh")
	if err := os.WriteFile(startPath, []byte(startScript), 0755); err != nil {
		return fmt.Errorf("failed to create start script: %v", err)
	}

	// Stop script
	stopScript := `#!/bin/bash
if [ -f vm.pid ]; then
  PID=$(cat vm.pid)
  if ps -p $PID > /dev/null; then
    kill $PID
    echo 'VM stopped'
  fi
  rm -f vm.pid
fi
`

	stopPath := filepath.Join(vmDir, "stop-vm.sh")
	if err := os.WriteFile(stopPath, []byte(stopScript), 0755); err != nil {
		return fmt.Errorf("failed to create stop script: %v", err)
	}

	// Status script
	statusScript := `#!/bin/bash
if [ -f vm.pid ]; then
  PID=$(cat vm.pid)
  if ps -p $PID > /dev/null; then
    echo 'VM is running (PID: $PID)'
  else
    echo 'VM is not running'
    rm -f vm.pid
  fi
else
  echo 'No VM PID file found'
fi
`

	statusPath := filepath.Join(vmDir, "status-vm.sh")
	if err := os.WriteFile(statusPath, []byte(statusScript), 0755); err != nil {
		return fmt.Errorf("failed to create status script: %v", err)
	}

	ui.Say("✅ Management scripts created")
	return nil
}

// createInstallationScript creates the VibeCode installation script
func (p *Provisioner) createInstallationScript(vmDir string, ui packer.Ui) error {
	ui.Say("Creating installation script...")

	installScript := `#!/bin/bash
echo 'Installing VibeCode dependencies in macOS VM...'

# Install Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Add Homebrew to PATH
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zshrc
eval "$(/opt/homebrew/bin/brew shellenv)"

# Install required packages
brew install node git curl wget
brew install code-server
brew install postgresql redis

# Install VibeCode
git clone https://github.com/ryanmaclean/vibecode-webgui.git
cd vibecode-webgui
npm install

# Start services
brew services start postgresql
brew services start redis

# Start VibeCode
code-server --bind-addr 0.0.0.0:8080 --auth none &

echo 'VibeCode installed and started!'
`

	installPath := filepath.Join(vmDir, "install-vibecode.sh")
	if err := os.WriteFile(installPath, []byte(installScript), 0755); err != nil {
		return fmt.Errorf("failed to create installation script: %v", err)
	}

	ui.Say("✅ Installation script created")
	return nil
}

// createREADME creates the README file
func (p *Provisioner) createREADME(vmDir string, ui packer.Ui) error {
	ui.Say("Creating README...")

	readme := fmt.Sprintf(`# VibeCode macOS vfkit VM

This VM was created using Packer and vfkit for optimal macOS virtualization.

## Usage

1. Start the VM:
   ./start-vm.sh

2. Install VibeCode (inside the VM):
   ./install-vibecode.sh

3. Access VibeCode at: http://localhost:8080

4. Stop the VM:
   ./stop-vm.sh

5. Check VM status:
   ./status-vm.sh

## Configuration

- Memory: %d MiB
- CPUs: %d
- Disk: %s
- macOS Version: %s

## Files

- vfkit-config.json: VM configuration
- %s.qcow2: VM disk image
- hardware-model: Hardware model file
- machine-id: Machine identifier
- aux-image: Auxiliary image file

`, p.config.Memory, p.config.CPUs, p.config.DiskSize, p.config.MacOSVersion, p.config.VMName)

	readmePath := filepath.Join(vmDir, "README.md")
	if err := os.WriteFile(readmePath, []byte(readme), 0644); err != nil {
		return fmt.Errorf("failed to create README: %v", err)
	}

	ui.Say("✅ README created")
	return nil
}
