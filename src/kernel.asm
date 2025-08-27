; Lockin OS - Tiny 16-bit text shell kernel
; Loaded by bootloader at 0x1000:0000 and executed in real mode
; Assembles with: nasm -f bin src/kernel.asm -o build/kernel.bin

BITS 16
ORG 0x0000

; -------- Constants (must be defined before use) --------
CMD_BUF_SIZE       equ 128
MAX_DIRS           equ 32
NAME_LEN           equ 11      ; 10 chars + null
MAX_FILES          equ 64
FILE_CONTENT_SIZE  equ 64
STARTUP_CYCLES     equ 3
STARTUP_DOT_TICKS  equ 6

start:
  ; Setup segments
  mov ax, cs
  mov ds, ax
  mov es, ax
  mov ax, 0x9000
  mov ss, ax
  mov sp, 0xFFFE

  ; Boot menu first: choose between BIOS screen and Boot
  call show_boot_menu

  ; After Boot was chosen and loading delay shown, display banner
  mov si, msg_banner
  call puts
  mov si, msg_loaded
  call puts

  ; Capture boot ticks (CX:DX) using BIOS TOD (AH=00h)
  xor ax, ax
  int 0x1A
  mov [boot_ticks_lo], dx
  mov [boot_ticks_hi], cx

  ; Init RAM directory table (root only at start)
  call dirs_init

shell_loop:
  ; Prompt
  ; Ensure we start prompts at column 0
  call ensure_col0
  mov si, msg_prompt
  call puts_raw

  ; Read line into buffer
  mov di, cmd_buffer
  mov cx, CMD_BUF_SIZE
  call readline

  ; DI now points to 0-terminated string at cmd_buffer
  ; Trim leading spaces and set command pointer
  mov si, cmd_buffer
  call skip_spaces
  mov [cmdptr], si
  ; Belt-and-suspenders: ensure command output starts at column 0
  call ensure_col0
  ; If empty line, reprompt
  cmp byte [si], 0
  je shell_loop
  ; Check commands (case-insensitive; allow trailing spaces/args)
  ; help
  mov si, cmd_help
  mov di, [cmdptr]
  mov cx, 4
  call strncasecmp_ci
  jnc .chk_whoami
  mov di, [cmdptr]
  add di, 4
  mov al, [di]
  cmp al, 0
  je .do_help
  cmp al, ' '
  je .do_help
.chk_whoami:
  mov si, cmd_whoami
  mov di, [cmdptr]
  mov cx, 6
  call strncasecmp_ci
  jnc .chk_date
  mov di, [cmdptr]
  add di, 6
  mov al, [di]
  cmp al, 0
  je .do_whoami
  cmp al, ' '
  je .do_whoami
.chk_date:
  mov si, cmd_date
  mov di, [cmdptr]
  mov cx, 4
  call strncasecmp_ci
  jnc .chk_uptime
  mov di, [cmdptr]
  add di, 4
  mov al, [di]
  cmp al, 0
  je .do_date
  cmp al, ' '
  je .do_date
.chk_uptime:
  mov si, cmd_uptime
  mov di, [cmdptr]
  mov cx, 6
  call strncasecmp_ci
  jnc .chk_about
  mov di, [cmdptr]
  add di, 6
  mov al, [di]
  cmp al, 0
  je .do_uptime
  cmp al, ' '
  je .do_uptime
  ; 'ver' and 'info' removed; use 'about'
.chk_about:
  mov si, cmd_about
  mov di, [cmdptr]
  mov cx, 5
  call strncasecmp_ci
  jnc .chk_beep
  mov di, [cmdptr]
  add di, 5
  mov al, [di]
  cmp al, 0
  je .do_about
  cmp al, ' '
  je .do_about
.chk_beep:
  mov si, cmd_beep
  mov di, [cmdptr]
  mov cx, 4
  call strncasecmp_ci
  jnc .chk_clear
  mov di, [cmdptr]
  add di, 4
  mov al, [di]
  cmp al, 0
  je .do_beep
  cmp al, ' '
  je .do_beep
.chk_clear:
  mov si, cmd_clear
  mov di, [cmdptr]
  mov cx, 5
  call strncasecmp_ci
  jnc .chk_halt
  mov di, [cmdptr]
  add di, 5
  mov al, [di]
  cmp al, 0
  je .do_clear
  cmp al, ' '
  je .do_clear
.chk_halt:
  mov si, cmd_halt
  mov di, [cmdptr]
  mov cx, 4
  call strncasecmp_ci
  jnc .chk_shutdown
  mov di, [cmdptr]
  add di, 4
  mov al, [di]
  cmp al, 0
  je .do_halt
  cmp al, ' '
  je .do_halt
