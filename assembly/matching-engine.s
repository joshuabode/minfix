; By: Joshua Bode
; The user code for the server. This uses sorted linked lists to implement the
; priority queue abstract data type which is used in the order books to match
; compatible bid and ask orders.


include os_fix_server.s

; Order Struct
; 32 bit: price
; 32 bit: quantity
; 32 bit: client_id
; 32 bit: next pointer

n_tickers equ 8;
price equ 0x0;
qty equ 0x4; quantity
cid equ 0x8; client_id
next equ 0xC; pointer to the next order in a linked list

quantity_mask equ 0b1111111111;

free_stack_size equ 100;
order_pool_size equ 400;

j main

include fix_lib.s

main
    la a0, send_market_data;
    li a7, ECALL_CREATE_PROC;
    ecall;

    la t0, pending_dirty;
    lb t0, [t0] ;
    beqz t0, main; skip if no data is ready
    call allocate_order;
    la t0, pending_data;
    lw t1, [t0] ; Load the pending data;
;   [31]: 0 for a bid and 1 for an ask
;   [30:27]: client_id
;   [12:3]: quantity
;   [2:0]: ticker_id

    srli t2, t1, 3; shift to ignore the ticker id
    andi t2, t2, quantity_mask; and mask with the 10 least significant bits
    sw t2, qty[a0] ; store to the struct returned by allocate_order
    slli t2, t1, 1; shift to ignore buy/sell side
    srli t2, t2, 28; shift to get the client id
    sb t2, cid[a0] ;
    lw t2, 4[t0] ; load pending_price
    sw t2, price[a0] ;

    andi a1, t1, ticker_id_mask; load the ticker_id into the argument for
    ; insertion

    bltz t1, skip_insert_bid;
    call insert_bid;
    j match_all_orders

skip_insert_bid
    call insert_ask;

match_all_orders
    li s0, n_tickers;
    subi s0, s0, 1;
match_all_orders_loop
    mv a0, s0;
    call match_orders;
    subi s0, s0, 1;
    bgez s0, match_all_orders_loop;

    la t1, pending_dirty;
    sw zero, [t1] ; clear the dirty bit, signalling that the engine is ready
    ; for the next order
    j main


; Matches orders in the order book
;
; arguments:
;    a0: The order book index (ticker_id) to settle
;
; returns:
;   none;
;

match_orders
    subi sp, sp, 20;
    sw ra, 16[sp] ;
    sw s3, 12[sp] ;
    sw s2, 8[sp] ;
    sw s1, 4[sp] ;
    sw s0, [sp] ;
    mv s2, a0; preserve a0
match_orders_loop
    la t0, head_table;
    slli t1, a0, 3; multiply by word size * words per index
    add t0, t0, t1; t0 = base + offset pointer to the ask head pointer
    addi t1, t0, 4; t1 = pointer to the bid head pointer
    lw t0, [t0] ; t0 = ask head pointer
    lw t1, [t1] ; t1 = bid head pointer
    lw t2, [t0] ; t2 = pointer to best ask
    lw t3, [t1] ; t3 = pointer to best bid

    beqz t2, match_orders_exit;
    beqz t3, match_orders_exit; while buy list not empty and sell list not empty
    lw t5, cid[t2] ; t1 client_id on the sell side
    lw t6, cid[t3] ; t2 client_id on the buy side
    beq t5, t6, match_all_orders_loop;

    lw s0, price[t2] ; s0 = best ask price
    lw s1, price[t3] ; s1 = best bid price
    bgt s0, s1, match_orders_exit;
    lw t5, next[t2]
    sw t5, [t0] ; ask_head = best ask.next (heap pop)
    lw t5, next[t3]
    sw t5, [t1] ; bid_head = best bid.next (heap pop)
    sw zero, next[t2]
    sw zero, next[t3] ; clear the next pointers for the matched orders
    lw t4, qty[t2] ; t4 = best ask quantity
    lw t5, qty[t3] ; t5 = best bid quantity
    bgt t5, t4, push_residual_bid;
    beq t4, t5, recycle_both_orders;

