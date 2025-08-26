; Lockin OS - Tiny 16-bit text shell kernel
; Loaded by bootloader at 0x1000:0000 and executed in real mode
; Assembles with: nasm -f bin src/kernel.asm -o build/kernel.bin

BITS 16
ORG 0x0000

start:
  ; Setup segments
  mov ax, cs
  mov ds, ax
  mov es, ax
  mov ax, 0x9000
  mov ss, ax
  mov sp, 0xFFFE

  ; Clear screen
  call cls

  ; Startup animation before banner
  call show_startup

  ; Banner
  mov si, msg_banner
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
  ; Check commands (case-insensitive)
  mov si, cmd_help
  mov di, [cmdptr]
  call streq_ci
  jc .do_help

  mov si, cmd_whoami
  mov di, [cmdptr]
  call streq_ci
  jc .do_whoami

  mov si, cmd_date
  mov di, [cmdptr]
  call streq_ci
  jc .do_date

  mov si, cmd_uptime
  mov di, [cmdptr]
  call streq_ci
  jc .do_uptime

  ; 'ver' and 'info' removed; use 'about'
  mov si, cmd_about
  mov di, [cmdptr]
  call streq_ci
  jc .do_about

  mov si, cmd_beep
  mov di, [cmdptr]
  call streq_ci
  jc .do_beep

  mov si, cmd_clear
  mov di, [cmdptr]
  call streq_ci
  jc .do_clear

  mov si, cmd_halt
  mov di, [cmdptr]
  call streq_ci
  jc .do_halt

  mov si, cmd_shutdown
  mov di, [cmdptr]
  call streq_ci
  jc .do_halt

  mov si, cmd_reboot
  mov di, [cmdptr]
  call streq_ci
  jc .do_reboot

  mov si, cmd_restart
  mov di, [cmdptr]
  call streq_ci
  jc .do_reboot

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

.do_uptime:
  ; Get current ticks CX:DX, compute delta from boot_ticks
  xor ax, ax
  int 0x1A
  ; delta = (CX:DX) - (boot_ticks_hi:boot_ticks_lo)
  sub dx, [boot_ticks_lo]
  sbb cx, [boot_ticks_hi]
  ; Convert to seconds: delta / 18 (approx)
  xor ax, ax        ; AX will hold seconds
  mov bx, 18
.upt_loop:
  ; compare CX:DX with 0
  mov si, cx
  or si, dx
  jz .upt_done
  ; if CX:DX < 18 then done
  cmp cx, 0
  jne .upt_ge
  cmp dx, bx
  jb .upt_done
.upt_ge:
  ; subtract 18 from DX (low word), borrow from CX
  sub dx, bx
  sbb cx, 0
  inc ax
  jmp .upt_loop
.upt_done:
  ; Print 'Uptime: ' and seconds 's'
  mov si, msg_uptime
  call puts_raw
  push ax
  call print_uint16
  mov si, letter_s
  call puts_raw
  ; print human-readable form: (H:M:S)
  mov si, space
  call puts_raw
  mov si, lparen
  call puts_raw
  ; retrieve seconds
  pop ax
  xor dx, dx
  mov bx, 3600
  div bx                 ; AX=H, DX=rem
  push ax                ; save H
  mov ax, dx             ; rem
  xor dx, dx
  mov bx, 60
  div bx                 ; AX=M, DX=S
  ; print H
  pop cx
  mov ax, cx
  call print_uint16
  mov si, colon
  call puts_raw
  ; print M
  ; AX already M
  call print_uint16
  mov si, colon
  call puts_raw
  ; print S
  mov ax, dx
  call print_uint16
  mov si, rparen
  call puts
  jmp shell_loop

.do_about:
  mov si, msg_about
  call puts
  jmp shell_loop

.do_beep:
  ; ASCII bell
  mov ah, 0x0E
  mov bh, 0x00
  mov bl, [text_attr]
  mov al, 7
  int 0x10
  ; newline
  mov ax, 0x0E0D
  mov bx, 0x0000
  mov bl, [text_attr]
  int 0x10
  mov al, 0x0A
  int 0x10
  jmp shell_loop