.chk_shutdown:
  mov si, cmd_shutdown
  mov di, [cmdptr]
  mov cx, 8
  call strncasecmp_ci
  jnc .chk_reboot
  mov di, [cmdptr]
  add di, 8
  mov al, [di]
  cmp al, 0
  je .do_halt
  cmp al, ' '
  je .do_halt
.chk_reboot:
  mov si, cmd_reboot
  mov di, [cmdptr]
  mov cx, 6
  call strncasecmp_ci
  jnc .chk_restart
  mov di, [cmdptr]
  add di, 6
  mov al, [di]
  cmp al, 0
  je .do_reboot
  cmp al, ' '
  je .do_reboot
.chk_restart:
  mov si, cmd_restart
  mov di, [cmdptr]
  mov cx, 7
  call strncasecmp_ci
  jnc .after_simple
  mov di, [cmdptr]
  add di, 7
  mov al, [di]
  cmp al, 0
  je .do_reboot
  cmp al, ' '
  je .do_reboot
.after_simple:
  mov si, cmd_echo
  mov di, [cmdptr]
  mov cx, 5
  call strncasecmp_ci
  jc .do_echo

  mov si, cmd_color
  mov di, [cmdptr]
  mov cx, 6
  call strncasecmp_ci
  jc .do_color

  mov si, cmd_pwd
  mov di, [cmdptr]
  call streq_ci
  jc .do_pwd

  mov si, cmd_ls
  mov di, [cmdptr]
  call streq_ci
  jc .do_ls

  mov si, cmd_cd
  mov di, [cmdptr]
  mov cx, 3
  call strncasecmp_ci
  jc .do_cd

  mov si, cmd_mkdir
  mov di, [cmdptr]
  mov cx, 6
  call strncasecmp_ci
  jc .do_mkdir

  mov si, cmd_rmdir
  mov di, [cmdptr]
  mov cx, 6
  call strncasecmp_ci
  jc .do_rmdir

  mov si, cmd_touch
  mov di, [cmdptr]
  mov cx, 6
  call strncasecmp_ci
  jc .do_touch

  mov si, cmd_rm
  mov di, [cmdptr]
  mov cx, 3
  call strncasecmp_ci
  jc .do_rm

  mov si, cmd_cat
  mov di, [cmdptr]
  mov cx, 4
  call strncasecmp_ci
  jc .do_cat

  ; write NAME TEXT
  mov si, cmd_write
  mov di, [cmdptr]
  mov cx, 6
  call strncasecmp_ci
  jc .do_write

  ; Unknown command
  mov si, msg_unknown
  call puts
  jmp shell_loop

  ; ----- missing command handlers (stubs) -----
.do_uptime:
  mov si, msg_not_impl
  call puts
  jmp shell_loop

.do_about:
  mov si, msg_banner
  call puts
  jmp shell_loop

.do_beep:
  mov ah, 0x0E
  mov bh, 0x00
  mov bl, [text_attr]
  mov al, 7           ; BEL
  int 0x10
  jmp shell_loop

.do_clear:
  call cls
  jmp shell_loop

.do_halt:
  mov si, msg_halt
  call puts
  cli
.halt_loop:
  hlt
  jmp .halt_loop

.do_reboot:
  mov si, msg_reboot
  call puts
  int 0x19
  jmp shell_loop

.do_echo:
  mov si, [cmdptr]
  add si, 5
  call skip_spaces
  call puts
  jmp shell_loop

.do_color:
  mov si, msg_not_impl
  call puts
  jmp shell_loop

.do_write:
  mov si, msg_not_impl
  call puts
  jmp shell_loop

.do_touch:
  mov si, [cmdptr]
  add si, 6
  call skip_spaces
  call token_to_temp
  jnc .touch_usage
  ; ensure not dir and not file exists
  mov bl, [current_dir]
  call find_child
  jc .touch_exists
  mov bl, [current_dir]
  call find_file_child
  jc .touch_exists
  ; alloc file
  call alloc_file
  jnc .touch_full
  mov bl, al
  mov byte [file_used+bx], 1
  mov al, [current_dir]
  mov [file_parent+bx], al
  call copy_temp_to_file
  mov si, msg_ok
  call puts
  jmp shell_loop
.touch_full:
  mov si, msg_full
  call puts
  jmp shell_loop
.touch_exists:
  mov si, msg_exists
  call puts
  jmp shell_loop
.touch_usage:
  mov si, msg_touch_usage
  call puts
  jmp shell_loop

