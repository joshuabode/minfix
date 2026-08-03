/*
* Module: transmitter fifo
* Description: provides a fire and forget fifo where a word can be written and
* the shifting of chars will be handled without the need for software
* intervention
*
*
* */
module tx_fifo(
  input         r_en,
  input         w_en,
  input[31:0]   data_in,
  input         reset,
  input         clk,

  output reg[7:0] tx_data,
  output wire     empty,
  output wire     full
  );
  //Internal signals
  reg[4:0] read_pointer = 5'b00000;
  reg[4:0] write_pointer = 5'b00000;
  reg[31:0] fifo_buffer [0:15];
  reg[1:0] byte_counter = 2'b00;
  
  wire [31:0] current_word = fifo_buffer[read_pointer[3:0]];
  
  // sequential logic for read
  always @(posedge clk or negedge reset) begin
    if (!reset) begin
        read_pointer <= 5'b00000;
        byte_counter <= 2'b00;
        tx_data      <= 8'b0;
    end else if (r_en && !empty) begin
        case (byte_counter)
            2'b11: tx_data <= current_word[7:0];
            2'b10: tx_data <= current_word[15:8];
            2'b01: tx_data <= current_word[23:16];
            2'b00: tx_data <= current_word[31:24];
        endcase
        if (byte_counter == 2'b11) begin
            read_pointer <= read_pointer + 1'b1;
            byte_counter <= 2'b00;
        end else begin
            byte_counter <= byte_counter + 1'b1;
        end
    end
  end

  always @(posedge clk or negedge reset) begin
    if (!reset) begin
        write_pointer <= 5'b00000;
    end else if (w_en && !full) begin
        fifo_buffer[write_pointer[3:0]] <= data_in; 
        write_pointer <= write_pointer + 1'b1;
    end
end

assign empty = (write_pointer == read_pointer);


assign full  = (read_pointer[4] != write_pointer[4]) && 
               (read_pointer[3:0] == write_pointer[3:0]);
endmodule