.do_halt:
  cli
.halt_loop:
  hlt
  jmp .halt_loop

.do_reboot:
  ; Try warm boot via BIOS
  int 0x19
  jmp .do_halt

.do_echo:
  ; Skip "echo " (5 bytes) and print remainder until 0
  mov si, [cmdptr]
  add si, 5
  call puts
  jmp shell_loop

.do_color:
  ; Expect two hex digits after optional spaces: color XY
  mov si, [cmdptr]
  add si, 6
  call skip_spaces
  ; Need at least two chars
  push si
  lodsb
  test al, al
  jz .color_usage_pop
  lodsb
  test al, al
  jz .color_usage_pop
  ; Back SI to start of two digits
  pop si
  call parse_hex_byte ; AL=val, CF=1 ok
  jnc .color_usage
  mov [text_attr], al
  ; Recolor existing screen with the new attribute
  call repaint_screen
  mov si, msg_color_set
  call puts
  jmp shell_loop
.color_usage:
  mov si, msg_color_usage
  call puts
  jmp shell_loop
; ensure SI stack balance on early usage branch
.color_usage_pop:
  pop si
  jmp .color_usage

; clear screen handler
.do_clear:
  call cls
  jmp shell_loop

.do_write:
  ; Parse: write NAME TEXT... (create if not exists, overwrite content)
  mov si, [cmdptr]
  add si, 6
  call skip_spaces
  ; first token is NAME -> temp_name
  call token_to_temp
  jnc .write_usage
  ; SI now at after NAME, can point to TEXT after skipping spaces
  call skip_spaces
  ; Find or create file under current_dir
  mov bl, [current_dir]
  call find_file_child
  jc .write_have_index
  ; not found -> create
  call alloc_file
  jnc .write_no_space
  mov bl, al
  mov byte [file_used+bx], 1
  mov al, [current_dir]
  mov [file_parent+bx], al
  call copy_temp_to_file
.write_have_index:
  ; BL must be file index
  ; Copy TEXT (at DS:SI) into file data up to FILE_CONTENT_SIZE
  push si
  push bx
  call file_data_ptr    ; SI -> data buffer
  mov di, si            ; DI = dest
  pop bx
  pop si                ; SI = source text
  mov cx, FILE_CONTENT_SIZE
  xor ah, ah            ; count actually written in AH
.w_copy:
  cmp cx, 0
  je .w_done_copy
  ; Stop if end of line (0 encountered). Our line buffer is 0-terminated.
  mov al, [si]
  cmp al, 0
  je .w_done_copy
  ; store and advance
  stosb
  inc si
  inc ah
  dec cx
  jmp .w_copy
.w_done_copy:
  ; Update size
  mov si, file_size
  xor bh, bh
  add si, bx
  mov [si], ah
  mov si, msg_ok
  call puts
  jmp shell_loop
.write_no_space:
  mov si, msg_full
  call puts
  jmp shell_loop
.write_usage:
  mov si, msg_write_usage
  call puts
  jmp shell_loop

; wait_ticks: wait AL BIOS ticks (~18.2 Hz)
wait_ticks:
  push ax
  push bx
  push cx
  push dx
  xor ah, ah
  int 0x1A          ; CX:DX current ticks, we use DX
  mov bx, dx        ; start
.wt_loop:
  xor ah, ah
  int 0x1A
  mov cx, dx
  sub cx, bx        ; elapsed (wrap ignored for small waits)
  cmp cl, al        ; compare low byte
  jb .wt_loop
  pop dx
  pop cx
  pop bx
  pop ax
  ret

; ensure_col0: if cursor column != 0, move to next line (using newline)
ensure_col0:
  pusha
  mov ah, 0x03
  mov bh, 0x00
  int 0x10
  cmp dl, 0
  je .ok
  ; Force cursor to column 0 on the same row
  mov ah, 0x02
  mov bh, 0x00
  xor dl, dl          ; col 0
  int 0x10
.ok:
  popa
  ret

