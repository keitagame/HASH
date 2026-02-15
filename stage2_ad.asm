; Advanced Stage 2 Bootloader with ELF support
; This version can load ELF format kernels

[BITS 16]
[ORG 0x1000]

; Constants
KERNEL_OFFSET equ 0x10000
ELF_MAGIC equ 0x464C457F        ; 0x7F 'E' 'L' 'F'

; ELF header offsets
ELF_ENTRY equ 24
ELF_PHOFF equ 28
ELF_PHNUM equ 44

; Program header offsets  
PHDR_TYPE equ 0
PHDR_OFFSET equ 4
PHDR_VADDR equ 8
PHDR_FILESZ equ 16
PHDR_MEMSZ equ 20

; Program header types
PT_LOAD equ 1

start_advanced:
    mov si, msg_advanced
    call print_string

    ; Enable A20
    call enable_a20_fast

    ; Load kernel
    call load_kernel_advanced

    ; Check if ELF
    mov eax, [KERNEL_OFFSET]
    cmp eax, ELF_MAGIC
    je .is_elf

    ; Not ELF, use standard Linux boot protocol
    mov si, msg_linux
    call print_string
    call detect_memory
    call switch_to_pm_linux
    jmp $

.is_elf:
    mov si, msg_elf
    call print_string
    call switch_to_pm_elf
    jmp $

enable_a20_fast:
    ; Fast A20 enable
    in al, 0x92
    or al, 2
    out 0x92, al
    ret

load_kernel_advanced:
    mov si, msg_load
    call print_string

    ; Reset disk
    xor ah, ah
    mov dl, [0x7C00 + (boot_drive - 0x7C00)]
    int 0x13

    ; Load up to 200 sectors
    mov ax, 0x1000
    mov es, ax
    xor bx, bx

    mov cx, 200         ; Total sectors to load
    mov si, 34          ; Starting sector

.load_loop:
    cmp cx, 0
    je .done

    ; Read up to 64 sectors at a time
    mov ax, cx
    cmp ax, 64
    jbe .read
    mov ax, 64

.read:
    push ax
    push cx

    mov ah, 0x02        ; Read
    mov cl, byte [.current_sector]
    mov ch, byte [.current_cylinder]
    mov dh, byte [.current_head]
    mov dl, [0x7C00 + (boot_drive - 0x7C00)]
    int 0x13

    pop cx
    pop ax

    jc .error

    ; Update pointers
    sub cx, ax
    add word [.current_sector], al

    ; Adjust for next read
    movzx dx, al
    shl dx, 9           ; sectors * 512
    add bx, dx

    jnc .load_loop

    ; Carry occurred, move to next segment
    mov ax, es
    add ax, 0x1000
    mov es, ax
    xor bx, bx

    jmp .load_loop

.done:
    ret

.error:
    mov si, msg_error
    call print_string
    jmp $

.current_sector: db 34
.current_cylinder: db 0
.current_head: db 0

detect_memory:
    xor ebx, ebx
    mov di, 0x5000
    mov edx, 0x534D4150

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

switch_to_pm_linux:
    cli
    lgdt [gdt_descriptor]
    
    mov eax, cr0
    or eax, 1
    mov cr0, eax
    
    jmp CODE_SEG:init_pm_linux

switch_to_pm_elf:
    cli
    lgdt [gdt_descriptor]
    
    mov eax, cr0
    or eax, 1
    mov cr0, eax
    
    jmp CODE_SEG:init_pm_elf

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
    dq 0

gdt_code:
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 10011010b
    db 11001111b
    db 0x00

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
msg_advanced: db "Advanced bootloader v1.0", 13, 10, 0
msg_load: db "Loading kernel...", 13, 10, 0
msg_elf: db "ELF kernel detected", 13, 10, 0
msg_linux: db "Linux bzImage detected", 13, 10, 0
msg_error: db "Load error!", 13, 10, 0

[BITS 32]
init_pm_linux:
    mov ax, DATA_SEG
    mov ds, ax
    mov ss, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    
    mov ebp, 0x90000
    mov esp, ebp

    ; Setup Linux boot params
    call setup_linux_boot
    
    ; Print to screen
    mov byte [0xB8000], 'L'
    mov byte [0xB8001], 0x0A
    
    ; Jump to kernel
    jmp CODE_SEG:KERNEL_OFFSET

init_pm_elf:
    mov ax, DATA_SEG
    mov ds, ax
    mov ss, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    
    mov ebp, 0x90000
    mov esp, ebp

    ; Print to screen
    mov byte [0xB8000], 'E'
    mov byte [0xB8001], 0x0A
    mov byte [0xB8002], 'L'
    mov byte [0xB8003], 0x0A
    mov byte [0xB8004], 'F'
    mov byte [0xB8005], 0x0A

    ; Load ELF program headers
    call load_elf_kernel
    
    ; Get entry point
    mov eax, [KERNEL_OFFSET + ELF_ENTRY]
    
    ; Jump to kernel entry
    jmp eax

load_elf_kernel:
    ; Get program header offset and count
    mov ebx, [KERNEL_OFFSET + ELF_PHOFF]
    add ebx, KERNEL_OFFSET
    movzx ecx, word [KERNEL_OFFSET + ELF_PHNUM]

.load_segments:
    test ecx, ecx
    jz .done

    ; Check if PT_LOAD
    mov eax, [ebx + PHDR_TYPE]
    cmp eax, PT_LOAD
    jne .next

    ; Load this segment
    mov esi, [ebx + PHDR_OFFSET]
    add esi, KERNEL_OFFSET
    mov edi, [ebx + PHDR_VADDR]
    mov edx, [ebx + PHDR_FILESZ]

    ; Copy segment
    push ecx
    mov ecx, edx
    rep movsb
    pop ecx

    ; Zero BSS if needed
    mov edx, [ebx + PHDR_MEMSZ]
    sub edx, [ebx + PHDR_FILESZ]
    test edx, edx
    jz .next

    push ecx
    mov ecx, edx
    xor al, al
    rep stosb
    pop ecx

.next:
    add ebx, 32         ; Size of program header
    dec ecx
    jmp .load_segments

.done:
    ret

setup_linux_boot:
    ; Setup boot_params at 0x9000
    mov edi, 0x9000
    mov ecx, 1024
    xor eax, eax
    rep stosd

    ; Setup basic fields
    mov dword [0x9000 + 0x1F1], 0x53726448
    mov byte [0x9000 + 0x210], 0x07
    mov byte [0x9000 + 0x211], 0x80
    mov word [0x9000 + 0x224], 0xDE00
    mov byte [0x9000 + 0x227], 0x01
    mov dword [0x9000 + 0x228], 0x20000

    ; Copy command line
    mov esi, cmdline
    mov edi, 0x20000
    mov ecx, 50
    rep movsb

    ret

cmdline: db "console=ttyS0 root=/dev/sda1 quiet", 0

times 16384-($-$$) db 0
