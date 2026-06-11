// ============================================================================
// Module: FIX_LFSR_Testbench
// Description: Testbench to verify the FIX_LFSR core module. Simulates system
//              resets, seed initialization, and runtime price configuration.
// By: Joshua Bode
// ============================================================================

module FIX_LFSR_Testbench();

localparam CLOCK_PERIOD = 10;                // 10ns period = 100 MHz clock

reg         clk;                             // Simulated system clock
reg         reset;                           // Active-high synchronous reset
reg         write;                           // CPU write cycle enable
reg         en;                              // DUT runtime processing enable
reg         reg_select;                      // 0: Seed write, 1: Price write
reg  [2:0]  ticker_id;                       // Ticker ID bus for price updates
reg  [31:0] data_in;                         // Shared configuration data bus
wire [31:0] data_out;                        // Packed trade data from DUT
wire [31:0] price_out;                       // Executed price from DUT

// ------------------------------------------------------------------------
// Clock Generation Block
// ------------------------------------------------------------------------
initial clk = 1'b1;
always #(CLOCK_PERIOD/2) clk <= !clk;

// ------------------------------------------------------------------------
// Initial Stimulus Initialization
// ------------------------------------------------------------------------
initial begin
    en         = 1'b0;                       // Start with processing disabled
    reset      = 1'b0;                       // De-assert reset initially
    write      = 1'b0;                       // Clear CPU write state
    reg_select = 1'b0;                       // Default register address to 0

    // Initialize data buses to 'x' to catch uninitialized read errors
    ticker_id  = 3'bxxx;
    data_in    = 32'hxxxx_xxxx;
end

// ------------------------------------------------------------------------
// Main Test Sequence
// ------------------------------------------------------------------------
initial begin
    reset_lfsr();                            // Establish deterministic baseline

    // Observe default state outputs for 5 clock cycles
    repeat (5) begin
        @(posedge clk);
        read_message();
    end

    set_seed(32'hE565_8BF1);                 // Load a non-zero PRNG seed

    // Observe output behavior post-seeding for 5 clock cycles
    repeat (5) begin
        @(posedge clk);
        read_message();
    end

    // Override Ticker 0 to start at an arbitrary $5.00 base price
    set_price(3'b0, 32'd500);

    toggle_cycling();                        // Turn on random walk generation

    // Monitor automated trade structures for 25 cycles
    repeat (25) begin
        @(posedge clk);
        read_message();
    end

    toggle_cycling();                        // Pause LFSR processing

    // Ensure outputs freeze and hold steady for 25 cycles
    repeat (25) begin
        @(posedge clk);
        read_message();
    end

    toggle_cycling();                        // Resume LFSR processing

    // Run final verification loop for 25 cycles
    repeat (25) begin
        @(posedge clk);
        read_message();
    end

    $stop;                                   // Pause simulation run
end

// ------------------------------------------------------------------------
// Device Under Test (DUT) Instantiation
// ------------------------------------------------------------------------
FIX_LFSR DUT (
    .clk(clk),
    .reset(reset),
    .write_en(write),
    .reg_select(reg_select),
    .ticker_id(ticker_id),
    .data_in(data_in),
    .data_out(data_out),
    .price_out(price_out),
    .enable(en)
);

// ------------------------------------------------------------------------
// Testbench Tasks (Driver Actions)
// ------------------------------------------------------------------------

// Task: Set a specific market price vector for a given ticker index
task set_price(input [2:0] ticker, input [31:0] price);
begin
    $display("%t Setting price of ticker #%d to %h", $time, ticker, price);
    write      <= #1 1'b1;                   // Drive CPU bus write control
    reg_select <= #1 1'b1;                   // Target price storage space
    ticker_id  <= #1 ticker;
    data_in    <= #1 price;                  // Drive target price on bus
    @(posedge clk)                           // Hold for one clock edge
    write      <= #1 1'b0;                   // Release write state
    data_in    <= #1 32'hxxxx_xxxx;          // Flood data with unknowns
    ticker_id  <= #1 32'hxxxx_xxxx;
end
endtask

// Task: Seed the 24-bit internal LFSR state register
task set_seed(input [31:0] seed);
begin
    $display("%t Setting seed to %h", $time, seed);
    write      <= #1 1'b1;                   // Drive CPU bus write control
    reg_select <= #1 1'b0;                   // Target LFSR seed space
    data_in    <= #1 seed;                   // Drive target seed on bus
    @(posedge clk)                           // Hold for one clock edge
    write      <= #1 1'b0;                   // Release write state
    data_in    <= #1 32'hxxxx_xxxx;          // Clear data bus with unknowns
end
endtask

// Task: Sample and display the active parsed fields from the trade bus
task read_message();
begin
    // Sampled 1ns after clock to allow signals to safely settle
    #1 $display("%t: Price: %d, Side: %d, Ticker ID: %d, Quantity: %d",
                $time, price_out, data_out[31], data_out[30:28],
                data_out[27:0]);
end
endtask

// Task: Assert a single-cycle synchronous module reset
task reset_lfsr();
begin
    $display("%t Resetting LFSR", $time);
    @(posedge clk) reset <= #1 1'b1;         // Assert reset
    @(posedge clk) reset <= #1 1'b0;         // De-assert reset
end
endtask

// Task: Invert the state of the processing loop clock enable signal
task toggle_cycling();
begin
    $display("%t Toggling LFSR enable", $time);
    @(posedge clk) en <= #1 en ^ 1'b1;       // Flip enable bit
end
endtask

endmodule
// ============================================================================