; show_startup: prints startup text and animates three dots appearing/disappearing
show_startup:
  pusha
  mov si, msg_startup
  call puts_raw
  ; two cycles of appear 3 dots then erase 3 dots
  mov bp, STARTUP_CYCLES
.cycle:
  ; appear 3 dots
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
  ; erase 3 dots (backspace-space-backspace)
  mov cx, 3
.erase:
  mov ah, 0x0E
  mov al, 8          ; BS
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
  ; clear screen after animation so startup text doesn't persist
  call cls
  popa
  ret

; newline: advance to next line honoring current text_attr and custom scroll
newline:
  pusha
  ; Get cursor position
  mov ah, 0x03
  mov bh, 0x00
  int 0x10              ; DH=row (0-24), DL=col
.nl_check_last:
  cmp dh, 24
  jb .nl_move_next
  ; At last row: perform scroll up 1 line with our attribute
  mov ax, 0x0601        ; AH=06 scroll up, AL=1 line
  mov bh, [text_attr]   ; fill attribute
  mov cx, 0x0000        ; top-left
  mov dx, 0x184F        ; bottom-right
  int 0x10
  ; Move cursor to col 0 of last row
  mov ah, 0x02
  mov bh, 0x00
  mov dx, 0x1840        ; row 24, col 0
  int 0x10
  jmp .nl_done
.nl_move_next:
  ; Move cursor explicitly to next line, col 0
  inc dh                 ; next row
  mov dl, 0              ; col 0
  mov ah, 0x02
  mov bh, 0x00
  int 0x10
.nl_done:
  popa
  ret

; puts: print 0-terminated string at DS:SI, then CRLF
puts:
  pusha
  call puts_raw
  ; Clear remainder of the line to avoid leftover characters from previous content
  call clear_eol
  call newline
  popa
  ret

; puts_raw: print 0-terminated string without CRLF
puts_raw:
  pusha
.pr:
  lodsb
  test al, al
  jz .prd
  mov ah, 0x0E
  mov bh, 0x00
  mov bl, [text_attr]
  int 0x10
  jmp .pr
.prd:
  popa
  ret

; clear_eol: clear from current cursor position to end of line using current text_attr
clear_eol:
  pusha
  ; Get current cursor position -> DL = col
  mov ah, 0x03
  mov bh, 0x00
  int 0x10
  ; CX = 80 - DL
  xor cx, cx
  mov cl, 80
  sub cl, dl
  jz .ce_done
  ; Write spaces with attribute, count in CX
  mov ah, 0x09
  mov al, ' '
  mov bh, 0x00
  mov bl, [text_attr]
  int 0x10
.ce_done:
  popa
  ret

; puts_lines: print sequence of 0-terminated strings at DS:SI until an extra 0 byte
; Layout: "line1",0,"line2",0,...,0
puts_lines:
  pusha
.pl_loop:
  cmp byte [si], 0
  je .pl_done
  ; Save start of this line
  mov di, si
  ; Anchor each line to column 0 before printing
  call ensure_col0
  call puts_raw
  call clear_eol
  call newline
  ; Restore start into SI, then advance to next string (past terminating 0)
  mov si, di
.pl_advance:
  lodsb
  test al, al
  jnz .pl_advance
  jmp .pl_loop
.pl_done:
  popa
  ret

; cls: clear screen using BIOS scroll up function
cls:
  pusha
  mov ax, 0x0600
  mov bh, [text_attr]
  mov cx, 0x0000
  mov dx, 0x184F
  int 0x10
  ; Move cursor to 0,0
  mov ah, 0x02
  mov bh, 0x00
  mov dx, 0x0000
  int 0x10
  popa
  ret

; repaint_screen: set attribute of all 80x25 cells to current text_attr, preserving characters
repaint_screen:
  pusha
  push ds
  push es
  ; Save current cursor position (DH=row, DL=col)
  mov ah, 0x03
  mov bh, 0x00
  int 0x10
  push dx                 ; save cursor pos
  mov ax, 0xB800
  mov es, ax
  xor di, di
  cld
  mov cx, 2000          ; 80*25 cells