push_residual_ask
    sub t4, t4, t5 ; Calculate unmatched quantity
    sw t4, qty[t2] ; Set this as the new quantity
    mv a0, t2; load address of order to argument
    mv a1, s2 ; load order book index to argument
    mv s3, t3; preserve pointer to best bid
    call insert_ask; insert residual order
    mv a0, s3; recycle fully matched order
    call recycle_order;
    j update_mkt_price;

push_residual_bid
    sub t5, t5, t4 ;
    sw t5, qty[t3] ;
    mv a0, t3; load address of order to argument
    mv a1, s2 ; load order book index to argument
    mv s3, t2; preserve pointer to best ask
    call insert_bid; insert residual order
    mv a0, s3; recycle fully matched order
    call recycle_order;
    j update_mkt_price;

recycle_both_orders
    mv a0, t2;
    mv s3, t3; preserve bid order pointer
    call recycle_order;
    mv a0, s3;
    call recycle_order;

update_mkt_price
    sub s1, s1, s0; s1 = best bid price - best ask price
    srli s1, s1, 2; s1 = (best bid price - best ask price)//2
    add s1, s0, s1; s1 = best ask price + (best bid price - best ask price)//2
    ; which is equivalent to (best bid price + best ask price)//2 which is our
    ; mid price. We use this as the market price
    la t0, mkt_price_table;
    slli t1, s2, 2; multiply ticker_id by word size
    add t0, t0, t1; t0 = pointer to market price
    sw s1, [t0]; update the market price to be the calculated mid price

print_matched_order
    la a0, matched_msg_buffer;
    call lib_println
    j match_orders_loop

match_orders_exit
    lw s0, [sp] ;
    lw s1, 4[sp] ;
    lw s2, 8[sp] ;
    sw s3, 12[sp] ;
    lw ra, 16[sp] ;
    addi sp, sp, 20;
    ret


pending_data defw 0;
pending_price defw 0;
pending_dirty defw 0;

mkt_price_table
    mkt_price_0 defw 0x2710;
    mkt_price_1 defw 0x2710;
    mkt_price_2 defw 0x2710;
    mkt_price_3 defw 0x2710;
    mkt_price_4 defw 0x2710;
    mkt_price_5 defw 0x2710;
    mkt_price_6 defw 0x2710;
    mkt_price_7 defw 0x2710;

send_market_data
    li s0, n_tickers;
    subi s0, s0, 1;
send_market_data_loop
    la t0, mkt_price_table
    slli t1, s0, 2; multiply by word size
    add t1, t0, t1; t1 = pointer to market price
    li a0, price_tag;
    la a1, mkt_data_msg_buffer;
    lw a2, [t1] ; load the market price
    li a3, price_value_len;
    call append_tagvalue;

    li a0, ticker_id_tag;
    ; a1 points to the next available byte after calling append_tagvalue
    mv a2, s0;
    li a3, ticker_id_value_len;
    call append_tagvalue;

    sb zero, [a1] ; null terminate the message

    la a0, mkt_data_msg_string_start;
    call lib_send_fix_msg;

    subi s0, s0, 1;
    bgtz s0, send_market_data_loop;

    li a0, 10_000; 10,000ms = 10 seconds
    li a7, ECALL_SLEEP_PROC;
    ecall;
j send_market_data


matched_msg_buffer defb "Trade executed", 0
mkt_data_msg_string_start defb "8=FIX.min", soh, "35=W", soh
mkt_data_msg_buffer defs 32, 0;

align

; Inserts an order into the ask (sell) side of the order book.
; A min priority queue with the price as the key is modelled with a linked list
;
; arguments:
;   a0: address of the new order
;   a1: the index of the order book to insert into (ticker_id)
;
; returns:
;   none

insert_ask
    la t0, head_table;
    slli t1, a1, 3; multiply by 8 (word size * words per entry)
    add t0, t0, t1 ; t0 = base + offset;
    lw t0, [t0] ; address of the ask_head for a ticker
    lw t1, [t0] ; t1 = current node
    mv t2, t0 ; t2 = pointer to the next field to update

