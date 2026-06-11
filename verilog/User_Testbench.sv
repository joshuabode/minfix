// ============================================================================
// Module: User_Testbench
// Description: Multi-channel automated test framework verifying both sides of
//              the peripheral wrapper module by simulating physical inter-chip
//              UART connections.
// By: Vuk Stojkovic and Joshua Bode
// ============================================================================

`define USER_IO_SPACE 16'h0002              // Memory block page target index

`define EOT           8'h04                 // End of transmission marker
`define STX           8'h02                 // Start of text frame indicator

module User_Testbench();
    integer i;
    localparam CLOCK_PERIOD = 10;           // 10ns cycle time (100 MHz clock)

    // Master Server Side Host Signals
    reg         clk;
    reg         reset;
    reg         s_read;
    reg         s_write;
    wire        s_cs;
    reg  [31:0] s_address;
    reg   [1:0] s_mode;
    reg  [31:0] s_data_in;
    wire [31:0] s_data_out;
    wire        s_stall;
    wire  [2:0] s_abort;
    wire  [3:0] s_irq;

    wire [31:0] s_port_direction;
    wire  [1:0] s_sounder;
    wire  [7:0] s_LED;
    reg   [3:0] s_switch;

    // Simulated Peer Client Side CPU Signals
    reg         c_read;
    reg         c_write;
    wire        c_cs;
    reg  [31:0] c_address;
    reg   [1:0] size;
    reg   [1:0] mode;
    reg  [31:0] c_data_in;
    wire [31:0] c_data_out;
    wire        c_stall;
    wire  [2:0] c_abort;
    wire  [3:0] c_irq;

    wire [31:0] c_port_direction;
    wire  [1:0] c_sounder;
    wire  [7:0] c_LED;
    reg   [3:0] c_switch;

    // Internal simulation routing signals
    reg         proc_read;
    wire [31:0] proc_data;
    reg  [31:0] parser_base;

    // Cross-wired serial lines
    wire [31:0] s_port_in, c_port_in, cts, stc;
    integer tx_counter;

    // ------------------------------------------------------------------------
    // Structural Interconnect: Serial Loopback Cross-wiring Array
    // ------------------------------------------------------------------------
    genvar k;
    generate
        // Wire Lower Channel Cluster (0 to 7)
        for(k=0; k<8; k=k+1) begin : wire_lower
            assign s_port_in[k] = cts[23-k]; // Client TX k maps to Server RX k
            assign c_port_in[k] = stc[23-k]; // Server TX k maps to Client RX k
        end
        // Wire Upper Channel Cluster (8 to 15)
        for(k=8; k<16; k=k+1) begin : wire_upper
            assign s_port_in[k] = cts[39-k]; // Client TX k maps to Server RX k
            assign c_port_in[k] = stc[39-k]; // Server TX k maps to Client RX k
        end
    endgenerate

    // ------------------------------------------------------------------------
    // Clock Generation Block
    // ------------------------------------------------------------------------
    initial begin
        clk = 1'b0;
        forever #(CLOCK_PERIOD / 2) clk = ~clk;
    end

    // ------------------------------------------------------------------------
    // Signal Initialization Setup
    // ------------------------------------------------------------------------
    initial begin
        reset    = 1'b0;
        c_read   = 1'b0;                         // Keep main buses idle
        s_read   = 1'b0;
        s_write  = 1'b0;
        c_write  = 1'b0;
        size     = 2'h2;                         // Standard word sizing
        mode     = 2'b11;                        // Initialize in Machine mode
        c_switch = 4'h0;                         // Static pull-down switches
    end

    // Trace diagnostic utilities tracking read state pipeline timing
    always @ (posedge clk) begin
        if (reset) proc_read <= 1'b0;
        else       proc_read <= c_cs && c_read;
    end
    assign proc_data = proc_read ? c_data_out : 32'hxxxx_xxxx;

    // ------------------------------------------------------------------------
    // Processing Sequence Stimulus Blocks
    // ------------------------------------------------------------------------
    initial begin
        reset_peripheral();
        $display("===================================");
        $display("%t Checking LFSR reset", $time);
        $display("===================================");

        // Scan baseline LFSR defaults post-flush
        client_peripheral_read_32bit(32'h0002_0180);
        client_peripheral_read_32bit(32'h0002_0184);
        client_peripheral_read_32bit(32'h0002_0188);
        client_peripheral_read_32bit(32'h0002_018C);

        $display("===================================");
        $display("%t Checking client to server transmission", $time);
        $display("===================================");

        // Step sequentially through all 16 parallel serial links
        for(tx_counter = 0; tx_counter < 16; tx_counter = tx_counter+1) begin
            $display("======================================================");
            $display("%t Sending via couple %d", $time, tx_counter);
            $display("======================================================");

            $display("%t ======= Sending market data =======", $time);

            // Transmit brief Market Data stream framing
            push_fix_message({>>{`STX, "8=FIX.min", 8'h01, "35=W", 8'h01,
                                 "44=11", 8'h01, "55=3", 8'h01, `EOT}},
                             tx_counter[3:0]);

            wait(s_irq[0] == 1'b1);

            // Query the centralized status vector info space
            $display("%t Polling Centralized Interrupt Info Vector...", $time);
            server_peripheral_read_32bit(32'h0002_0040);

            // Memory layout offset logic: 0x80, 0x90, 0xA0...
            parser_base = 32'h0002_0080 + (tx_counter * 32'h0000_0010);

            server_peripheral_read_32bit(parser_base + 32'h0);
            @(posedge clk);
            server_peripheral_read_32bit(parser_base + 32'h4);
            @(posedge clk);
            server_peripheral_read_32bit(parser_base + 32'hC);
            @(posedge clk);

            // Wipe status bits once values are processed
            server_peripheral_write_32bit(parser_base + 32'hC, 32'h0);

            $display("%t ======== Sending buy order =======", $time);

            // Transmit detailed New Order Single packet data sequence
            push_fix_message({>>{`STX, "8=FIX.min", 8'h01, "35=D", 8'h01,
                                 "38=00A", 8'h01, "44=00123456", 8'h01,
                                 "49=1", 8'h01, "54=1", 8'h01, "55=7",
                                 8'h01, `EOT}}, tx_counter[3:0]);

            wait(s_irq[0] == 1'b1);

            // Verify status vector info space changes on second packet hit
            $display("%t Polling Centralized Interrupt Info Vector...", $time);
            server_peripheral_read_32bit(32'h0002_0040);

            server_peripheral_read_32bit(parser_base + 32'h0);
            @(posedge clk);
            server_peripheral_read_32bit(parser_base + 32'h4);
            @(posedge clk);
            server_peripheral_read_32bit(parser_base + 32'hC);
            @(posedge clk);

            server_peripheral_write_32bit(parser_base + 32'hC, 32'h0);

            repeat (5) @(posedge clk);
        end

        repeat (2) @ (posedge clk);             /* Hold steady before exit  */
        $stop;
    end

    // Address space comparator matching specified system memory page mapping
    assign s_cs = s_address[31:16] === `USER_IO_SPACE;
    assign c_cs = c_address[31:16] === `USER_IO_SPACE;

    // ------------------------------------------------------------------------
    // Dual System Module Instantiation Layouts
    // ------------------------------------------------------------------------
    User_Peripheral DUT_Server (
        .clk            (clk),
        .reset          (reset),
        .cs_i           (s_cs),
        .read_i         (s_read),
        .write_i        (s_write),
        .address_i      (s_address),
        .size_i         (size),
        .mode_i         (mode),
        .stall_o        (s_stall),
        .abort_o        (s_abort),
        .data_in        (s_data_in),
        .data_out       (s_data_out),
        .port_in        (s_port_in),
        .port_out       (stc),
        .port_direction (s_port_direction),
        .LED_o          (s_LED),
        .switch_i       (s_switch),
        .irq_o          (s_irq)
    );

    User_Peripheral DUT_Client (
        .clk            (clk),
        .reset          (reset),
        .cs_i           (c_cs),
        .read_i         (c_read),
        .write_i        (c_write),
        .address_i      (c_address),
        .size_i         (size),
        .mode_i         (mode),
        .stall_o        (c_stall),
        .abort_o        (c_abort),
        .data_in        (c_data_in),
        .data_out       (c_data_out),
        .port_in        (c_port_in),
        .port_out       (cts),
        .port_direction (c_port_direction),
        .LED_o          (c_LED),
        .switch_i       (c_switch),
        .irq_o          (c_irq)
    );

    // ------------------------------------------------------------------------
    // Simulation Vector Driver Utility Tasks
    // ------------------------------------------------------------------------

    task server_peripheral_write_32bit(input [31:0] write_address,
                                       input [31:0] write_data);
    begin
        $display("%t Writing %h to peripheral address %h", $time, write_data,
                                                           write_address);
        s_write   <= #1 1'b1;
        s_read    <= #1 1'b0;
        s_address <= #1 write_address;
        s_data_in <= #1 write_data;
        @ (posedge clk);
        s_write   <= #1 1'b0;
    end
    endtask

    task client_peripheral_write_32bit(input [31:0] write_address,
                                       input [31:0] write_data);
    begin
        $display("%t Writing %h to peripheral address %h", $time, write_data,
                                                           write_address);
        c_write   <= #1 1'b1;
        c_read    <= #1 1'b0;
        c_address <= #1 write_address;
        c_data_in <= #1 write_data;
        @ (posedge clk);
        c_write   <= #1 1'b0;
    end
    endtask

    task push_fix_message(input string message, input[3:0] ux_id);
        logic[31:0] word_buffer;
        int len;
        int j, k;
    begin
        len = message.len();
        for(j = 0; j < len; j = j+4) begin
            word_buffer = 32'h0000_0000;
            for(k = 0; k < 4; k = k+1) begin
                if(j+k < len) begin
                    word_buffer[(k)*8+: 8] = message[j+k];
                end else begin
                    word_buffer[(k)*8+: 8] = 8'h00;
                end
            end
            push_tx_word(word_buffer, ux_id);
        end
    end
    endtask

    task push_tx_word(input [31:0] word, input[3:0] ux_id);
    begin
        client_peripheral_write_32bit(32'h0002_0000 + (ux_id * 4), word);
    end
    endtask

    task client_peripheral_read_32bit(input [31:0] peripheral_read_address);
    begin
        c_write   <= #1 1'b0;
        c_read    <= #1 1'b1;
        c_address <= #1 peripheral_read_address;
        c_data_in <= #1 32'hxxxx_xxxx;
        @(posedge clk);
        #1 $display("%t Read %h from address %h", $time, c_data_out,
                                                  peripheral_read_address);
        c_write   <= #1 1'b0;
        c_read    <= #1 1'b0;
        c_address <= #1 32'hxxxx_xxxx;
        c_data_in <= #1 32'hxxxx_xxxx;
    end
    endtask

    task server_peripheral_read_32bit(input [31:0] peripheral_read_address);
    begin
        s_write   <= #1 1'b0;
        s_read    <= #1 1'b1;
        s_address <= #1 peripheral_read_address;
        s_data_in <= #1 32'hxxxx_xxxx;
        @(posedge clk);
        #1 $display("%t Read %h from address %h", $time, s_data_out,
                                                  peripheral_read_address);
        s_write   <= #1 1'b0;
        s_read    <= #1 1'b0;
        s_address <= #1 32'hxxxx_xxxx;
        s_data_in <= #1 32'hxxxx_xxxx;
    end
    endtask

    task reset_peripheral();
    begin
        @ (posedge clk) reset <= #1 1'b0;
        @ (posedge clk) reset <= #1 1'b1;
        @ (posedge clk) reset <= #1 1'b0;
    end
    endtask

endmodule
/*============================================================================*/