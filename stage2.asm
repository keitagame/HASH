; Stage 2 Bootloader - Loads Linux kernel
; This stage enables A20, enters protected mode, and loads the Linux kernel

[BITS 16]
[ORG 0x1000]
boot_drive db 0
BOOT_DRIVE equ 0x7C00 + 0x200



KERNEL_OFFSET equ 0x10000   ; Load kernel at 1MB

start_stage2:
    mov si, msg_stage2
    call print_string

    ; Enable A20 line
    call enable_a20

    ; Load kernel from disk
    call load_kernel

    ; Get memory map
    call detect_memory

    ; Enter protected mode
    call switch_to_pm

; Enable A20 line using BIOS
enable_a20:
    mov si, msg_a20
    call print_string

    ; Try BIOS method first
    mov ax, 0x2401
    int 0x15
    jnc .done

    ; Try keyboard controller method
    call wait_8042
    mov al, 0xAD
    out 0x64, al

    call wait_8042
    mov al, 0xD0
    out 0x64, al

    call wait_8042_data
    in al, 0x60
    push ax

    call wait_8042
    mov al, 0xD1
    out 0x64, al

    call wait_8042
    pop ax
    or al, 2
    out 0x60, al

    call wait_8042
    mov al, 0xAE
    out 0x64, al

.done:
    ret

wait_8042:
    in al, 0x64
    test al, 2
    jnz wait_8042
    ret

wait_8042_data:
    in al, 0x64
    test al, 1
    jz wait_8042_data
    ret

; Load kernel from disk
load_kernel:
    mov si, msg_kernel
    call print_string

    ; Reset disk
    xor ah, ah
    mov dl, [BOOT_DRIVE]
    ;mov dl, [0x7C00 + boot_drive - start]
    int 0x13

    ; Load kernel (starting from sector 34, load 100 sectors)
    mov ax, 0x1000
    mov es, ax
    xor bx, bx          ; ES:BX = 0x10000

    mov ah, 0x02        ; Read sectors
    mov al, 100         ; Number of sectors
    mov ch, 0           ; Cylinder
    mov cl, 34          ; Sector
    mov dh, 0           ; Head
    mov dl, [BOOT_DRIVE]
    ;mov dl, [0x7C00 + boot_drive - start]
    int 0x13

    jc .error
    ret

.error:
    mov si, msg_error
    call print_string
    jmp $

; Detect memory using BIOS
detect_memory:
    mov si, msg_memory
    call print_string

    ; Get memory size using INT 0x15, EAX=0xE820
    xor ebx, ebx
    mov di, 0x5000      ; Store memory map at 0x5000
    mov edx, 0x534D4150 ; 'SMAP'

.loop:
    mov eax, 0xE820
    mov ecx, 24
    int 0x15

    jc .done
    cmp eax, 0x534D4150
    jne .done

    add di, 24
    test ebx, ebx
    jnz .loop

.done:
    ret

; Switch to protected mode
switch_to_pm:
    cli

    ; Load GDT
    lgdt [gdt_descriptor]

    ; Set PE bit
    mov eax, cr0
    or eax, 1
    mov cr0, eax

    ; Far jump to 32-bit code
    jmp CODE_SEG:init_pm

; Print string (16-bit real mode)
print_string:
    pusha
    mov ah, 0x0E
.loop:
    lodsb
    cmp al, 0
    je .done
    int 0x10
    jmp .loop
.done:
    popa
    ret

; GDT
gdt_start:
    ; Null descriptor
    dq 0

    ; Code segment descriptor
gdt_code:
    dw 0xFFFF       ; Limit low
    dw 0x0000       ; Base low
    db 0x00         ; Base middle
    db 10011010b    ; Access byte
    db 11001111b    ; Flags + Limit high
    db 0x00         ; Base high

    ; Data segment descriptor
gdt_data:
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 10010010b
    db 11001111b
    db 0x00

gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dd gdt_start

CODE_SEG equ gdt_code - gdt_start
DATA_SEG equ gdt_data - gdt_start

; Messages
msg_stage2: db "Stage 2 loaded", 13, 10, 0
msg_a20: db "Enabling A20...", 13, 10, 0
msg_kernel: db "Loading kernel...", 13, 10, 0
msg_memory: db "Detecting memory...", 13, 10, 0
msg_error: db "Error!", 13, 10, 0

; 32-bit protected mode code
[BITS 32]
init_pm:
    ; Setup segments
    mov ax, DATA_SEG
    mov ds, ax
    mov ss, ax
    mov es, ax
    mov fs, ax
    mov gs, ax

    ; Setup stack
    mov ebp, 0x90000
    mov esp, ebp

    ; Print success message in 32-bit mode
    mov ebx, 0xB8000
    mov byte [ebx], 'P'
    mov byte [ebx+1], 0x0F
    mov byte [ebx+2], 'M'
    mov byte [ebx+3], 0x0F

    ; Setup Linux boot protocol
    call setup_linux_boot

    ; Jump to kernel
    jmp CODE_SEG:KERNEL_OFFSET

setup_linux_boot:
    ; Zero out BSS if needed
    ; Setup boot parameters according to Linux boot protocol

    ; Setup boot_params structure at 0x9000
    mov edi, 0x9000
    mov ecx, 4096/4
    xor eax, eax
    rep stosd

    ; Fill in some basic boot parameters
    mov dword [0x9000 + 0x1F1], 0x53726448  ; Magic number
    mov byte [0x9000 + 0x210], 0x07         ; Boot protocol version
    mov byte [0x9000 + 0x211], 0x80         ; Type of loader
    mov word [0x9000 + 0x224], 0xDE00       ; Heap end pointer
    mov byte [0x9000 + 0x227], 0x01         ; Extended loader type

    ; Command line
    mov dword [0x9000 + 0x228], 0x20000     ; Command line pointer

    ; Copy command line
    mov esi, cmdline
    mov edi, 0x20000
    mov ecx, cmdline_end - cmdline
    rep movsb

    ret

cmdline: db "console=ttyS0 root=/dev/sda1", 0
cmdline_end:

; Fill rest of stage 2
times 16384-($-$$) db 0
