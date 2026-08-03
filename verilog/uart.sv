`define DC1 8'h11
`define DC3 8'h13
`define EOT 8'h04
`define STX 8'h02

module uart_better #(
    parameter FCLK = 40_000_000,
    parameter BAUD = 100_000
)(
    input  wire        clk,
    input  wire        reset,      // Active-low asynchronous

    //  CPU Interface: Transmit
    input  wire [31:0] cpu_tx_data,
    input  wire        cpu_tx_w_en,
    output wire        cpu_tx_full,
    output wire        cpu_tx_empty,

    // FIX Interface: Receive
    output wire [7:0]  fix_rx_data,
    input  wire        fix_r_en,
    output wire        cpu_rx_full, // Expose this so the FSM knows when to block
    output wire        fix_data_valid,

    // CPU Interface: Interrupts
    output reg         rx_error_interrupt,

    //  Physical Pins
    input  wire        rx_pin,
    output wire        tx_pin
);

    // Internal Wires & Baud Generation
    wire tick;
    
    baud_tick #(
        .FCLK(FCLK),
        .BAUD(BAUD)
    ) baud_gen (
        .clk(clk),
        .reset(reset),
        .tick(tick)
    );

    // Transmitter Pipeline
    wire [7:0] tx_byte_to_uart;
    wire       tx_fifo_empty;
    wire       tx_uart_busy;
     
    reg        tx_fifo_r_en;
    reg        tx_uart_trigger;
    reg [1:0]  tx_fsm_state;
   // used to track if a byte is between a stx and eot
    reg        tx_blocked;
    reg        req_send_xoff;
    reg        req_send_xon;     // Fixed typo here!
    reg        inject_mode;
    reg         tx_halted;
    reg [7:0]  ctrl_byte;
    
    tx_fifo tx_buffer (
        .r_en(tx_fifo_r_en),
        .w_en(cpu_tx_w_en),
        .data_in(cpu_tx_data),
        .reset(reset),
        .clk(clk),
        .tx_data(tx_byte_to_uart),
        .empty(tx_fifo_empty),
        .full(cpu_tx_full)
    );

    assign cpu_tx_empty = tx_fifo_empty;

    
    wire [7:0] d_sel = inject_mode ? ctrl_byte : tx_byte_to_uart;

    uart_tx transmitter (
        .tick(tick),
        .trigger(tx_uart_trigger),
        .reset(reset),
        .tx_data(d_sel),
        .tx_line(tx_pin),
        .busy(tx_uart_busy)
    );

    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            tx_fsm_state    <= 3'b000;
            tx_fifo_r_en    <= 1'b0;
            tx_uart_trigger <= 1'b0;
            req_send_xoff   <= 1'b0;
            req_send_xon    <= 1'b0;
            inject_mode     <= 1'b0;
            tx_halted       <= 1'b1; 
        end else begin
            if (cpu_rx_full) req_send_xoff <= 1'b1;
            if (!cpu_rx_full && req_send_xoff) req_send_xon <= 1'b1;
            
            case (tx_fsm_state)
                2'b00: begin // IDLE: Wait for data in FIFO
                    tx_uart_trigger <= 1'b0;
                    tx_fifo_r_en    <= 1'b0; 
                    
                    if (req_send_xoff) begin
                        ctrl_byte        <= `DC3;
                        inject_mode      <= 1'b1;
                        req_send_xoff    <= 1'b0; 
                        tx_fsm_state     <= 2'b01; 
                    end 
                    else if (req_send_xon) begin
                        ctrl_byte        <= `DC1;
                        inject_mode      <= 1'b1;
                        req_send_xon     <= 1'b0; 
                        tx_fsm_state     <= 2'b01; 
                    end 
                    else if (!tx_fifo_empty && !tx_blocked) begin
                        inject_mode <= 1'b0;
                        tx_fifo_r_en <= 1'b1;
                        tx_fsm_state <= 2'b01;
                    end
                end
                
                2'b01: begin // LOAD: Trigger UART
                    // trying with checks here for halted
                    tx_fifo_r_en <= 1'b0;  // stop buffer spilling out
                    if(tx_halted)begin
                        if(tx_byte_to_uart==`STX)begin
                            tx_halted <= 1'b0;
                            tx_uart_trigger <= 1'b1;
                            tx_fsm_state <= 2'b01;
                        end else begin
                            tx_uart_trigger <= 1'b0;
                            tx_fsm_state <= 2'b00; //back to idle
                        end
                    end else begin
                        tx_uart_trigger <= 1'b1; // validate the signal
                            if (tx_uart_busy) begin
                                tx_fsm_state <= 2'b10;   
                            end
                        end
                    end
                
                2'b10: begin // WAIT: Wait for UART to finish
                    tx_uart_trigger <= 1'b0;
                    tx_fifo_r_en    <= 1'b0; 
                    if (!tx_uart_busy) begin
                        tx_fsm_state <= 2'b00;
                    end
                    if(tx_byte_to_uart==`EOT) begin
                        tx_halted <= 1'b1;
                    end
                end             
                
                default: tx_fsm_state <= 2'b00;
            endcase
        end
    end

    // Receiver Pipeline
    wire [7:0] rx_byte_from_uart;
    wire       rx_data_ready;
    wire       rx_ctrl_ready;
    wire       rx_parity_err;
    wire       rx_frame_err;
   
    reg        rx_fifo_w_en;

    uart_rx receiver (
        .rx_line(rx_pin), .tick(tick),
        .reset(reset),
        .rx_data(rx_byte_from_uart),
        .parity_error(rx_parity_err),
        .data_error(rx_frame_err),
        .data_ready(rx_data_ready),
        .ctrl_ready(rx_ctrl_ready)
    );

    rx_fifo rx_buffer (
        .data_in(rx_byte_from_uart),
        .read_en(fix_r_en ),
        .write_en(rx_fifo_w_en),
        .clk(clk),
        .reset(reset),
        .full(cpu_rx_full), 
        .data_valid(fix_data_valid),
        .data_out(fix_rx_data)
    );

    // Edge detectors
    reg rx_ready_d, rx_ctrl_d, rx_perr_d, rx_ferr_d;
    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            rx_ready_d <= 1'b0;
            rx_ctrl_d  <= 1'b0;
            rx_perr_d  <= 1'b0;
            rx_ferr_d  <= 1'b0;
        end else begin
            rx_ready_d <= rx_data_ready;
            rx_ctrl_d  <= rx_ctrl_ready;
            rx_perr_d  <= rx_parity_err;
            rx_ferr_d  <= rx_frame_err;
        end
    end

    wire ready_pulse = rx_data_ready & ~rx_ready_d;
    wire ctrl_pulse  = rx_ctrl_ready & ~rx_ctrl_d;
    wire error_pulse = (rx_parity_err & ~rx_perr_d) | (rx_frame_err & ~rx_ferr_d);

    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            rx_fifo_w_en       <= 1'b0;
            rx_error_interrupt <= 1'b0;
            tx_blocked         <= 1'b0;
        end else begin
            rx_fifo_w_en       <= 1'b0;
            rx_error_interrupt <= 1'b0;

            if (error_pulse) begin
                rx_error_interrupt <= 1'b1; 
            end 
            else if (ready_pulse) begin
                rx_fifo_w_en  <= 1'b1;
            end 
            else if (ctrl_pulse) begin // FIXED: Changed 'begin' to '(ctrl_pulse) begin'
                case(rx_byte_from_uart)
                  `DC1: tx_blocked <= 1'b0;
                  `DC3: tx_blocked <= 1'b1;
                endcase
            end
       end
    end

endmodule
