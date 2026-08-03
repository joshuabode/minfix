/*Module: rx_fifo
*
* Description: a hardware fifo for storaging collected bytes from the reciever
* module
*/
`define MAX_BUFFER_PTR 4'b1111
`define EOT            8'h04
`define STX            8'h02
module rx_fifo(
    input[7:0]        data_in, 
    input             read_en,
    input             write_en,
    input             clk,
    input             reset,
    output wire       full,
    output reg[7:0]   data_out, // sending bytes now instead
    output reg        data_valid
  );

  // write registers
  reg [7:0] write_pointer = 8'h00;
  // read registers
  reg [7:0] read_pointer = 8'h00;
  wire empty;
  // main register file for the dual buffer memory
  reg[7:0] buffer [0:127]; // approx 2 full messages

  // write logic, writes willl come from the receiver
  assign full = (write_pointer[7] != read_pointer[7])
                && (write_pointer[6:0]==read_pointer[6:0]);
  assign empty = (read_pointer==write_pointer);

  always@ (posedge clk, negedge reset)begin
    
    if(!reset)begin
      write_pointer <= 8'h00;
    end else begin
      // write logic
      if(write_en && !full)begin
        buffer[write_pointer[6:0]] <= data_in;
        write_pointer <= write_pointer + 1;
      end
    end
  end
  // read logic, reads out to the FIX parser
  always@ (posedge clk, negedge reset) begin

    if(!reset) begin
      read_pointer <= 8'h00;
      data_valid <= 1'b0;
    end else begin
      if(read_en && !empty)begin
        // check for eot
        if(buffer[read_pointer[6:0]]==`EOT)begin
          data_valid <= 1'b0 ;// wait for fresh values
        end else begin
          data_valid <= 1'b1; // Non EOT char
        end 
        data_out <= buffer[read_pointer[6:0]]; // needs validation from valid bit
        read_pointer <= read_pointer + 1;
      end else begin
        data_valid <= 1'b0;
      end
    end
  end
endmodule