.rs_loop:
  ; Skip character byte
  inc di
  ; Write attribute
  mov al, [text_attr]
  stosb                 ; store at ES:DI, then DI++ (attributes position)
  ; Next cell
  loop .rs_loop
  ; Restore cursor position
  pop dx
  mov ah, 0x02
  mov bh, 0x00
  int 0x10
  pop es
  pop ds
  popa
  ret

; readline: reads a line into ES:DI? We'll use DS:DI, max length in CX. Null-terminated.
; Simple editing: backspace, enter; echoes characters.
readline:
  pusha
  ; We'll keep pointer in DI, count in CX
  xor ax, ax
  mov [rl_start], di     ; remember buffer start safely
.rl_loop:
  ; get key
  xor ax, ax
  int 0x16       ; AH=0, wait keystroke -> AL
  cmp al, 13     ; Enter
  je .enter
  cmp al, 8      ; Backspace
  je .backspace
  cmp al, 27     ; ESC -> clear line
  je .esc
  ; printable?
  cmp al, ' '
  jb .rl_loop
  ; If buffer full (leave space for null)
  cmp cx, 1
  jbe .rl_loop
  ; store and echo
  stosb
  dec cx
  ; echo char
  mov ah, 0x0E
  mov bh, 0x00
  mov bl, [text_attr]
  int 0x10
  jmp .rl_loop

.backspace:
  mov ax, [rl_start]
  cmp di, ax
  jbe .rl_loop
  dec di
  inc cx
  ; move cursor back and erase char visually
  mov ah, 0x0E
  mov al, 8
  mov bh, 0x00
  mov bl, [text_attr]
  int 0x10
  mov al, ' '
  int 0x10
  mov al, 8
  int 0x10
  jmp .rl_loop

.esc:
  ; Clear current line: move cursor to col 0, print CR, then spaces
  ; Simpler: emit CRLF and reprint prompt
  call newline
  ; Reset DI and CX
  mov di, [rl_start]
  mov cx, CMD_BUF_SIZE
  ; Reprint prompt
  mov si, msg_prompt
  call puts_raw
  jmp .rl_loop

.enter:
  ; Null-terminate
  mov al, 0
  stosb
  ; Newline
  call newline
  popa
  ret

; streq: compare DS:SI and DS:DI strings for equality (0-terminated)
; sets CF=1 if equal, CF=0 if not
streq:
  push ax
  push si
  push di
.cmp:
  lodsb
  scasb
  jne .noteq
  test al, al
  jnz .cmp
  ; both zero at same time -> equal
  stc
  jmp .done
.noteq:
  clc
.done:
  pop di
  pop si
  pop ax
  ret

; strncmp: compare first CX bytes of DS:SI and DS:DI; sets CF=1 if equal
strncmp:
  push ax
  push si
  push di
.cmpn:
  cmp cx, 0
  je .eq
  mov al, [si]
  mov ah, [di]
  cmp al, ah
  jne .noteq
  inc si
  inc di
  dec cx
  jmp .cmpn
.eq:
  stc
  jmp .dn
.noteq:
  clc
.dn:
  pop di
  pop si
  pop ax
  ret

; print_bcd2: print 2 digits from BCD byte in AL
print_bcd2:
  push ax
  push bx
  push dx
  mov dl, al
  ; high nibble
  mov al, dl
  and al, 0xF0
  shr al, 4
  add al, '0'
  mov ah, 0x0E
  mov bh, 0x00
  mov bl, [text_attr]
  int 0x10
  ; low nibble
  mov al, dl
  and al, 0x0F
  add al, '0'
  mov ah, 0x0E
  mov bh, 0x00
  mov bl, [text_attr]
  int 0x10
  pop dx
  pop bx
  pop ax
  ret

; print_uint16: print AX as unsigned decimal
print_uint16:
  push ax
  push bx
  push cx
  push dx
  mov cx, 0           ; digit count
.pu_loop:
  mov dx, 0
  mov bx, 10
  div bx              ; AX/=10, remainder in DX
  push dx             ; push remainder digit
  inc cx
  test ax, ax
  jnz .pu_loop
  ; print digits