.do_rm:
  mov si, [cmdptr]
  add si, 3
  call skip_spaces
  call token_to_temp
  jnc .rm_usage
  mov bl, [current_dir]
  call find_file_child
  jnc .rm_not_found
  ; delete
  mov bl, al
  mov byte [file_used+bx], 0
  mov si, msg_ok
  call puts
  jmp shell_loop
.rm_not_found:
  mov si, msg_not_found
  call puts
  jmp shell_loop
.rm_usage:
  mov si, msg_rm_usage
  call puts
  jmp shell_loop

.do_cat:
  mov si, [cmdptr]
  add si, 4
  call skip_spaces
  call token_to_temp
  jnc .cat_usage
  mov bl, [current_dir]
  call find_file_child
  jnc .cat_not_found
  ; AL has file index
  mov bl, al
  ; CX = size
  xor cx, cx
  mov si, file_size
  xor bh, bh
  add si, bx
  mov cl, [si]
  jcxz .cat_empty
  ; SI -> data buffer for this file
  call file_data_ptr
.cat_print_loop:
  lodsb
  mov ah, 0x0E
  mov bh, 0x00
  mov bl, [text_attr]
  int 0x10
  loop .cat_print_loop
  mov si, empty
  call puts
  jmp shell_loop
.cat_empty:
  mov si, msg_empty
  call puts
  jmp shell_loop
.cat_not_found:
  mov si, msg_not_found
  call puts
  jmp shell_loop
.cat_usage:
  mov si, msg_cat_usage
  call puts
  jmp shell_loop

.do_pwd:
  call print_pwd
  jmp shell_loop

.do_ls:
  ; reset ls_printed flag and counters
  mov byte [ls_printed], 0
  mov byte [dir_count], 0
  mov byte [file_count], 0
  call list_children
  call list_files
  ; if nothing printed, show (empty)
  cmp byte [ls_printed], 0
  jne .ls_done
  mov si, msg_empty
  call puts
.ls_done:
  ; print totals
  xor ax, ax
  mov al, [dir_count]
  call print_uint16
  mov si, msg_totals_dirs
  call puts_raw
  xor ax, ax
  mov al, [file_count]
  call print_uint16
  mov si, msg_totals_files
  call puts
  jmp shell_loop

.do_cd:
  mov si, [cmdptr]
  add si, 3
  call skip_spaces
  ; handle empty -> go to root
  mov al, [si]
  cmp al, 0
  je .cd_root
  ; determine starting directory
  mov bh, [current_dir]
  cmp byte [si], '/'
  jne .cd_loop_start
  ; start at root if path begins with '/'
  mov bh, 0
.cd_skip_slashes:
  cmp byte [si], '/'
  jne .cd_loop_start
  inc si
  jmp .cd_skip_slashes
.cd_loop_start:
  ; end or space -> finish
  mov al, [si]
  cmp al, 0
  je .cd_done_set
  cmp al, ' '
  je .cd_done_set
  ; read one segment token (stops at space or '/')
  call token_to_temp
  jnc .cd_usage
  ; handle '.' and '..'
  mov si, temp_name
  cmp byte [si], '.'
  jne .cd_name_seg
  cmp byte [si+1], '.'
  jne .cd_name_single
  cmp byte [si+2], 0
  jne .cd_name_seg
  ; ".." -> parent
  mov al, bh
  cmp al, 0
  je .cd_after_seg
  mov bl, al
  mov bh, [dir_parent+bx]
  jmp .cd_after_seg
.cd_name_single:
  cmp byte [si+1], 0
  jne .cd_name_seg
  ; "." -> no change
  jmp .cd_after_seg
.cd_name_seg:
  ; find child under BH
  mov bl, bh
  call find_child
  jnc .cd_not_found
  mov bh, al
.cd_after_seg:
  ; skip any '/' between segments
  call skip_spaces
  cmp byte [si], '/'
  jne .cd_loop_start
.cd_skip2:
  cmp byte [si], '/'
  jne .cd_loop_start
  inc si
  jmp .cd_skip2
.cd_root:
  mov byte [current_dir], 0
  jmp .cd_done_ok
.cd_done_set:
  mov [current_dir], bh
  jmp .cd_done_ok
.cd_not_found:
  mov si, msg_not_found
  call puts
  jmp shell_loop
.cd_usage:
  mov si, msg_cd_usage
  call puts
  jmp shell_loop
.cd_done_ok:
  mov si, msg_ok
  call puts
  jmp shell_loop

