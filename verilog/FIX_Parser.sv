// ============================================================================
// Module: FIX_Parser
// Description: Streaming byte-by-byte hardware parser for a minimal variant
//              of the Financial Information eXchange (FIX) protocol.
//              Supports parsing Order Single ('D') and Market Data ('W')
//              messages. Keeps all comment lines under 80 characters.
// By: Joshua Bode
// ============================================================================

`define SOH           8'h01          // FIX Start-Of-Header ASCII delimiter

module FIX_Parser (
    input  wire        clk,                 // Core system clock
    input  wire        reset,               // Synchronous system reset
    input  wire [7:0]  rx_data,             // Incoming byte data stream
    input  wire        rx_valid,            // Input data valid qualifier

    output logic [31:0] trade_data_out,     // Formatted layout of trade fields
    output logic [31:0] price_out,          // Captured & parsed numerical price
    output logic [31:0] info_out,           // Parser metadata & error reports
    output logic       recv_ready           // High when ready for next message
);

    /*
        Error codes summary:
            0: No error detected
            1: Invalid tag or bad tag ordering/sequencing
            2: Invalid protocol version string
            3: Invalid or unsupported message type
            4: Invalid value for execution side
            5: Invalid Ticker ID out of range
    */

    // Protocol Version Validation Key
    localparam [55:0] expected_version = "FIX.min";

    // Converts an ASCII hexadecimal digit ("0"-"9", "A"-"F") into a 4-bit bin
    function automatic logic [3:0] hex_to_bin(logic [7:0] ascii);
        if (ascii >= "0" && ascii <= "9") return ascii[3:0];
        if (ascii >= "A" && ascii <= "F") return ascii[3:0] + 4'd9;
        return 4'h0;
    endfunction

    // State definitions for the streaming FIX tag/value parsing loop
    enum logic [3:0] {
        TAG,                                // Parsing tag numbers up to '='
        VERSION,                            // Tag 8: Protocol Version
        TYPE,                               // Tag 35: Message Type
        QTY,                                // Tag 38: Order Quantity
        PRICE,                              // Tag 44: Execution Price
        CID,                                // Tag 49: Sender Client ID
        SIDE,                               // Tag 54: Side (Buy/Sell)
        TID,                                // Tag 55: Symbol / Ticker ID
        DONE                                // Terminal cycle execution state
    } state = TAG;

    // Internal State registers
    logic [15:0] tmp_tag = 16'h0;           // Shift register for text tags
    logic [55:0] tmp_val = 56'h0;           // Accruing value buffer register
    logic market_data_msg = 1'b0;           // High if parsing a "W" message
    logic valid = 1'b0;                     // Internal packet-ready flag
    logic [2:0] packets_recieved = 3'd0;    // Sequence checkpoint tracker

    logic       market_data;                // Latched copy of message type
    logic       out_valid;                  // Masked output valid flag

    // Internal unpacked data registers
    logic [2:0] error_out;                  // Active code error register
    logic [9:0] quantity_out = 10'b0;       // Numeric order quantity
    logic [3:0] client_id_out = 4'b0;       // Numeric Client identification
    logic       side_out = 1'b0;            // Decoded Side bit (0=Buy, 1=Sell)
    logic [2:0] ticker_id_out = 3'b0;       // Extracted numeric ticker index

    // ------------------------------------------------------------------------
    // Sequential State Machine & Stream Parsing
    // ------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            state            <= TAG;
            valid            <= 1'b0;
            tmp_val          <= 56'h0;
            tmp_tag          <= 16'h0;
            packets_recieved <= 3'd0;
            market_data_msg  <= 1'b0;
            market_data      <= 1'b0;
            quantity_out     <= 10'b0;
            client_id_out    <= 4'b0;
            side_out         <= 1'b0;
            ticker_id_out    <= 3'b0;
            error_out        <= 3'd0;
            price_out        <= 32'h0;
        end else if (rx_valid) begin
            error_out <= 3'd0;              // Optimistically clear errors

            case (state)
                // --- STATE: TAG ---
                // Accumulates character tags until an '=' sign is processed
                TAG: begin
                    valid   <= 1'b0;
                    tmp_val <= 56'h0;

                    // Branch parsing rules based on message flavor
                    if (rx_data == "=" && !market_data_msg) begin
                        tmp_tag <= 16'h0;
                        case (tmp_tag)
                            {8'h0, "8"}: state <= VERSION;
                            "35":        state <= TYPE;
                            "38":        state <= QTY;
                            "44":        state <= PRICE;
                            "49":        state <= CID;
                            "54":        state <= SIDE;
                            "55":        state <= TID;
                            default:     error_out <= 3'd1; // Invalid tag
                        endcase
                    end else if (rx_data == "=" && market_data_msg) begin
                        tmp_tag <= 16'h0;
                        case (tmp_tag)
                            "35":    state <= TYPE;
                            "44":    state <= PRICE;
                            "55":    state <= TID;
                            default: error_out <= 3'd1; // Invalid tag
                        endcase
                    end else
                        tmp_tag <= (tmp_tag << 8) + rx_data; // Shift tag text
                end

                // --- STATE: VERSION (Tag 8) ---
                VERSION: begin
                    if (rx_data == `SOH && packets_recieved == 0) begin
                        packets_recieved <= (packets_recieved + 1'd1);
                        if (tmp_val == expected_version) begin
                            tmp_val <= 56'h0;
                            state   <= TAG;
                        end else
                            error_out <= 3'd2; // Invalid Protocol Version
                    end else if (packets_recieved == 0)
                        tmp_val <= (tmp_val << 8) + rx_data;
                    else
                        error_out <= 3'd1;     // Bad Sequencing
                end

                // --- STATE: TYPE (Tag 35) ---
                TYPE: begin
                    if (rx_data == `SOH && packets_recieved == 1) begin
                        packets_recieved <= (packets_recieved + 1'd1);
                        if (tmp_val[7:0] == "D")
                            state <= TAG;      // New Order Single Message
                        else if (tmp_val[7:0] == "W") begin
                            market_data_msg <= 1'b1; // Market Data Message
                            state <= TAG;
                        end
                        else
                            error_out <= 3'd3; // Unknown Message Type
                    end else if (packets_recieved == 1)
                        tmp_val <= (tmp_val << 8) + rx_data;
                    else
                        error_out <= 3'd1;     // Bad Sequencing
                end

                // --- STATE: QTY (Tag 38) ---
                QTY: begin
                    if (rx_data == `SOH && packets_recieved == 2) begin
                        packets_recieved <= (packets_recieved + 1'd1);
                        quantity_out     <= tmp_val;
                        tmp_val          <= 56'h0;
                        state            <= TAG;
                    end else if (packets_recieved == 2)
                        tmp_val <= (tmp_val << 4) + hex_to_bin(rx_data);
                    else
                        error_out <= 3'd1;     // Bad Sequencing
                end

                // --- STATE: PRICE (Tag 44) ---
                PRICE: begin
                    // Match expected checkpoint index based on msg context
                    if (rx_data == `SOH &&
                        packets_recieved == (market_data_msg ? 2 : 3)) begin
                        packets_recieved <= (packets_recieved + 1'd1);
                        price_out        <= tmp_val;
                        tmp_val          <= 56'h0;
                        state            <= TAG;
                    end else if (packets_recieved == (market_data_msg ? 2 : 3))
                        tmp_val <= (tmp_val << 4) + hex_to_bin(rx_data);
                    else
                        error_out <= 3'd1;     // Bad Sequencing
                end

                // --- STATE: CID (Tag 49) ---
                CID: begin
                    if (rx_data == `SOH && packets_recieved == 4) begin
                        packets_recieved <= (packets_recieved + 1'd1);
                        client_id_out    <= tmp_val;
                        tmp_val          <= 56'h0;
                        state            <= TAG;
                    end else if (packets_recieved == 4)
                        tmp_val <= (tmp_val << 4) + hex_to_bin(rx_data);
                    else
                        error_out <= 3'd1;     // Bad Sequencing
                end

                // --- STATE: SIDE (Tag 54) ---
                SIDE: begin
                    if (rx_data == `SOH && packets_recieved == 5) begin
                        packets_recieved <= (packets_recieved + 1'd1);
                        side_out         <= (tmp_val[7:0] == "1") ? 1'b0 : 1'b1;
                        // Error code 4 if input is not "1" (Buy) or "2" (Sell)
                        error_out        <= !(tmp_val[7:0] == "1"
                                            || tmp_val[7:0] == "2")
                                            ? 3'd4 : 3'd0;
                        tmp_val          <= 56'h0;
                        state            <= TAG;
                    end else if (packets_recieved == 5)
                        tmp_val <= (tmp_val << 8) + rx_data;
                    else
                        error_out <= 3'd1;     // Bad Sequencing
                end

                // --- STATE: TID (Tag 55) ---
                TID: begin
                    if (rx_data == `SOH &&
                        packets_recieved == (market_data_msg ? 3 : 6)) begin
                        packets_recieved <= (packets_recieved + 1'd1);
                        ticker_id_out    <= tmp_val;
                        // Error code 5 if Ticker ID falls out of range [0, 7]
                        error_out        <= (!(tmp_val >= 56'd0 &&
                                              tmp_val < 56'd8)) ? 3'd5 : 3'd0;
                        tmp_val          <= 56'h0;
                        state            <= TAG;
                        valid            <= 1'b1; // Trigger raw packet ready
                        market_data      <= market_data_msg;
                    end else if (packets_recieved == (market_data_msg ? 3 : 6))
                        tmp_val <= (tmp_val << 4) + hex_to_bin(rx_data);
                    else
                        error_out <= 3'd1;     // Bad Sequencing
                end
            endcase
        end
    end

    // ------------------------------------------------------------------------
    // Continuous Output Signal Assignment
    // ------------------------------------------------------------------------
    // Suppress packet validity if a parsing error code was uncovered
    assign out_valid = (error_out == 3'd0) ? valid : 1'b0;

    // Packs components out cleanly. Strips client fields if market data message
    assign trade_data_out = {
        (market_data ? 1'b0  : side_out),
        (market_data ? 4'b0  : client_id_out),
        14'b0,
        (market_data ? 10'b0 : quantity_out),
        ticker_id_out
    };

    // Package data transaction metadata info bus
    assign info_out   = {out_valid, market_data, 27'b0, error_out};
    assign recv_ready = !out_valid;

endmodule
/*============================================================================*/