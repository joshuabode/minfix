// ============================================================================
// Module: User_Peripheral
// Description: Scalable system peripheral matrix routing 16 concurrent full
//              duplex UART interfaces directly to specialized streaming FIX
//              Protocol Parsers alongside an autonomous pseudo-random LFSR
//              market generator. Features a centralized interrupt info reg.
// By: Vuk Stojkovic and Joshua Bode
// ============================================================================

module User_Peripheral (
    input  wire        clk,                 // Microprocessor system clock
    input  wire        reset,               // Synchronous active-high reset
    input  wire        cs_i,                // Matrix bus module chip select
    input  wire        read_i,              // Bus read strobe qualifier
    input  wire  [1:0] size_i,              // Data transfer size formatting
    input  wire        write_i,             // Bus write strobe qualifier
    input  wire  [1:0] mode_i,              // Privilege authentication mode
    input  wire [31:0] address_i,           // Interconnect data access address
    output wire        stall_o,             // Interconnect stall handshake line
    output wire  [2:0] abort_o,             // Matrix exception diagnostic codes
    input  wire [31:0] data_in,             // CPU master output data bus
    output logic [31:0] data_out,            // CPU master input data bus

    input  wire [31:0] port_in,             // Raw incoming PCB connector lines
    output wire [31:0] port_out,            // Raw outgoing PCB connector lines
    output wire [31:0] port_direction,     // Pin bit direction (0=Out, 1=In)
    output wire  [7:0] LED_o,               // Debug diagnostic status LEDs

    output wire  [7:0] LCD_data_o,          // Parallel LCD character data out
    input  wire  [7:0] LCD_data_i,          // Parallel LCD character data in
    output wire        LCD_RW_o,            // LCD Read/Write selection bit
    output wire        LCD_RS_o,            // LCD Register Selection flag
    output wire        LCD_E_o,             // LCD Strobe operation enable
    output wire        LCD_BL_o,            // LCD Panel backlight toggle

    input  wire  [3:0] switch_i,            // Physical onboard DIP switches
    output wire  [3:0] irq_o                // Combined CPU vector interrupts
);

    // Latched cycle buffer tracking register access offsets
    reg [15:0] addr;

    // Inverted master logic lines required by underlying primitives
    wire        low_reset;

    // Multi-channel internal diagnostic error lines
    logic [15:0] tx_empty_interrupt;
    logic [15:0] rx_error_interrupt;
    reg   [7:0]  led_state = 8'h01;

    // --- Parser Array Core Signals ---
    wire [31:0] p_trade_data_out [15:0];
    wire [31:0] p_info_out       [15:0];
    wire [31:0] p_price_out      [15:0];

    // --- Autonomous Generator Signals ---
    wire [31:0] l_trade_data_out;
    wire [31:0] l_price_out;

    // --- Autonomous Generator Configuration Mapping ---
    reg         lfsr_write          = 1'b0;
    logic       lfsr_reg_select     = 1'b0;
    reg         lfsr_enable         = 1'b0;
    reg   [2:0] lfsr_ticker_select  = 3'b000;
    logic [31:0] lfsr_data_in;

    // --- Decoder Address Spaces ---
    wire        lfsr_access;
    wire        parser_access;
    wire        uart_access;
    wire        interrupt_info_read;        // New flag for status decoding

    // Unused execution flags from the stub code
    wire        fix_ready;
    wire        rx_data_valid;
    reg         data_sent;

    // Specialized hardware configuration logic arrays
    wire [15:0] parser_reset;
    wire [15:0] parser_control_write;
    wire [15:0] is_tx_write;
    wire [32:0] tx_full;

    // Dynamic array tracking packet generation completion statuses
    logic [15:0] fix_data_ready_intr;

    // ------------------------------------------------------------------------
    // Address Decoding & Configuration Mapping Combinational Logic
    // ------------------------------------------------------------------------

    // Parses and tracks software resets routed to individual FIX engines
    assign parser_control_write = (cs_i && write_i && parser_access &&
                                   address_i[3:0] == 4'hC) ?
                                  16'h1 << (address_i[11:4] - 8'h8) : 16'h0;

    assign parser_reset = parser_control_write | {16{reset}};

    // Decodes master reads to centralized status monitoring address space
    assign interrupt_info_read = (read_i && cs_i && address_i == 32'h0002_0040);

    // Maps master configurations down to the active market LFSR
    assign lfsr_control_write = cs_i && write_i && lfsr_access &&
                                (address_i[3:0] == 4'hC);
    assign lfsr_toggle_bit    = data_in[3];

    // --- Module Memory Partition Offsets ---
    // Registers 0x000 to 0x03F -> Main Block UART Cluster
    assign uart_access   = address_i[7:4] < 4'h4;
    // Registers 0x080 to 0x17F -> Main Block FIX Parser Array
    assign parser_access = (address_i[11:4] < 8'h18) &&
                           (address_i[11:4] >= 8'h08);
    // Registers 0x180 to 0x18F -> Shared Autonomous LFSR block
    assign lfsr_access   = address_i[11:4] == 8'h18;

    // Map system diagnostics status flags down to physical board LEDs
    assign LED_o     = {2'h0, (tx_empty_interrupt != 16'h0),
                             (fix_data_ready_intr  != 16'h0)};
    assign low_reset = ~reset;

    // Maps host CPU word writes to target appropriate serial channel FIFOs
    assign is_tx_write = (cs_i && write_i && (address_i[7:6] == 2'b00)) ?
                         16'h1 << address_i[5:2] : 16'h0;

    // ------------------------------------------------------------------------
    // Structural Generation Matrix: Channels [0 to 7]
    // ------------------------------------------------------------------------
    genvar i;
    generate
        for(i=0; i<8; i=i+1) begin: uart_lower
            logic      fix_uart_ready;
            logic      uart_fix_valid;
            logic[7:0] uart_fix_data;

            uart_better uart0 (
                .clk(clk),
                .reset(low_reset),
                // Handles cross-endian byte conversions for word buses
                .cpu_tx_data({data_in[7:0],   data_in[15:8],
                              data_in[23:16], data_in[31:24]}),
                .cpu_tx_w_en(is_tx_write[i]),
                .cpu_tx_full(tx_full[i]),
                .cpu_tx_empty(tx_empty_interrupt[i]),
                .fix_rx_data(uart_fix_data),
                .fix_r_en(fix_uart_ready),
                .fix_data_valid(uart_fix_valid),
                .rx_error_interrupt(rx_error_interrupt[i]),
                .rx_pin(port_in[i]),
                .tx_pin(port_out[23-i])
            );

            FIX_Parser parser (
                .clk(clk),
                .reset(parser_reset[i]),
                .rx_data(uart_fix_data),
                .rx_valid(uart_fix_valid),
                .trade_data_out(p_trade_data_out[i]),
                .price_out(p_price_out[i]),
                .info_out(p_info_out[i]),
                .recv_ready(fix_uart_ready)
            );

            assign fix_data_ready_intr[i] = p_info_out[i][31];
        end
    endgenerate

    // ------------------------------------------------------------------------
    // Structural Generation Matrix: Channels [8 to 15]
    // ------------------------------------------------------------------------
    genvar j;
    generate
        for(j=8; j<16; j=j+1) begin: uart_upper
            logic      fix_uart_ready;
            logic      uart_fix_valid;
            logic[7:0] uart_fix_data;

            uart_better uart0 (
                .clk(clk),
                .reset(low_reset),
                .cpu_tx_data({data_in[7:0],   data_in[15:8],
                              data_in[23:16], data_in[31:24]}),
                .cpu_tx_w_en(is_tx_write[j]),
                .cpu_tx_full(tx_full[j]),
                .cpu_tx_empty(tx_empty_interrupt[j]),
                .fix_rx_data(uart_fix_data),
                .fix_r_en(fix_uart_ready),
                .fix_data_valid(uart_fix_valid),
                .rx_error_interrupt(rx_error_interrupt[j]),
                .rx_pin(port_in[j]),
                .tx_pin(port_out[39-j])
            );

            FIX_Parser parser (
                .clk(clk),
                .reset(parser_reset[j]),
                .rx_data(uart_fix_data),
                .rx_valid(uart_fix_valid),
                .trade_data_out(p_trade_data_out[j]),
                .price_out(p_price_out[j]),
                .info_out(p_info_out[j]),
                .recv_ready(fix_uart_ready)
            );

            assign fix_data_ready_intr[j] = p_info_out[j][31];
        end
    endgenerate

    // ------------------------------------------------------------------------
    // Core Shared Micro-Market Generator Primitive
    // ------------------------------------------------------------------------
    FIX_LFSR LFSR (
        .clk(clk),
        .reset(reset),
        .write_en(lfsr_write),
        .reg_select(lfsr_reg_select),
        .ticker_id(lfsr_ticker_select),
        .data_in(lfsr_data_in),
        .data_out(l_trade_data_out),
        .price_out(l_price_out),
        .enable(lfsr_enable)
    );

    // Synchronous bus responses configured at higher interconnect components
    assign stall_o = cs_i   && 1'b0;
    assign abort_o = {3{cs_i}} && 3'h0;

    // Synchronous addressing delays to match standard pipeline memory fetches
    always @ (posedge clk) begin
        if (cs_i && read_i) begin
            addr <= address_i[15:0];
        end
    end

    // ------------------------------------------------------------------------
    // Sequential Control Logic: Config and Memory Management
    // ------------------------------------------------------------------------
    always @ (posedge clk) begin
        if (reset) begin
            lfsr_write  <= 1'b0;
            lfsr_enable <= 1'b0;
        end else begin
            if (rx_data_valid) begin
                data_sent <= 1'b1;
            end

            // Updates operational mode parameters safely
            if (lfsr_control_write && !lfsr_toggle_bit) begin
                lfsr_reg_select <= data_in[31];
            end

            // Catches incoming price updates designated for specific tickers
            if (cs_i && write_i && lfsr_access) begin
                case (address_i[3:2])
                    2'b10: lfsr_data_in <= data_in;
                endcase
            end

            // Avoid clobbering internal registers when execution bits swap
            lfsr_write <= lfsr_control_write && !lfsr_toggle_bit;

            if (lfsr_control_write) begin
                lfsr_enable        <= lfsr_enable ^ lfsr_toggle_bit;
                lfsr_ticker_select <= lfsr_toggle_bit ? lfsr_ticker_select :
                                                        data_in[2:0];
            end
        end
    end

    // ------------------------------------------------------------------------
    // Combinational Logic Block: Multi-Module Master Read Mux
    // ------------------------------------------------------------------------
    always @ (*) begin
        data_out = 32'h0000_0000; // Safe default output baseline

        if (parser_access) begin
            case(address_i[3:2])
                2'h0: data_out = p_trade_data_out[address_i[11:4]-8];
                2'h1: data_out = p_price_out[address_i[11:4]-8];
                2'h2: data_out = 32'h0000_0000;
                2'h3: data_out = p_info_out[address_i[11:4]-8];
            endcase
        end else if (uart_access)
            data_out = 32'h0000_0000; // UART addresses are write-only
        else if (interrupt_info_read)
            data_out = {rx_error_interrupt, fix_data_ready_intr};
        else if (lfsr_access) begin
            case (address_i[3:2])
                2'h0: data_out = l_trade_data_out;
                2'h1: data_out = l_price_out;
                2'h2: data_out = 32'h0000_0000;
                2'h3: data_out = {29'b0, lfsr_ticker_select};
            endcase
        end
    end

    // Configure 16 lower port bits as input pins and 16 upper port bits as outputs
    assign port_direction = 32'h0000_FFFF;

    // Package out consolidated system interrupts
    assign irq_o = {1'b0, (rx_error_interrupt != 16'h0),
                          (tx_empty_interrupt != 16'h0),
                          (fix_data_ready_intr != 16'h0)};

    // Default static assignments for expansion components
    assign LCD_data_o = 8'b0;
    assign LCD_RW_o   = 1'b1;
    assign LCD_RS_o   = 1'b0;
    assign LCD_E_o    = 1'b0;
    assign LCD_BL_o   = 1'b0;

endmodule
/*============================================================================*/