.do_mkdir:
  mov si, [cmdptr]
  add si, 6
  call skip_spaces
  call token_to_temp
  jnc .mkdir_usage
  ; ensure not exist
  mov bl, [current_dir]
  call find_child
  jc .mkdir_exists
  ; find free slot
  call alloc_dir
  jnc .mkdir_full
  ; set fields
  ; AL=index
  mov bl, al
  mov byte [dir_used+bx], 1
  mov al, [current_dir]
  mov [dir_parent+bx], al
  ; copy name from temp_name into dir_name[bl]
  call copy_temp_to_dir
  ; stay in current directory (do not auto-enter new one)
  mov si, msg_ok
  call puts
  jmp shell_loop
.mkdir_full:
  mov si, msg_full
  call puts
  jmp shell_loop
.mkdir_exists:
  mov si, msg_exists
  call puts
  jmp shell_loop
.mkdir_usage:
  mov si, msg_mkdir_usage
  call puts
  jmp shell_loop

.do_rmdir:
  mov si, [cmdptr]
  add si, 6
  call skip_spaces
  call token_to_temp
  jnc .rmdir_usage
  mov bl, [current_dir]
  call find_child
  jc .rmdir_found
  ; not found under current: if name matches current dir and not root, delete current
  mov al, [current_dir]
  cmp al, 0
  je .rmdir_not_found
  push ax
  mov bl, al
  call dir_index_to_ptr      ; SI -> current dir name
  mov di, temp_name
  call streq
  pop ax
  jnc .rmdir_not_found
  ; treat target as current_dir
  ; ensure empty (no children)
  push ax
  mov bl, al                 ; bl = current_dir
  call has_children
  pop ax
  jc .rmdir_not_empty
  ; ensure no files inside
  push ax
  mov bl, al
  call has_files
  pop ax
  jc .rmdir_not_empty
  ; set current to parent, then delete
  mov bl, al
  mov dl, [dir_parent+bx]
  mov [current_dir], dl
  mov byte [dir_used+bx], 0
  mov si, msg_ok
  call puts
  jmp shell_loop
.rmdir_found:
  ; ensure empty (no children)
  push ax
  mov bl, al           ; dir index
  call has_children    ; CF=1 if has children
  pop ax
  jc .rmdir_not_empty
  ; ensure no files under this dir
  push ax
  mov bl, al
  call has_files
  pop ax
  jc .rmdir_not_empty
  ; delete found child
  mov bl, al
  mov byte [dir_used+bx], 0
  mov si, msg_ok
  call puts
  jmp shell_loop
.rmdir_not_empty:
  mov si, msg_not_empty
  call puts
  jmp shell_loop
.rmdir_not_found:
  mov si, msg_not_found
  call puts
  jmp shell_loop
.rmdir_usage:
  mov si, msg_rmdir_usage
  call puts
  jmp shell_loop

.do_help:
  mov si, msg_help
  call puts_lines
  jmp shell_loop

.do_whoami:
  mov si, msg_user_prefix
  call puts_raw
  mov si, username
  call puts
  jmp shell_loop

.do_date:
  ; Robust RTC read via INT 1Ah with CF checks
.date_retry:
  mov ah, 0x04            ; get date (BCD)
  int 0x1A
  jc .date_retry
  mov [rtc_century], ch
  mov [rtc_year], cl
  mov [rtc_month], dh
  mov [rtc_day], dl
  mov ah, 0x02            ; get time (BCD)
  int 0x1A
  jc .date_retry
  mov [rtc_hour], ch
  mov [rtc_min], cl
  mov [rtc_sec], dh
  ; Print YYYY-MM-DD HH:MM:SS
  mov al, [rtc_century]
  call print_bcd2
  mov al, [rtc_year]
  call print_bcd2
  mov si, dash
  call puts_raw
  mov al, [rtc_month]
  call print_bcd2
  mov si, dash
  call puts_raw
  mov al, [rtc_day]
  call print_bcd2
  mov si, space
  call puts_raw
  mov al, [rtc_hour]
  call print_bcd2
  mov si, colon
  call puts_raw
  mov al, [rtc_min]
  call print_bcd2
  mov si, colon
  call puts_raw
  mov al, [rtc_sec]
  call print_bcd2
  mov si, empty
  call puts
  jmp shell_loop

