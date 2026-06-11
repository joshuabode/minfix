include os_fix_client.s

include fix_lib.s


; Polls the FIX LFSR device to get random parameters for a FIX message then
; constructs the FIX message in tagvalue encoding and returns a pointer
; to the string.
;
; args:
;   a0: a pointer to the destination of the string
;   a1: trader/client_id
;
; returns:
;   none
;

get_message
    subi sp, sp, 20;
    sw ra, 16[sp]
    sw s3, 12[sp]
    sw s2, 8[sp]
    sw s1, 4[sp]
    sw s0, [sp]

    mv s3, a1; preserve client_id

    li a7, ECALL_GET_LFSR;
    ecall

    mv s1, a0; preserve buy/sell side
    mv s2, a1; preserve ticker_id

    li a0, quantity_tag;
    la a1, message_buffer;
    ; a2 already holds the value of quantity from get_lfsr_params_ecall
    li a3, price_value_len; quantity is 3 bytes according to the protocol
    call append_tagvalue

    li a0, price_tag;
    ; a1 points to the next available byte after calling append_tagvalue
    mv a2, a3;
    li a3, price_value_len;
    call append_tagvalue;

    li a0, client_id_tag;
    mv a2, s3; restore client_id value
    li a3, client_id_value_len; client_id is 1 byte according to the protocol
    call append_tagvalue;

    li a0, side_tag;
    mv a2, s1;
    addi a2, a2, side_value_len;
    li a3, 1;
    call append_tagvalue;

    li a0, ticker_id_tag;
    mv a2, s2;
    li a3, ticker_id_value_len;
    call append_tagvalue;

    sb zero, 1[a1] ; null terminate

    lw s0, [sp]
    lw s1, 4[sp]
    lw s2, 8[sp]
    lw s3, 12[sp]
    lw ra, 16[sp]
    addi sp, sp, 20;

    ret

; Expects the client_id in s0

random_message_process
    li a7, ECALL_GET_SYS_TIME;
    ecall;
    li a7, ECALL_SET_LFSR_SEED;
    ecall;

transmission_loop

    li a0, message_buffer;
    call get_message

    li a0, message_buffer;
    mv a1, s0; load the client_id of the process to send data via that PIO pin
    call lib_send_fix_msg;

j transmission_loop

main
    li s0, 15;
spawn_process_loop; spawn a process for 16 client, one trading over each PIO pin
    la a0, random_message_process;
    li a1, s0
    li a7, ECALL_CREATE_PROC;
    ecall;
    subi s0, s0, 1
    bgtz s0, spawn_process_loop
    li a7, ECALL_HALT;
    ecall;

begin_string defb "8=FIX.min", soh, "35=D", soh ; Specifies the protocol version
; and the message type (D represents new order)

message_buffer defs 32, 0;