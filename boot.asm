; Stage 1 Bootloader - MBR (512 bytes)
; Loads Stage 2 from disk and jumps to it

[BITS 16]
[ORG 0x7C00]

start:
    ; Setup segments
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    sti

    ; Save boot drive
    mov [boot_drive], dl

    ; Print loading message
    mov si, msg_loading
    call print_string

    ; Load Stage 2 from disk
    ; Stage 2 is located at sector 2, we'll load 32 sectors
    mov ah, 0x02        ; Read sectors
    mov al, 32          ; Number of sectors to read
    mov ch, 0           ; Cylinder 0
    mov cl, 2           ; Start from sector 2
    mov dh, 0           ; Head 0
    mov dl, [boot_drive]
    mov bx, 0x1000      ; Load to 0x1000
    int 0x13

    jc disk_error

    ; Jump to Stage 2
    jmp 0x0000:0x1000

disk_error:
    mov si, msg_error
    call print_string
    jmp $

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

boot_drive: db 0
msg_loading: db "Loading bootloader...", 13, 10, 0
msg_error: db "Disk error!", 13, 10, 0

; Fill the rest with zeros and add boot signature
times 510-($-$$) db 0
dw 0xAA55