; draw_menu: draw boot menu
draw_menu:
  pusha
  ; clear screen
  call cls
  ; Title centered-ish with inverse bar
  mov ah, 0x02
  mov bh, 0x00
  mov dx, (3<<8) | 20
  int 0x10
  ; swap attr -> highlight
  push ax
  mov al, [text_attr]
  push ax
  mov byte [text_attr], 0x70
  mov si, msg_menu_title
  call puts_raw
  pop ax
  mov [text_attr], al
  pop ax
  ; Box (wider and centered)
  mov ah, 0x02
  mov bh, 0x00
  mov dx, (9<<8) | 16
  int 0x10
  mov si, msg_box_top
  call puts_raw
  mov ah, 0x02
  mov dx, (10<<8) | 16
  int 0x10
  mov si, msg_box_empty
  call puts_raw
  mov ah, 0x02
  mov dx, (11<<8) | 16
  int 0x10
  mov si, msg_box_empty
  call puts_raw
  mov ah, 0x02
  mov dx, (12<<8) | 16
  int 0x10
  mov si, msg_box_empty
  call puts_raw
  mov ah, 0x02
  mov dx, (13<<8) | 16
  int 0x10
  mov si, msg_box_bottom
  call puts_raw
  ; Items inside box at fixed columns
  ; BIOS row 11, start col 18
  mov ah, 0x02
  mov bh, 0x00
  mov dx, (11<<8) | 18
  int 0x10
  mov al, [menu_sel]
  cmp al, 0
  jne .bios_norm
  push ax
  mov al, [text_attr]
  push ax
  mov byte [text_attr], 0x70 ; inverse highlight
  mov si, msg_item_bios_sel
  call puts_raw
  pop ax
  mov [text_attr], al
  pop ax
  jmp .after_bios
.bios_norm:
  mov si, msg_item_bios
  call puts_raw
.after_bios:
  ; BOOT row 12, start col 18
  mov ah, 0x02
  mov bh, 0x00
  mov dx, (12<<8) | 18
  int 0x10
  mov al, [menu_sel]
  cmp al, 1
  jne .boot_norm
  push ax
  mov al, [text_attr]
  push ax
  mov byte [text_attr], 0x70
  mov si, msg_item_boot_sel
  call puts_raw
  pop ax
  mov [text_attr], al
  pop ax
  jmp .after_boot
.boot_norm:
  mov si, msg_item_boot
  call puts_raw
.after_boot:
  ; Boot options line (static placeholder)
  mov ah, 0x02
  mov bh, 0x00
  mov dx, (19<<8) | 10
  int 0x10
  mov si, msg_boot_opts
  call puts_raw
  mov si, msg_boot_opts_value
  call puts
  ; Footer hints
  mov ah, 0x02
  mov bh, 0x00
  mov dx, (23<<8) | 6
  int 0x10
  mov si, msg_menu_hint
  call puts_raw
  popa
  ret

show_loading_and_wait:
  pusha
  call cls
  mov si, msg_loading
  call puts
  call wait_5s
  call cls
  popa
  ret

; Messages for directory actions
msg_ok db "OK",0
msg_full db "No space",0
msg_exists db "Already exists",0
msg_not_found db "Not found",0
msg_not_empty db "Not empty",0
msg_empty db "(empty)",0
msg_cd_usage db "Usage: cd NAME | cd .. | cd /",0
msg_mkdir_usage db "Usage: mkdir NAME",0
msg_rmdir_usage db "Usage: rmdir NAME",0
slash db "/",0

; Messages for file actions
msg_touch_usage db "Usage: touch NAME",0
msg_rm_usage db "Usage: rm NAME",0
msg_cat_usage db "Usage: cat NAME",0
msg_write_usage db "Usage: write NAME TEXT",0

; RAM directory storage
current_dir db 0
dir_used times MAX_DIRS db 0
dir_parent times MAX_DIRS db 0
dir_names times (MAX_DIRS*NAME_LEN) db 0
temp_name times NAME_LEN db 0
pwd_depth db 0

; RAM file storage (names only, no content for now)
file_used   times MAX_FILES db 0
file_parent times MAX_FILES db 0
file_names  times (MAX_FILES*NAME_LEN) db 0
file_size   times MAX_FILES db 0
file_data   times (MAX_FILES*FILE_CONTENT_SIZE) db 0

; temp flags
ls_printed db 0
dir_count db 0
file_count db 0

; totals labels for ls
msg_totals_dirs db " dirs, ",0
msg_totals_files db " files",0

; generic message
msg_not_impl db "(not implemented)",0

; =============================
; Minimal kernel support layer
; =============================

; --- global text attribute (foreground on black) ---
text_attr db 0x07

; --- general strings ---
crlf db 13,10,0
dash db "-",0
colon db ":",0
space db " ",0
empty db "",0

; --- banner and prompt ---
msg_banner db "LockinOS starting...",0
msg_prompt db "> ",0
msg_unknown db "Unknown command",0
msg_halt db "System halted.",0
msg_reboot db "Rebooting...",0

; --- boot timing ---
boot_ticks_lo dw 0
boot_ticks_hi dw 0

; --- command buffers and pointers ---
cmd_buffer times CMD_BUF_SIZE db 0
cmdptr dw 0

