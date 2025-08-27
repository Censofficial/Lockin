# Build script for Lockin OS (Windows PowerShell)
# Requires: NASM in PATH
# Optional: QEMU in PATH to run the OS

$ErrorActionPreference = 'Stop'

# Paths
$root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$proj    = Split-Path -Parent $root
$src     = Join-Path $proj 'src'
$outdir  = Join-Path $proj 'build'
$bootBin = Join-Path $outdir 'boot.bin'
$kernBin = Join-Path $outdir 'kernel.bin'
$image   = Join-Path $outdir 'lockinos.img'

# Tools
function Require-Tool($name) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        throw "Required tool '$name' not found in PATH. Please install it."
    }
}

# File locking
function Test-FileLocked($path) {
    if (-not (Test-Path $path)) { return $false }
    try {
        $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
        $fs.Close()
        return $false
    } catch { return $true }
}

# Remove with retry
function Remove-FileWithRetry($path, $retries = 5, $delayMs = 500) {
    if (-not (Test-Path $path)) { return }
    for ($i = 0; $i -lt $retries; $i++) {
        try {
            Remove-Item -LiteralPath $path -Force -ErrorAction Stop
            return
        } catch {
            if ($i -lt ($retries - 1)) { Start-Sleep -Milliseconds $delayMs } 
            else { Write-Warning "Could not delete '$path': $($_.Exception.Message). Close any process using it and retry." }
        }
    }
}

# Ensure output directory
if (-not (Test-Path $outdir)) { New-Item -ItemType Directory -Path $outdir | Out-Null }

# Cleanup old artifacts
foreach ($f in @($bootBin, $kernBin, $image)) { Remove-FileWithRetry $f }

# Check tools
Write-Host "[1/4] Checking tools..."
Require-Tool nasm

# Assemble bootloader
Write-Host "[2/4] Assembling bootloader..."
$bootAsm = Join-Path $src 'boot.asm'
& nasm -f bin $bootAsm -o $bootBin

# Assemble kernel
Write-Host "[3/4] Assembling kernel..."
$kernelAsm = Join-Path $src 'kernel.asm'
& nasm -f bin $kernelAsm -o $kernBin

# Validate boot sector
$bootBytes = [IO.File]::ReadAllBytes($bootBin)
if ($bootBytes.Length -ne 512) {
    Write-Warning "Boot sector is $($bootBytes.Length) bytes. Padding/truncating to 512."
    $bootFixed = New-Object byte[] 512
    [Array]::Copy($bootBytes, $bootFixed, [Math]::Min(512, $bootBytes.Length))
    $bootFixed[510] = 0x55
    $bootFixed[511] = 0xAA
    $bootBytes = $bootFixed
}

# Validate kernel size
$kernBytes = [IO.File]::ReadAllBytes($kernBin)
$maxSectors = 32
$maxBytes = 512 * $maxSectors
if ($kernBytes.Length -gt $maxBytes) {
    throw "Kernel too large ($($kernBytes.Length) bytes). Max supported: $maxBytes bytes ($maxSectors sectors)."
}

# Create floppy image
Write-Host "[4/4] Creating floppy image..."
if (Test-FileLocked $image) {
    throw "Target image '$image' is locked by another process. Close any emulator using it."
}

$floppySize = 1474560 # 1.44MB
$imgBytes = New-Object byte[] $floppySize
[Array]::Copy($bootBytes, 0, $imgBytes, 0, 512)
[Array]::Copy($kernBytes, 0, $imgBytes, 512, $kernBytes.Length)

[IO.File]::WriteAllBytes($image, $imgBytes)
Write-Host "Done. Image: $image"

Write-Host "`nRun with QEMU (if installed):"
Write-Host "  qemu-system-i386 -fda `"$image`""