.pu_print:
  pop dx
  add dl, '0'
  mov al, dl
  mov ah, 0x0E
  mov bh, 0x00
  mov bl, [text_attr]
  int 0x10
  loop .pu_print
  pop dx
  pop cx
  pop bx
  pop ax
  ret

; skip_spaces: advance SI over spaces and tabs
skip_spaces:
  push ax
.ss_loop:
  mov al, [si]
  cmp al, ' '
  je .next
  cmp al, 9
  jne .done
.next:
  inc si
  jmp .ss_loop
.done:
  pop ax
  ret

; tolower_al: convert AL to lowercase if 'A'-'Z'
tolower_al:
  cmp al, 'A'
  jb .tl_end
  cmp al, 'Z'
  ja .tl_end
  add al, 32
.tl_end:
  ret

; streq_ci: case-insensitive strcmp(SI, DI). CF=1 if equal
streq_ci:
  push si
  push di
.se_loop:
  mov al, [si]
  call tolower_al       ; AL = lower(SI)
  mov ah, [di]
  xchg al, ah           ; AH = lower(SI), AL = [DI]
  call tolower_al       ; AL = lower(DI)
  cmp ah, al
  jne .se_ne
  test ah, ah
  jz .se_eq
  inc si
  inc di
  jmp .se_loop
.se_eq:
  stc
  jmp .se_out
.se_ne:
  clc
.se_out:
  pop di
  pop si
  ret

; strncasecmp_ci: compare up to CX bytes SI vs DI, case-insensitive. CF=1 if equal prefix
strncasecmp_ci:
  push si
  push di
  push cx
.sn_loop:
  cmp cx, 0
  je .sn_eq
  mov al, [si]
  call tolower_al       ; AL = lower(SI)
  mov ah, [di]
  xchg al, ah           ; AH = lower(SI), AL = [DI]
  call tolower_al       ; AL = lower(DI)
  cmp ah, al
  jne .sn_ne
  inc si
  inc di
  dec cx
  jmp .sn_loop
.sn_eq:
  stc
  jmp .sn_out
.sn_ne:
  clc
.sn_out:
  pop cx
  pop di
  pop si
  ret

; parse_hex_byte: parse two hex digits at DS:SI -> AL, CF=1 on success; SI += 2
parse_hex_byte:
  push bx
  push dx
  xor ax, ax
  mov bl, [si]
  call hex_nibble
  jnc .fail
  shl al, 4
  inc si
  mov dl, al
  mov bl, [si]
  call hex_nibble
  jnc .fail
  inc si
  or al, dl
  stc
  jmp .out
.fail:
  clc
.out:
  pop dx
  pop bx
  ret

; ----------------------------------------
; RAM directory system (very simple)
; ----------------------------------------
; Constants
MAX_DIRS  equ 32
NAME_LEN  equ 11   ; max 10 chars + null
MAX_FILES equ 64
FILE_CONTENT_SIZE equ 64

; dirs_init: set up root directory and clear others
dirs_init:
  pusha
  mov cx, MAX_DIRS
  mov di, dir_used
  xor ax, ax
.clr:
  stosb
  loop .clr
  ; root at index 0
  mov byte [dir_used+0], 1
  mov byte [dir_parent+0], 0
  mov byte [dir_names+0], 0
  mov byte [current_dir], 0
  popa
  ret

; dir_index_to_ptr: IN BL=index -> SI points to name slot
dir_index_to_ptr:
  push ax
  push dx
  push di
  xor bh, bh        ; ensure BX=index
  ; DI = BX*11
  mov di, bx
  shl di, 3         ; *8
  mov ax, bx
  shl ax, 1         ; *2
  add di, ax        ; *10
  add di, bx        ; *11
  mov si, dir_names
  add si, di
  pop di
  pop dx
  pop ax
  ret

; token_to_temp: read one token from DS:SI into temp_name (<=10 chars), CF=1 if ok and non-empty
token_to_temp:
  push ax
  push di
  mov di, temp_name
  mov ah, 0         ; len
.tloop:
  mov al, [si]
  cmp al, 0
  je .tend
  cmp al, ' '
  je .tend
  cmp al, '/'
  je .tend
  cmp ah, NAME_LEN-1
  jae .tend
  stosb
  inc si
  inc ah
  jmp .tloop