; --- RTC scratch ---
rtc_century db 0
rtc_year    db 0
rtc_month   db 0
rtc_day     db 0
rtc_hour    db 0
rtc_min     db 0
rtc_sec     db 0

; --- user info ---
msg_user_prefix db "User: ",0
username db "user",0

; --- help text ---
msg_help db "LockinOS shell (minimal build)",13,10
         db "Available commands:",13,10
         db "  help      - show this help",13,10
         db "  whoami    - show current user",13,10
         db "  date      - show RTC date/time",13,10
         db "  echo TEXT - print TEXT",13,10
         db "  clear     - clear screen",13,10
         db "  beep      - beep once",13,10
         db "  reboot    - reboot via BIOS",13,10
         db "  halt      - halt CPU",0

; --- menu state and strings ---
menu_sel db 0
msg_menu_title db "  Lockin OS Boot Menu  ",0
msg_box_top    db "+--------------------------+",0
msg_box_empty  db "|                          |",0
msg_box_bottom db "+--------------------------+",0
msg_item_bios      db "  Bios",0
msg_item_bios_sel  db "[ Bios ]",0
msg_item_boot      db "  Boot",0
msg_item_boot_sel  db "[ Boot ]",0
msg_boot_opts      db "Boot Options: ",0
msg_boot_opts_value db "(none)",0
msg_menu_hint db "Enter=Select  Up/Down=Move   I=Bios  B=Boot  ESC=Boot",0

; =============================
; Basic console routines
; =============================

cls:
  pusha
  mov ax, 0x0600
  mov bh, [text_attr]
  xor cx, cx
  mov dx, 0x184F
  int 0x10
  mov ah, 0x02
  xor dx, dx
  int 0x10
  popa
  ret

puts_raw: ; SI -> 0-terminated string
  pusha
.next:
  lodsb
  test al, al
  jz .done
  mov ah, 0x0E
  mov bh, 0x00
  mov bl, [text_attr]
  int 0x10
  jmp .next
.done:
  popa
  ret

puts: ; SI -> 0-terminated, then newline
  call puts_raw
  mov si, crlf
  call puts_raw
  ret

puts_lines:
  ; minimal: same as puts
  jmp puts

ensure_col0:
  ; set cursor to column 0 of current row
  pusha
  mov ah, 0x03      ; get cursor pos
  mov bh, 0x00
  int 0x10          ; returns DH=row, DL=col
  xor dl, dl        ; col = 0
  mov ah, 0x02
  mov bh, 0x00
  int 0x10
  popa
  ret

readline: ; DI=dest, CX=max
  pusha
  mov bx, di        ; BX = start
  dec cx            ; leave room for 0
.rl_wait:
  xor ax, ax
  int 0x16          ; wait key
  cmp al, 13        ; Enter
  je .rl_done
  cmp al, 8         ; Backspace
  jne .rl_char
  cmp di, bx        ; at start?
  je .rl_wait
  dec di
  inc cx
  ; erase on screen: BS, space, BS
  mov ah, 0x0E
  mov bh, 0x00
  mov bl, [text_attr]
  mov al, 8
  int 0x10
  mov al, ' '
  int 0x10
  mov al, 8
  int 0x10
  jmp .rl_wait
.rl_char:
  cmp cx, 0
  je .rl_wait       ; ignore when buffer full
  stosb             ; store AL
  dec cx
  ; echo
  mov ah, 0x0E
  mov bh, 0x00
  mov bl, [text_attr]
  int 0x10
  jmp .rl_wait
.rl_done:
  mov byte [di], 0
  popa
  ret

skip_spaces: ; SI -> skip space chars (updates SI)
.ss_loop:
  mov al, [si]
  cmp al, ' '
  jne .ss_done
  inc si
  jmp .ss_loop
.ss_done:
  ret

; streq_ci: compare SI and DI case-insensitive; CF=1 if equal
streq_ci:
  push ax
  push bx
.ci_loop:
  mov al, [si]
  mov bl, [di]
  ; to upper AL
  cmp al, 'a'
  jb .al_ok
  cmp al, 'z'
  ja .al_ok
  sub al, 32
.al_ok:
  ; to upper BL
  cmp bl, 'a'
  jb .bl_ok
  cmp bl, 'z'
  ja .bl_ok
  sub bl, 32
.bl_ok:
  cmp al, bl
  jne .ci_ne
  cmp al, 0
  je .ci_eq
  inc si
  inc di
  jmp .ci_loop
.ci_eq:
  stc
  pop bx
  pop ax
  ret
.ci_ne:
  clc
  pop bx
  pop ax
  ret

; strncasecmp_ci: compare up to CX chars case-insensitive; CF=1 if first CX match
strncasecmp_ci:
  push ax
  push bx
