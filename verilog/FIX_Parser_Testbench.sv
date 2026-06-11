// ============================================================================
// Module: FIX_Parser_Testbench
// Description: Comprehensive verification testbench for the FIX_Parser.
//              Preserves all original test vectors while appending new targeted
//              scenarios to isolate every error type in the error_t enum.
// By: Joshua Bode
// ============================================================================

module FIX_Parser_Testbench();

localparam  CLOCK_PERIOD = 10;

reg         clk;                               /* System clock (100 MHz)    */
reg         reset;                             /* System reset              */
reg  [7:0]  rx_data;                           /* Incoming raw data byte    */
reg         rx_valid;                          /* Input data valid strobe   */

wire [31:0] trade_data_out;
wire [31:0] price_out;
wire [31:0] info_out;
wire        recv_ready;

// ------------------------------------------------------------------------
// Clock Generation Block
// ------------------------------------------------------------------------
initial clk = 1'b1;                            /* Setup a clock signal      */
always  #(CLOCK_PERIOD/2) clk <= !clk;

// ------------------------------------------------------------------------
// Signal Initialization
// ------------------------------------------------------------------------
initial begin
    rx_valid = 1'b0;
    reset     = 1'b0;                          /* Define control signals    */
    rx_data = 8'hxx;
end

// ------------------------------------------------------------------------
// Processor Stimulus Simulation Block
// ------------------------------------------------------------------------

// Note that the streaming operator is used on strings to avoid a synthesis
// error using the default Vivado script

initial begin
    reset_parser();

    // Test Case 1: Send a completely junk text string
    parse_message("Hello");

    reset_parser();

    // Test Case 2: Malformed Message Type (Unknown tag assignment 'G')
    parse_message({>>{"8=FIX.min", 8'h01, "35=G", 8'h01}});

    reset_parser();

    // Test Case 3: Out-of-sequence parameters driven to Market Data msg
    parse_message({>>{"8=FIX.min", 8'h01, "35=W", 8'h01,
                      "49=1", 8'h01, "54=1", 8'h01}});

    reset_parser();

    // Test Case 4: Valid Market Data ("W") Message structure
    parse_message({>>{"8=FIX.min", 8'h01, "35=W", 8'h01,
                      "44=11", 8'h01, "55=3", 8'h01}});

    reset_parser();

    // Test Case 5: Partial invalid version text string
    parse_message("8=FIX4.4");

    reset_parser();

    // Test Case 6: Invalid version string capped by a correct SOH flag
    parse_message({>>{"8=FIX4.4", 8'h01}});

    reset_parser();

    // Test Case 7: Invalid out-of-order tag (Tag 12 placed instead of 35)
    parse_message({>>{"8=FIX.min", 8'h01, "12=D", 8'h01, "38=00A", 8'h01,
                      "44=00123456", 8'h01, "49=1", 8'h01, "54=1", 8'h01,
                      "55=7", 8'h01}});

    reset_parser();

    // Test Case 8: Invalid out-of-bounds ticker identifier (Ticker "77")
    parse_message({>>{"8=FIX.min", 8'h01, "35=D", 8'h01, "38=00A", 8'h01,
                      "44=00123456", 8'h01, "49=1", 8'h01, "54=1", 8'h01,
                      "55=77", 8'h01}});

    reset_parser();

    // Test Case 9: Ideal, structured full-form New Order Single ("D") msg
    parse_message({>>{"8=FIX.min", 8'h01, "35=D", 8'h01, "38=00A", 8'h01,
                      "44=00123456", 8'h01, "49=1", 8'h01, "54=1", 8'h01,
                      "55=7", 8'h01}});

    // --- Isolation Test 1: Explicit ERR_BAD_TAG (Code 1) ---
    reset_parser();
    $display("--- Testing Isolation: ERR_BAD_TAG ---");
    // Feeding an invalid tag structure "99=" inside an otherwise valid sequence
    parse_message({>>{"8=FIX.min", 8'h01, "99=D", 8'h01}});

    // --- Isolation Test 2: Explicit ERR_BAD_VERSION (Code 2) ---
    reset_parser();
    $display("--- Testing Isolation: ERR_BAD_VERSION ---");
    // Forcing an illegal protocol variant signature string into Tag 8
    parse_message({>>{"8=FIX.BAD", 8'h01}});

    // --- Isolation Test 3: Explicit ERR_BAD_TYPE (Code 3) ---
    reset_parser();
    $display("--- Testing Isolation: ERR_BAD_TYPE ---");
    // Supplying an unmapped message execution character 'Z' to Tag 35
    parse_message({>>{"8=FIX.min", 8'h01, "35=Z", 8'h01}});

    // --- Isolation Test 4: Explicit ERR_BAD_SIDE (Code 4) ---
    reset_parser();
    $display("--- Testing Isolation: ERR_BAD_SIDE ---");
    // Driving an unsupported action value '9' (Valid options are '1' or '2')
    parse_message({>>{"8=FIX.min", 8'h01, "35=D", 8'h01, "38=00A", 8'h01,
                      "44=00123456", 8'h01, "49=1", 8'h01, "54=9", 8'h01}});

    // --- Isolation Test 5: Explicit ERR_BAD_TICKER (Code 5) ---
    reset_parser();
    $display("--- Testing Isolation: ERR_BAD_TICKER ---");
    // Evaluating an out-of-bounds ticker indexing address parameter '9'
    parse_message({>>{"8=FIX.min", 8'h01, "35=D", 8'h01, "38=00A", 8'h01,
                      "44=00123456", 8'h01, "49=1", 8'h01, "54=1", 8'h01,
                      "55=9", 8'h01}});

    repeat (3)
        @ (posedge clk)
    $stop;
end

// ------------------------------------------------------------------------
// Device Under Test (DUT) Instantiation
// ------------------------------------------------------------------------
FIX_Parser DUT (
    .clk(clk),
    .reset(reset),
    .rx_data(rx_data),
    .rx_valid(rx_valid),
    .trade_data_out(trade_data_out),
    .price_out(price_out),
    .info_out(info_out),
    .recv_ready(recv_ready)
);

// ------------------------------------------------------------------------
// Simulation Driver Tasks
// ------------------------------------------------------------------------
task parse_message(input string message);
begin
    $display("%t Parsing message: %s", $time, message);

    foreach (message[i]) begin
        rx_data  <= #1 message[i];
        rx_valid <= #1 1'b1;
        @(posedge clk);
        #1; // Post-edge capture print to track active state changes
        $display("  Byte: %s | State: %s | Error State: %d",
                 message[i], DUT.state.name(), info_out[2:0]);
        rx_valid <= #1 1'b0;
        rx_data  <= #1 8'hxx;
    end
end
endtask

task reset_parser();
begin
    $display("%t Resetting Parser", $time);
    @ (posedge clk) reset <= #1 1'b1;
    @ (posedge clk) reset <= #1 1'b0;
end
endtask

endmodule
/*============================================================================*/