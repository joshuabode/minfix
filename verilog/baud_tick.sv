module baud_tick #(
    parameter integer FCLK = 40_000_000,
    parameter integer BAUD = 100_000
)(
    input wire clk,
    input wire reset,
    output reg tick
);
    localparam integer CYCLES = FCLK/(BAUD * 16); //over-sampling
    reg [3:0] tick_cnt; // tracks ticks up to 16 for tx 
    reg [$clog2(CYCLES)-1:0] cnt;

    always@(posedge clk, negedge reset)
        begin
            if(!reset) begin
                cnt <= CYCLES-1;
                tick <= 1'b0;
            end else begin
                if (cnt == 0) begin
                    cnt <= CYCLES-1;
                    tick <= 1'b1;
                end else begin
                    cnt <= cnt - 1;
                    tick <= 1'b0;
                end
            end
        end
endmodule