.nci_loop:
  cmp cx, 0
  je .nci_eq
  mov al, [si]
  mov bl, [di]
  ; to upper AL
  cmp al, 'a'
  jb .nci_al_ok
  cmp al, 'z'
  ja .nci_al_ok
  sub al, 32
.nci_al_ok:
  ; to upper BL
  cmp bl, 'a'
  jb .nci_bl_ok
  cmp bl, 'z'
  ja .nci_bl_ok
  sub bl, 32
.nci_bl_ok:
  cmp al, bl
  jne .nci_ne
  inc si
  inc di
  dec cx
  jmp .nci_loop
.nci_eq:
  stc
  pop bx
  pop ax
  ret
.nci_ne:
  clc
  pop bx
  pop ax
  ret

; streq: case-sensitive equality; CF=1 if equal
streq:
  push ax
.cs_loop:
  mov al, [si]
  cmp al, [di]
  jne .cs_ne
  cmp al, 0
  je .cs_eq
  inc si
  inc di
  jmp .cs_loop
.cs_eq:
  stc
  pop ax
  ret
.cs_ne:
  clc
  pop ax
  ret

; Print AX as unsigned decimal
print_uint16:
  pusha
  mov bx, 10
  mov cx, 0           ; count
  mov dx, 0
  mov si, numbuf+5    ; end of buffer
.pu_loop:
  xor dx, dx
  div bx              ; AX /= 10, remainder in DX
  add dl, '0'
  dec si
  mov [si], dl
  inc cx
  test ax, ax
  jnz .pu_loop
  ; output CX digits at SI
.pu_out:
  lodsb
  mov ah, 0x0E
  mov bh, 0x00
  mov bl, [text_attr]
  int 0x10
  loop .pu_out
  popa
  ret

; Print AL as two BCD digits
print_bcd2:
  pusha
  mov ah, al
  and ah, 0x0F       ; low nibble
  mov bl, al
  and bl, 0xF0       ; high nibble
  shr bl, 4
  add bl, '0'
  mov al, bl
  mov ah, 0x0E
  mov bh, 0x00
  mov bl, [text_attr]
  int 0x10
  mov al, ah
  add al, '0'
  mov ah, 0x0E
  mov bh, 0x00
  mov bl, [text_attr]
  int 0x10
  popa
  ret

; =============================
; Minimal FS/dir stubs (no-op)
; =============================

dirs_init: ret
find_child: clc 
  ret
find_file_child: clc 
  ret
alloc_file: clc 
  ret
copy_temp_to_file: ret
alloc_dir: clc 
  ret
copy_temp_to_dir: ret
dir_index_to_ptr: ret
has_children: clc 
  ret
has_files: clc 
  ret
list_children: ret
list_files: ret
file_data_ptr: ret
print_pwd: ret
token_to_temp:
  stc
  ret
; numeric buffer for print_uint16 (max 5 digits)
numbuf times 6 db 0

; =============================
; Splash, waits, boot menu, BIOS screen
; =============================

show_startup:
  pusha
  mov si, msg_banner
  call puts_raw
  mov bp, STARTUP_CYCLES
.cycle:
  mov cx, 3
.appear:
  mov ah, 0x0E
  mov bh, 0x00
  mov bl, [text_attr]
  mov al, '.'
  int 0x10
  mov al, STARTUP_DOT_TICKS
  call wait_ticks
  loop .appear
  mov cx, 3
.erase:
  mov ah, 0x0E
  mov al, 8
  mov bh, 0x00
  mov bl, [text_attr]
  int 0x10
  mov al, ' '
  int 0x10
  mov al, 8
  int 0x10
  mov al, STARTUP_DOT_TICKS
  call wait_ticks
  loop .erase
  dec bp
  jnz .cycle
  call wait_5s
  call cls
  popa
  ret

; Wait AL ticks (~55 ms each)
wait_ticks:
  pusha
  xor ah, ah
  int 0x1A            ; CX:DX = ticks
  add dx, ax          ; add AL ticks (AH is 0)
.wt_loop:
  int 0x1A
  cmp dx, ax          ; compare low word only
  jb .wt_loop
  popa
  ret

wait_5s:
  push ax
  push bx
  push cx
  push dx
  mov ah, 0x86
  mov cx, 0x004C
  mov dx, 0x4B40
  int 0x15
  jc .fallback
  pop dx
  pop cx
  pop bx
  pop ax
  ret
.fallback:
  mov al, 91
  call wait_ticks
  pop dx
  pop cx
  pop bx
  pop ax
  ret

show_boot_menu:
  pusha
  mov byte [menu_sel], 0
