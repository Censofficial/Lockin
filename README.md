# Lockin OS

A tiny 16-bit real-mode OS that boots from a floppy image and provides a simple command shell.

This is intentionally simple. MInimal filesystems, just a boot sector loader and a small kernel loaded from the first track.

## Requirements

- Windows PowerShell
- NASM (assembler) in PATH: https://www.nasm.us/
- Optional: QEMU in PATH to run the image: https://www.qemu.org/

## Build

1. Open PowerShell in the project root (`c:\Users\a\Desktop\Lockin`).
2. Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\build\build.ps1
```

This produces `build/lockinos.img` (1.44MB floppy image).

## Run (QEMU)

```powershell
qemu-system-i386 -fda .\build\lockinos.img
```



