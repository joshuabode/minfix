`define RX_IDLE_STATE   3'b000
`define RX_START        3'b001
`define RX_DATA         3'b010
`define RX_PARITY       3'b011
`define RX_STOP         3'b100
`define RX_ERROR        3'b101

`define EOT             8'h04 /*End of transmission*/
`define DC1             8'h11 /*Stop transmission  */
`define DC3             8'h13 /*Resume transmission*/


module uart_rx(
    input  wire       rx_line,
    input  wire       tick,
    input  wire       reset,
    output reg  [7:0] rx_data,
    output reg        parity_error,
    output reg        data_error, 
    output reg        data_ready,
    output reg        ctrl_ready
); 

reg [2:0] rx_state  = `RX_IDLE_STATE;
reg [3:0] tick_acc  = 4'b0000;
reg [7:0] shift_reg = 8'b0000_0000;
reg [2:0] bits_recv = 3'b000;
reg       rx_parity_bit;

always @(posedge tick or negedge reset) begin
  if(!reset) begin
    rx_state      <= `RX_IDLE_STATE;
    tick_acc      <= 4'b0000;
    shift_reg     <= 8'b0000_0000;
    bits_recv     <= 3'b000;
    rx_parity_bit <= 1'b0;
    data_ready    <= 1'b0;
    ctrl_ready    <= 1'b0;        // FIXED: Was improperly initialized to 1'b1
    parity_error  <= 1'b0;
    data_error    <= 1'b0;
  end else begin
    data_ready <= 1'b0;
    ctrl_ready <= 1'b0;
    
    case(rx_state)
      `RX_IDLE_STATE: begin
        if(rx_line == 1'b0) begin
          if(tick_acc == 4'b0111) begin
            rx_state <= `RX_START; 
          end else tick_acc <= tick_acc + 1'b1;
        end else tick_acc <= 4'b0000;
      end 

      `RX_START: begin
        tick_acc <= 4'b0000; 
        if(rx_line == 1'b0) begin
          rx_state      <= `RX_DATA; 
          rx_parity_bit <= 1'b0;
          bits_recv     <= 3'b000; // Reset alignment counter!
        end else begin
          rx_state <= `RX_ERROR; 
        end
      end 

      `RX_DATA: begin
        if(tick_acc == 4'b1111) begin
          shift_reg     <= {rx_line, shift_reg[7:1]};
          rx_state      <= (bits_recv == 3'b111) ? `RX_PARITY : `RX_DATA;
          bits_recv     <= bits_recv + 1'b1;  
          rx_parity_bit <= (rx_line == 1'b1) ? ~rx_parity_bit : rx_parity_bit;
          tick_acc      <= 4'b0000;
        end else tick_acc <= tick_acc + 1'b1;
      end

      `RX_PARITY: begin
        if(tick_acc == 4'b1111) begin
          if(rx_parity_bit == rx_line) begin
            rx_state     <= `RX_STOP;
            tick_acc     <= 4'b0000;
            parity_error <= 1'b0;
          end else begin
            rx_state     <= `RX_ERROR;
            parity_error <= 1'b1;
          end
        end else tick_acc <= tick_acc + 1'b1;
      end 

      `RX_STOP: begin
        if(tick_acc == 4'b1111) begin
          tick_acc <= 4'b0000;
          if(rx_line == 1'b0) begin
            rx_state   <= `RX_ERROR;
            data_error <= 1'b1;
          end else begin 
            rx_state   <= `RX_IDLE_STATE;
            data_error <= 1'b0;
            rx_data    <= shift_reg;     
            if (shift_reg == `DC1 || shift_reg == `DC3) begin
                ctrl_ready <= 1'b1;
                data_ready <= 1'b0;
            end else begin
                ctrl_ready <= 1'b0;
                data_ready <= 1'b1;
            end
          end
        end else tick_acc <= tick_acc + 1'b1;
      end 

      `RX_ERROR: begin
        if(rx_line == 1'b1) begin
          rx_state <= `RX_IDLE_STATE; 
        end
      end
    endcase
  end
end
endmodule
