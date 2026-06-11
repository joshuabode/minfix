// ============================================================================
// Module: FIX_LFSR
// Description: Generates synthetic, randomized Financial Information eXchange
//              (FIX) style trade orders. Uses a 24-bit LFSR to randomize
//              trade sides, ticker IDs, order quantities, and price deltas
//              across 8 tracked market tickers.
// By: Joshua Bode
// ============================================================================

`define DEFAULT_PRICE       32'd10000        // Initial price in pennies ($100)
`define MIN_PRICE           32'd0            // Floor price constraint
`define MAX_PRICE           32'hFFFF_FFFF    // Ceiling price constraint

module FIX_LFSR (
    input  wire        clk,                 // System clock
    input  wire        reset,               // Synchronous system reset
    input  wire        write_en,            // Write enable for configuration
    input  wire        enable,              // Start shifting the LFSR
    input  wire        reg_select,          // Host reg select (0:Seed, 1:Price)
    input  wire [2:0]  ticker_id,           // Ticker for price updates
    input  wire [31:0] data_in,             // Configuration data bus input
    // Packed trade order: [31]:Side, [30:28]:Ticker, [27:0]:Quantity
    output reg  [31:0] data_out,
    output reg  [31:0] price_out            // Active price for current trade
);

    // Memory array storing the current market price for 8 unique tickers
    reg [31:0] market_price [7:0];

    // 33-bit signed variable to handle math & catch underflow/overflow
    logic signed [32:0] current_price = `DEFAULT_PRICE;

    // 24-bit pseudo-random number generator registers
    reg  [23:0] lfsr = 24'b0;
    reg  [23:0] next_lfsr = 24'h0;

    // Internal trade fields sliced directly from the LFSR state bits
    wire side;                              // 1-bit direction (0:Buy, 1:Sell)
    wire [2:0] ticker;                      // 3-bit Ticker ID lookup index
    wire [27:0] quantity;                   // 28-bit Order quantity
    wire [31:0] read_price;                 // Base price before mutation
    logic signed [6:0] delta;               // Price change magnitude

    // --- LFSR Bit Mapping Layout ---
    assign side       = lfsr[0];
    assign ticker     = write_en ? ticker_id : lfsr[3:1];
    assign quantity   = {18'b0, lfsr[13:4]}; // Extracts 10-bit random quantity
    assign read_price = market_price[ticker];

    // ------------------------------------------------------------------------
    // Sequential Logic Block: LFSR State & Market Price Memory Storage
    // ------------------------------------------------------------------------
    always @ (posedge clk) begin
        lfsr <= next_lfsr;
        if (reset)
            for (int i = 0; i < 8; i++)
                market_price[i] <= `DEFAULT_PRICE;
        else
            market_price[ticker] <= current_price;
    end

    // ------------------------------------------------------------------------
    // Combinational Logic Block: Next-State, CPU Writes, & Price Generation
    // ------------------------------------------------------------------------
    always @ (*) begin
        // Default assignments to prevent unintended latch synthesis
        next_lfsr     = lfsr;
        current_price = read_price;
        delta         = 7'b0;

        if (reset) begin
            next_lfsr     = 24'b0;
            current_price = `DEFAULT_PRICE;
        end
        // CPU Direct Write Mode: Override current ticker price
        else if (write_en && reg_select) begin
            current_price = data_in;
        end
        // CPU Direct Write Mode: Seed the LFSR register
        else if (write_en && !reg_select) begin
            next_lfsr     = data_in[23:0];
        end
        // Autonomous Trade and Random Walk Price Generation
        else begin
            if (enable) begin
                // Calculate price step size via bit-shifting.
                // Direction: bits [15:14], Scale factor: bits [20:17]
                case (lfsr[15:14])
                    2'b01:   delta = (-1 << lfsr[20:17]); // Negative movement
                    2'b10:   delta = (1 << lfsr[20:17]);  // Positive movement
                    default: delta = 0;                   // Flat market
                endcase

                // Apply sign-extended delta to baseline price
                current_price = read_price + {{26{delta[6]}}, delta};

                // Handle Out-Of-Bounds conditions.
                // If bit[32] is high, a signed overflow or underflow occurred.
                // We clamp the price to MIN or MAX based on the direction of
                // the delta step (2'b01 for down/underflow, 2'b10 for up/overflow).
                if (current_price[32]) begin
                    case (lfsr[15:14])
                        2'b01:   current_price = `MIN_PRICE;   // Clamp at floor
                        2'b10:   current_price = `MAX_PRICE;   // Clamp at ceiling
                        default: current_price = `DEFAULT_PRICE; // Fallback safely
                    endcase
                end

                // Advance the LFSR using Polynomial taps:
                // x^24 + x^23 + x^22 + x^17 + 1
                next_lfsr = lfsr << 1;
                next_lfsr[0] = lfsr[16] ^ lfsr[21] ^ lfsr[22] ^ lfsr[23];
            end
        end
    end

    // ------------------------------------------------------------------------
    // Output Assignment (Continuous Drive)
    // ------------------------------------------------------------------------
    // Expose the formatted synthetic order details to the downstream bus
    assign data_out  = {side, ticker, quantity};
    assign price_out = market_price[ticker];

endmodule
/*============================================================================*/