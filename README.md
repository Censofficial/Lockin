# Lockin OS (minimal text shell)

A tiny 16-bit real-mode OS that boots from a floppy image and provides a simple command shell.

This is educational and intentionally simple. No filesystems, just a boot sector loader and a small kernel loaded from the first track.

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

You should see a prompt:

```
Lockin OS shell ready. Type 'help'
> 
```

Supported commands:

- help
- whoami
- date
- uptime
- about
- beep
- echo X
- color XY (hex attribute like 1E)
- pwd
- ls
- cd NAME | cd .. | cd /
- mkdir NAME
- rmdir NAME (only if empty)
- touch NAME
- rm NAME
- cat NAME (stub: no file contents yet)
- clear
- shutdown | halt
- restart | reboot

## Notes

- The bootloader loads at most 32 sectors (16 KiB) of kernel from the first track (contiguous after the boot sector). The build script enforces this size limit.
- No filesystem is used; the kernel is placed immediately after the boot sector inside the floppy image.
- Creating an ISO is unnecessary; most emulators/VMs boot floppy images directly. If you later want an ISO, we can add a tiny El Torito boot image wrapper.