.tend:
  mov al, 0
  stosb
  cmp ah, 0
  je .empty
  stc
  jmp .done
.empty:
  clc
.done:
  pop di
  pop ax
  ret

; copy_temp_to_dir: IN BL=index; copy temp_name into dir_names[BL]
copy_temp_to_dir:
  push si
  push di
  call dir_index_to_ptr
  mov di, si
  mov si, temp_name
.cp:
  lodsb
  stosb
  test al, al
  jnz .cp
  pop di
  pop si
  ret

; find_child: IN BL=parent index, SI->temp_name; OUT AL=index, CF=1 if found
find_child:
  push bx
  push cx
  push si
  mov ah, bl              ; save parent index in AH
  mov cx, MAX_DIRS-1
  mov al, 1               ; start from index 1
.fnext:
  mov bl, al
  cmp byte [dir_used+bx], 1
  jne .fcont
  cmp byte [dir_parent+bx], ah
  jne .fcont
  ; compare names dir_names[bl] with temp_name
  push ax
  push bx
  call dir_index_to_ptr   ; SI -> name
  mov di, temp_name
  call streq              ; CF=1 if equal
  pop bx
  pop ax
  jc .found
.fcont:
  inc al
  loop .fnext
  clc
  jmp .done
.found:
  stc
.done:
  pop si
  pop cx
  pop bx
  ret

; has_children: IN BL=index; CF=1 if any child exists
has_children:
  push ax
  push bx
  push cx
  mov ch, bl           ; save target parent index in CH
  mov cx, MAX_DIRS
  xor ax, ax
.hn:
  mov bl, al
  xor bh, bh
  cmp byte [dir_used+bx], 1
  jne .hnc
  mov dl, [dir_parent+bx]
  cmp dl, ch
  je .hyes
.hnc:
  inc al
  loop .hn
  clc
  jmp .hout
.hyes:
  stc
.hout:
  pop cx
  pop bx
  pop ax
  ret

; has_files: IN BL=index; CF=1 if any file exists under this dir
has_files:
  push ax
  push bx
  push cx
  mov ch, bl           ; save target parent index in CH
  mov cx, MAX_FILES
  xor ax, ax
.hf_loop:
  mov bl, al
  xor bh, bh
  cmp byte [file_used+bx], 1
  jne .hf_next
  mov dl, [file_parent+bx]
  cmp dl, ch
  je .hf_yes
.hf_next:
  inc al
  loop .hf_loop
  clc
  jmp .hf_out
.hf_yes:
  stc
.hf_out:
  pop cx
  pop bx
  pop ax
  ret

; alloc_dir: find free slot (>=1). OUT AL=index, CF=1 if found
alloc_dir:
  push cx
  mov cx, MAX_DIRS-1
  mov al, 1
.an:
  mov bl, al
  cmp byte [dir_used+bx], 0
  je .got
  inc al
  loop .an
  clc
  pop cx
  ret
.got:
  stc
  pop cx
  ret

; print_pwd: prints current path (root or /name)
print_pwd:
  pusha
  mov al, [current_dir]
  cmp al, 0
  je .only_root
  ; Build stack of indices from current up to root (exclude 0)
  mov byte [pwd_depth], 0   ; depth = 0
.pw_acc:
  mov bl, al
  push bx              ; push index
  inc byte [pwd_depth] ; depth++
  mov al, [dir_parent+bx]
  cmp al, 0
  jne .pw_acc
  ; Print "/name" for each element from root downward
.pw_print:
  mov al, [pwd_depth]
  cmp al, 0
  je .done
  dec byte [pwd_depth]
  pop bx               ; BX = index
  ; print '/'
  mov ah, 0x0E
  mov bh, 0x00
  mov dl, bl           ; save BL=index in DL before clobbering BL
  mov bl, [text_attr]
  mov al, '/'
  int 0x10
  ; print name
  mov bl, dl           ; restore BL=index
  call dir_index_to_ptr
  call puts_raw
  ; BL already restored
  jmp .pw_print