.redraw:
  call draw_menu
.keyloop:
  xor ax, ax
  int 0x16
  cmp al, 13
  je .enter
  cmp al, 27
  je .esc
  cmp al, 'b'
  je .do_boot
  cmp al, 'B'
  je .do_boot
  cmp al, 'i'
  je .do_bios
  cmp al, 'I'
  je .do_bios
  cmp al, 0
  jne .keyloop
  cmp ah, 0x48
  jne .chk_down
  mov bl, [menu_sel]
  dec bl
  and bl, 1
  mov [menu_sel], bl
  jmp .redraw
.chk_down:
  cmp ah, 0x50
  jne .keyloop
  mov bl, [menu_sel]
  inc bl
  and bl, 1
  mov [menu_sel], bl
  jmp .redraw
.enter:
  cmp byte [menu_sel], 0
  je .do_bios
  jmp .do_boot
.esc:
  jmp .do_boot
.do_bios:
  call bios_screen
  jmp .redraw
.do_boot:
  call show_loading_and_wait
  popa
  ret

bios_screen:
  pusha
  ; set text_attr to blue bg, bright white
  push ax
  mov al, [text_attr]
  push ax
  mov byte [text_attr], 0x1F
  call cls
  ; header
  mov ah, 0x02
  mov bh, 0x00
  mov dx, (1<<8) | 2
  int 0x10
  mov si, msg_bios_title
  call puts
  ; conventional memory
  mov ah, 0x02
  mov dx, (3<<8) | 4
  int 0x10
  mov si, msg_mem
  call puts_raw
  int 0x12             ; AX = KB of conventional memory
  call print_uint16
  mov si, msg_kb
  call puts
  ; date/time
  mov ah, 0x02
  mov dx, (5<<8) | 4
  int 0x10
  mov si, msg_date
  call puts_raw
  ; read RTC date/time (robust)
.rtc_retry:
  mov ah, 0x04
  int 0x1A
  jc .rtc_retry
  mov [rtc_century], ch
  mov [rtc_year], cl
  mov [rtc_month], dh
  mov [rtc_day], dl
  mov ah, 0x02
  int 0x1A
  jc .rtc_retry
  mov [rtc_hour], ch
  mov [rtc_min], cl
  mov [rtc_sec], dh
  ; print YYYY-MM-DD
  mov al, [rtc_century]
  call print_bcd2
  mov al, [rtc_year]
  call print_bcd2
  mov si, dash
  call puts_raw
  mov al, [rtc_month]
  call print_bcd2
  mov si, dash
  call puts_raw
  mov al, [rtc_day]
  call print_bcd2
  ; time line
  mov ah, 0x02
  mov dx, (6<<8) | 4
  int 0x10
  mov si, msg_time
  call puts_raw
  mov al, [rtc_hour]
  call print_bcd2
  mov si, colon
  call puts_raw
  mov al, [rtc_min]
  call print_bcd2
  mov si, colon
  call puts_raw
  mov al, [rtc_sec]
  call print_bcd2
  mov si, empty
  call puts
  ; OS info
  mov ah, 0x02
  mov dx, (8<<8) | 4
  int 0x10
  mov si, msg_os
  call puts
  ; footer/hints
  mov ah, 0x02
  mov dx, (22<<8) | 2
  int 0x10
  mov si, msg_menu_hint
  call puts
  ; wait for ESC
.wait:
  xor ax, ax
  int 0x16
  cmp al, 27
  jne .wait
  pop ax
  mov [text_attr], al
  popa
  ret

; --- command strings to satisfy references ---
msg_loading db "Loading...",0
msg_loaded db "Loaded successfully. Type 'help'",0
msg_bios_title db "LockinOS BIOS Information",0
msg_mem db "Conventional memory: ",0
msg_kb db " KB",0
msg_date db "Date: ",0
msg_time db "Time: ",0
msg_os db "OS: LockinOS (minimal build)",0
cmd_help db "help",0
cmd_whoami db "whoami",0
cmd_date db "date",0
cmd_uptime db "uptime",0
cmd_about db "about",0
cmd_beep db "beep",0
cmd_clear db "clear",0
cmd_halt db "halt",0
cmd_shutdown db "shutdown",0
cmd_reboot db "reboot",0
cmd_restart db "restart",0
cmd_echo db "echo ",0
cmd_color db "color ",0
cmd_pwd db "pwd",0
cmd_ls db "ls",0
cmd_cd db "cd ",0
cmd_mkdir db "mkdir ",0
cmd_rmdir db "rmdir ",0
cmd_touch db "touch ",0
cmd_rm db "rm ",0
cmd_cat db "cat ",0
cmd_write db "write ",0