insert_ask_loop
    beqz t1, commit_link;
    lw t3, price[t1] ; get the price of the current node
    lw t4, price[a0] ; get the price of the new node

    blt t4, t3, commit_link; insert the new order once its price is strictly
    ; less than the current node's. This keeps time priority

    ; Current := next
    lw t1, next[t1] ;
    addi t2, t1, 8;
    j insert_ask_loop


; Inserts an order into the bid (buy) side of the order book.
; A max priority queue with the price as the key is modelled with a linked list
;
; arguments:
;   a0: address of the new order
;   a1: the index of the order book to insert into (ticker_id)
;
; returns:
;   none

insert_bid
    la t0, head_table;
    slli t1, a1, 3; multiply by 8 (word size * words per entry)
    add t0, t0, t1 ; t0 = base + offset; address of the ask_head for a ticker
    addi t0, t0, 4; go to the next address to get the bid_head
    lw t0, [t0] ; address of the bid_head for a ticker
    lw t1, [t0] ; t1 = current node
    mv t2, t0 ; t2 = pointer to the next field to update

insert_bid_loop
    beqz t1, commit_link;
    lw t3, price[t1] ; get the price of the current node
    lw t4, price[a0] ; get the price of the new node

    bgt t4, t3, commit_link; insert the new order once its price is strictly
    ; greater than the current node's. This keeps time priority

    ; Current := next
    lw t1, next[t1] ;
    addi t2, t1, 8;
    j insert_bid_loop

; Commits to the insertion of an order

commit_link
    sw t1, next[a0] ; new_node.next = current
    sw a0, [t2] ; (prev or head).next = new_node
    ret

; Pushes an order pointer to the free stack
;
; args:
;   a0: the pointer to the order to recycle
;


recycle_order
    la t0, free_top
    lw t1, [t0]

    li t2, free_stack_size;
    bge t1, t2, recycle_order_exit; exit early to prevent stack overflow

    la t3, free_stack;
    add t3, t3, t1; t2 = base + offset
    sw a0, [t3] ; add the pointer to the free list

    addi t1, t1, 4; move the stack pointer up by one address
    sw t1, [t0] ;

recycle_order_exit
    ret

; Finds space in the order_pool for a new order
;
; arguments:
;   none
;
; returns:
;   a0: a pointer to a free slot
;

allocate_order
    la t0, free_top;
    lw t1, [t0];
    beqz t1, use_pool; if the free stack is empty, use the pool

    subi t1, t1, 4; move the free stack pointer down
    sw t1, [t0] ;
    la t2, free_stack;
    add t2, t2, t1; t2 = base + offset
    lw a0, [t2] ; load the address of a free slot
    ret

use_pool
    la t0, pool_i;
    lw t1, [t0] ; get the pool index
    li t4, order_pool_size;
    bge t1, t4, out_of_mem_crash;
    la t2, order_pool; base
    slli t3, t1, 4; The order struct is 16 bytes
    add a0, t2, t3 ; a0 = base + offset
    addi t1, t1, 1;
    sw t1, [t0] ;
    ret

out_of_mem_crash
    li a7, ECALL_HALT
    ecall

pool_i defw 0; Index to the next available slot


head_table
    defw ask_head_0;
    defw bid_head_0;
    defw ask_head_1;
    defw bid_head_1;
    defw ask_head_2;
    defw bid_head_2;
    defw ask_head_3;
    defw bid_head_3;
    defw ask_head_4;
    defw bid_head_4;
    defw ask_head_5;
    defw bid_head_5;
    defw ask_head_6;
    defw bid_head_6;
    defw ask_head_7;
    defw bid_head_7;


ask_head_0 defw 0;
bid_head_0 defw 0;
ask_head_1 defw 0;
bid_head_1 defw 0;
ask_head_2 defw 0;
bid_head_2 defw 0;
ask_head_3 defw 0;
bid_head_3 defw 0;
ask_head_4 defw 0;
bid_head_4 defw 0;
ask_head_5 defw 0;
bid_head_5 defw 0;
ask_head_6 defw 0;
bid_head_6 defw 0;
ask_head_7 defw 0;
bid_head_7 defw 0;

order_pool defs order_pool_size << 4; Enough space for `order_pool_size` orders

free_stack defs free_stack_size, 0; Space for `free_stack_size` pointers to
                                  ; free slots

free_top defw 0;