.only_root:
  mov si, slash
  call puts
  popa
  ret
.done:
  ; end line
  call clear_eol
  call newline
  popa
  ret

; list_children: list names under current_dir, or (empty)
list_children:
  pusha
  mov dl, [current_dir]
  mov al, 1
.lnext:
  cmp al, MAX_DIRS
  jae .lend
  mov bl, al
  xor bh, bh
  cmp byte [dir_used+bx], 1
  jne .skip
  cmp byte [dir_parent+bx], dl
  jne .skip
  call dir_index_to_ptr
  ; print name with '/' suffix for directories
  call puts_raw
  ; print '/'
  mov ah, 0x0E
  mov bh, 0x00
  mov bl, [text_attr]
  mov al, '/'
  int 0x10
  ; finish line
  call clear_eol
  call newline
  ; mark that something was printed and count
  mov byte [ls_printed], 1
  inc byte [dir_count]
.skip:
  inc al
  jmp .lnext
.lend:
  popa
  ret

; list_files: list file names under current_dir, or nothing if none
list_files:
  pusha
  mov dl, [current_dir]
  mov al, 0
.lf_next:
  cmp al, MAX_FILES
  jae .lf_end
  mov bl, al
  xor bh, bh
  cmp byte [file_used+bx], 1
  jne .lf_skip
  cmp byte [file_parent+bx], dl
  jne .lf_skip
  ; print name (prefix with nothing for now)
  call file_index_to_ptr
  call puts
  ; mark that something was printed
  mov byte [ls_printed], 1
  inc byte [file_count]
.lf_skip:
  inc al
  jmp .lf_next
.lf_end:
  popa
  ret
 
; file_index_to_ptr: IN BL=index -> SI points to file name slot
file_index_to_ptr:
  push ax
  push dx
  push di
  xor bh, bh
  mov di, bx
  shl di, 3         ; *8
  mov ax, bx
  shl ax, 1         ; *2
  add di, ax        ; *10
  add di, bx        ; *11
  mov si, file_names
  add si, di
  pop di
  pop dx
  pop ax
  ret

; copy_temp_to_file: IN BL=index; copy temp_name into file_names[BL]
copy_temp_to_file:
  push si
  push di
  call file_index_to_ptr
  mov di, si
  mov si, temp_name
.cf_cp:
  lodsb
  stosb
  test al, al
  jnz .cf_cp
  pop di
  pop si
  ret

; find_file_child: IN BL=parent index, SI->temp_name; OUT AL=index, CF=1 if found
find_file_child:
  push bx
  push cx
  push si
  mov ah, bl              ; parent
  mov cx, MAX_FILES
  xor al, al
.ffn:
  cmp al, MAX_FILES
  jae .ff_done
  mov bl, al
  cmp byte [file_used+bx], 1
  jne .ff_cont
  cmp byte [file_parent+bx], ah
  jne .ff_cont
  push ax
  push bx
  call file_index_to_ptr
  mov di, temp_name
  call streq
  pop bx
  pop ax
  jc .ff_found
.ff_cont:
  inc al
  loop .ffn
  clc
  jmp .ff_done2
.ff_found:
  stc
.ff_done2:
  pop si
  pop cx
  pop bx
  ret
.ff_done:
  clc
  jmp .ff_done2

; alloc_file: find free file slot
alloc_file:
  push cx
  mov cx, MAX_FILES
  xor al, al
.af_loop:
  cmp al, MAX_FILES
  jae .af_none
  mov bl, al
  cmp byte [file_used+bx], 0
  je .af_got
  inc al
  loop .af_loop
.af_none:
  clc
  pop cx
  ret
.af_got:
  stc
  pop cx
  ret

; file_data_ptr: IN BL=index -> SI points to start of content buffer
file_data_ptr:
  push ax
  push dx
  push di
  xor bh, bh
  mov di, bx
  ; DI = BX * FILE_CONTENT_SIZE
  ; For 64 bytes size, multiply by 64 = shift left 6
  shl di, 6
  mov si, file_data
  add si, di
  pop di
  pop dx
  pop ax
  ret
