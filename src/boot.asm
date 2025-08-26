; Lockin OS - Minimal Bootloader (16-bit real mode)
; Loads a tiny kernel from the first floppy track and jumps to it
; Assembles with: nasm -f bin src/boot.asm -o build/boot.bin

BITS 16
ORG 0x7C00

start:
  cli
  xor ax, ax
  mov ds, ax
  mov es, ax
  mov ss, ax
  mov sp, 0x7C00
  sti

  ; Remember BIOS drive number in DL (already set by BIOS)
  mov [boot_drive], dl

  ; Show message
  mov si, msg_loading
  call print_string

  ; Load kernel to 0x1000:0000 (paragraph 0x1000)
  mov ax, 0x1000
  mov es, ax
  xor bx, bx

  ; Prepare CHS start at C=0, H=0, S=2 and read KERNEL_SECTORS one-by-one
  xor ch, ch             ; cylinder = 0
  xor dh, dh             ; head = 0
  mov cl, 2              ; sector = 2 (boot is sector 1)
  mov si, KERNEL_SECTORS ; remaining sectors

.read_next_sector:
  cmp si, 0
  je .done_read
  ; Try read sector with up to 3 retries
  mov di, 3
.try_sector:
  mov dl, [boot_drive]
  mov ah, 0x02           ; Read sectors
  mov al, 1              ; one sector
  int 0x13
  jnc .sector_ok
  ; reset disk and retry
  mov ah, 0x00
  int 0x13
  dec di
  jnz .try_sector
  jmp disk_error
.sector_ok:
  ; advance destination ES by 512 bytes (32 paragraphs)
  push ax
  mov ax, es
  add ax, 32
  mov es, ax
  pop ax
  ; advance CHS: next sector, handle track/head rollover (18 spt, 2 heads)
  inc cl                 ; next sector
  cmp cl, 19             ; past sector 18?
  jb .chs_done
  mov cl, 1              ; sector back to 1
  xor dh, 1              ; toggle head 0<->1
  cmp dh, 0
  jne .chs_done
  inc ch                 ; after head 1 -> next cylinder
.chs_done:
  dec si
  jmp .read_next_sector

.done_read:

  ; Far jump to loaded kernel at 0x1000:0000
  jmp 0x1000:0x0000

; ----------------------------------------
; print_string: prints 0-terminated string at DS:SI using BIOS teletype
; ----------------------------------------
print_string:
  pusha
.print_char:
  lodsb
  test al, al
  jz .done
  mov ah, 0x0E
  mov bh, 0x00
  mov bl, 0x07
  int 0x10
  jmp .print_char
.done:
  popa
  ret

; ----------------------------------------
; disk_error: show message and halt
; ----------------------------------------
disk_error:
  mov si, msg_disk
  call print_string
.hang:
  cli
  hlt
  jmp .hang

; ----------------------------------------
; Data
; ----------------------------------------
KERNEL_SECTORS equ 32 ; Max sectors to load (boot script enforces size)

boot_drive db 0
msg_loading db "Lockin OS booting... loading kernel", 13, 10, 0
msg_disk    db "Disk read error. Halt.", 13, 10, 0

; Pad boot sector to 512 bytes and add boot signature 0xAA55
TIMES 510-($-$$) db 0
DW 0xAA55
