; By: Joshua Bode
; Some library functions for constructing MinFIX messages.


include print_lib.s
include network_lib.s ; By Vuk to interface with his communication hardware

soh equ 0x1; start of header character
equals equ 0x3D; '='
price_value_len equ 8;
quantity_value_len equ 3;
client_id_value_len equ 1;
ticker_id_value_len equ 1;
side_value_len equ 1;

; Converts a value to a hexidecimal string. Used to match the MinFIX spec.
;
; args:
;   a0: the value to convert
;   a1: the resultant length of the hex string in bytes
;
; returns:
;   a0: a pointer to the hex string
;

htoa ; i := a1
    li t1, value_buffer;
    li t3, 28; the amount to right shift by to get the most significant nibble
htoa_loop
    srl t0, a0, t3; shift so the current nibble is the least significant
    andi t0, t0, nibble_mask;
    addi t0, t0, '0';
    li t2, ':';
    bltu t0, t2, skip_convert_letter;
    addi t0, t0, 7;
skip_convert_letter
    sb t0, [t1]; store ascii value
    addi t1, t1, 1; next charachter
    subi a1, a1, 1; i--
    subi t3, t3, 4; shift by 1 nibble less next iteration
    bgtz a1, htoa_loop;
    sb zero, [t1]; add string terminator
    li a0, value_buffer;
    ret


value_buffer defs 12, 0;
value_buffer_end

; Appends a tagvalue to a string
;
; args:
;   a0: a pointer to the start of the tag string
;   a1: a pointer to the start of the destination string
;   a2: the value (will be converted to hex string)
;   a3: the length of the converted hex string in bytes
;
; returns:
;   a1: the pointer to the next empty byte in the destination string
;


append_tagvalue
    subi sp, sp, 8
    sw ra, 4[sp]
    sw s0, [sp] ;
    call copy_str;
    li t0, equals;
    sb t0, [a1] ;
    addi a1, a1, 1;
    mv s0, a1; preserve destination string pointer

    mv a0, a2; load hex value
    mv a1, a3; load size of hex-string
    call htoa; hexadecimal to ascii
    mv a1, s0; restore destination string pointer
    call copy_str;
    li t0, soh;
    sb t0, [a1] ;
    addi a1, a1, 1
    lw s0, [sp] ;
    lw ra, 4[sp]
    addi sp, sp, 8
    ret


quantity_tag defb "38", 0;
price_tag defb "44", 0;
client_id_tag defb "49", 0;
side_tag defb "54", 0;
ticker_id_tag defb "55", 0;

align