; hex_nibble: input BL=char, output AL=nibble, CF=1 ok
hex_nibble:
  push bx
  mov al, bl
  ; '0'-'9'
  cmp al, '0'
  jb .tryA
  cmp al, '9'
  jg .tryA
  sub al, '0'
  stc
  jmp .hx_out
.tryA:
  ; 'A'-'F'
  cmp al, 'A'
  jb .trya
  cmp al, 'F'
  jg .trya
  sub al, 'A'
  add al, 10
  stc
  jmp .hx_out
.trya:
  ; 'a'-'f'
  cmp al, 'a'
  jb .bad
  cmp al, 'f'
  jg .bad
  sub al, 'a'
  add al, 10
  stc
  jmp .hx_out
.bad:
  clc
.hx_out:
  pop bx
  ret

; ----------------------------------------
; Data
; ----------------------------------------
CMD_BUF_SIZE equ 128
STARTUP_CYCLES    equ 3     ; number of dot cycles (increase to slow down)
STARTUP_DOT_TICKS equ 6     ; ticks per dot (~55ms each tick) -> ~330ms

msg_startup db "LockinOS starting",0
msg_banner db "LockinOS shell ready.Type 'help'",0
msg_prompt db "> ",0
msg_unknown db "Unknown command.Type 'help'",0

cmd_buffer times CMD_BUF_SIZE db 0

cmd_help   db "help",0
cmd_whoami db "whoami",0
cmd_date   db "date",0
cmd_uptime db "uptime",0
cmd_about  db "about",0
cmd_beep   db "beep",0
cmd_clear  db "clear",0
cmd_halt   db "halt",0
cmd_reboot db "reboot",0
cmd_shutdown db "shutdown",0
cmd_restart  db "restart",0
cmd_echo   db "echo ",0
cmd_color  db "color ",0
cmd_write  db "write ",0

msg_help db "Commands:",0
         db  "  help       - show this help",0
         db  "  whoami     - current user",0
         db  "  date       - current date/time",0
         db  "  uptime     - time since boot (sec)",0
         db  "  about      - about LockinOS",0
         db  "  beep       - beep (bell)",0
         db  "  echo X     - print X",0
         db  "  color XY   - set text attr hex (e.g. 1E)",0
         db  "  pwd        - show current directory",0
         db  "  ls         - list items",0
         db  "  cd NAME    - change directory (.. or /)",0
         db  "  mkdir NAME - create directory",0
         db  "  rmdir NAME - remove empty directory",0
         db  "  touch NAME - create empty file",0
         db  "  rm NAME    - remove file",0
         db  "  cat NAME   - print file contents",0
         db  "  write NAME TEXT - create/overwrite file with TEXT",0
         db  "  clear      - clear screen",0
         db  "  shutdown   - shut down (halt)",0
         db  "  restart    - reboot",0
         db  "  halt       - halt CPU",0
         db  "  reboot     - reboot",0
         db  0

; state/config
text_attr db 0x07
msg_about db "LockinOS: Minimal 16-bit real-mode OS (V1.0.0)",0
empty db "",0
boot_ticks_lo dw 0
boot_ticks_hi dw 0
cmdptr dw 0
rl_start dw 0
msg_color_usage db "Usage: color XY  (X=bg,Y=fg hex, e.g. 1E)",0
msg_color_set db "Color set.",0
msg_user_prefix db "User ",0
username db "root",0
msg_uptime db "Uptime: ",0
letter_s db "s",0
dash db "-",0
colon db ":",0
space db " ",0
lparen db "(",0
rparen db ")",0

; RTC temp storage (BCD fields)
rtc_century db 0
rtc_year    db 0
rtc_month   db 0
rtc_day     db 0
rtc_hour    db 0
rtc_min     db 0
rtc_sec     db 0

; File/Dir command tokens
cmd_pwd   db "pwd",0
cmd_ls    db "ls",0
cmd_cd    db "cd ",0
cmd_mkdir db "mkdir ",0
cmd_rmdir db "rmdir ",0
cmd_touch db "touch ",0
cmd_rm    db "rm ",0
cmd_cat   db "cat ",0

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
