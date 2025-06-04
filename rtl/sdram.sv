// Module to drive dual Alliance Memory AS4C32M16SB module connected to DE10-Nano via GPIO


// Interface
// When cmd_ready is asserted, controller will accept a command on the next rising edge
// Read: data will appear on data_read port some cycles later along with a 1 on data_read_val
// Write: data_write will accept [burst_len] words for [burst_len] consecutive cycles beginning with 
//    the cycle the command is registered
module sdram #(parameter FREQ = 50000000) (
  input  logic clk,
  input  logic reset,

  // SOC interface
  input  logic        read,
  input  logic        write,
  input  logic [25:0] addr,  // {chip, bank[1:0], row[12:0], col[9:0]}
  output logic        cmd_ready,
  input  logic [15:0] data_write,
  output logic [15:0] data_read,
  output logic        data_read_val,


  // SDRAM interface
  output logic        sd_clk,
  output logic        sd_cs,        // two chips
  output logic [1:0]  sd_bank,      // four banks per chip
  output logic [12:0] sd_addr,      // multiplexed address
  output logic        sd_ras,       // row address select
  output logic        sd_cas,       // column address select
  output logic        sd_we,        // write enable
  input  logic [15:0] sd_data_in,   // read data
  output logic [15:0] sd_data_out,  // write data
  output logic        sd_drive_data // tristate driver enable
);

  // Timings (ns) (pg 22)
  localparam real tCK_ns = 1_000_000_000 / FREQ;
  localparam tRC_ns = 63;
  localparam tRFC_ns = 63;
  localparam tRCD_ns = 21;
  localparam tRP_ns = 21;
  localparam tRRD_ns = 14;
  localparam tMRD_ns = 14;
  localparam tRAS_min_ns = 42;
  localparam tWR_ns = 14;
  localparam tREFI_ns = 64_000_000 / 8192;
  localparam tPOD_ns = 200_000;

  // Timings (cycles)
  localparam tCAS     = 2;  // valid at any valid frequency
  localparam tRC      = int'((tRC_ns + tCK_ns - 1) / tCK_ns) - 1;  // Row cycle time (same bank)
  localparam tRFC     = int'((tRFC_ns + tCK_ns - 1) / tCK_ns) - 1;  // Refresh cycle time
  localparam tRCD     = int'((tRCD_ns + tCK_ns - 1) / tCK_ns) - 1;  // RAS# to CAS# delay (same bank)
  localparam tRP      = int'((tRP_ns + tCK_ns - 1) / tCK_ns) - 1;  // Precharge to refresh/row activate command (same bank)
  localparam tRRD     = int'((tRRD_ns + tCK_ns - 1) / tCK_ns) - 1;  // Row activate to row activate delay (different banks) 
  localparam tMRD     = int'((tMRD_ns + tCK_ns - 1) / tCK_ns) - 1;  // Mode register set cycle time
  localparam tRAS     = int'((tRAS_min_ns + tCK_ns - 1) / tCK_ns) - 1;  // Row activate to precharge time (same bank) (min)
  localparam tWR      = int'((tWR_ns + tCK_ns - 1) / tCK_ns) - 1;  // Write recovery
  localparam tREFI    = int'((tREFI_ns + tCK_ns - 1) / tCK_ns) - 1;  // Refresh period
  localparam tPOD     = int'((tPOD_ns + tCK_ns - 1) / tCK_ns) - 1;  // Power on delay

  // SDRAM mode settings
  localparam BURST_LENGTH   = 3'b000; // 000 = none, 001 = 2, 010 = 4, 011 = 8
  localparam BURST_TYPE     = 1'b0;   // 0 = sequential, 1 = interleaved
  localparam CAS_LATENCY    = 3'd2;   // 2/3 allowed
  localparam TEST_MODE      = 2'b00;  // 0 = disabled
  localparam NO_WRITE_BURST = 1'b1;   // 1 = disabled
  localparam MODE = {3'b000, NO_WRITE_BURST, TEST_MODE, CAS_LATENCY, BURST_TYPE, BURST_LENGTH};

  // Commands
  enum logic [2:0] {
    CMD_NOP     = 3'b111,
    CMD_STOP    = 3'b110,
    CMD_ACTIVE  = 3'b011,
    CMD_READ    = 3'b101,
    CMD_WRITE   = 3'b100,
    CMD_PRECHG  = 3'b010,
    CMD_AUTOREF = 3'b001,
    CMD_MRS     = 3'b000
  } sd_cmd;

  // States
  typedef enum {
    INIT_POWER,
    INIT_PRECHARGE,
    INIT_MODE,
    INIT_AUTOREF1,
    INIT_AUTOREF2,

    IDLE,
    ACTIVATE,  // Open Row
    PRECHARGE, // Close Row
    READ,
    WRITE,
    REFRESH_PRECHARGE, // Precharge All
    REFRESH, // AutoRefresh
    WAIT
  } state_t;
  
  state_t state, next_state, post_delay_state;

  // input latch
  logic        read_r;
  logic        write_r;
  logic [15:0] data_write_r; // TODO convert to FIFO when burst write support is added

  logic        power_on_seq_complete;
  logic        cmd_complete;
  logic        udqm, ldqm; // udqm to a12, ldqm to a11
  logic        chip_addr;
  logic [1:0]  bank_addr;
  logic [12:0] row_addr;
  logic [9:0]  col_addr;

  logic [15:0] delay, wait_cycles;
  // rows open in every bank
  logic [3:0]  open_rows;
  logic [12:0] open_row_addrs [3:0];
  // read latency tracker
  logic [tCAS-1:0] cas_shift_r; 
  // refresh timer
  logic [15:0] refresh_timer;
  logic        pending_refresh;

  // command latch
  always_ff @(posedge clk) begin
    if (reset) begin
      cmd_ready <= 0;
      read_r <= 0;
      write_r <= 0;
    end else begin
      if (power_on_seq_complete) begin
        cmd_ready <= 1;
      end
      if (cmd_ready && (read || write)) begin
        cmd_ready <= 0;
        read_r <= read;
        write_r <= write;
        data_write_r <= data_write;
        {chip_addr, bank_addr, row_addr, col_addr} <= addr;
      end
      if (cmd_complete) begin
        cmd_ready <= 1;
        read_r <= 0;
        write_r <= 0;
      end
    end
  end
 
  assign sd_clk = clk;
  assign {sd_ras, sd_cas, sd_we} = sd_cmd;
  assign data_read = sd_data_in;
  assign data_read_val = cas_shift_r[0];

  // nextstate / delay (NOP)
  always_ff @(posedge clk) begin
    if (reset) begin
      state <= INIT_POWER;
    end else begin
      if (delay != 0) begin
        wait_cycles <= delay - 1;
        post_delay_state <= next_state;
        state <= WAIT;
      end else if (state == WAIT) begin
        if (wait_cycles == 0)
          state <= post_delay_state;
        else
          wait_cycles <= wait_cycles - 1;
      end else begin
        state <= next_state;
      end
    end
  end

  // sdram driver
  always_comb begin
    power_on_seq_complete = 0;
    cmd_complete = 0;
    next_state = IDLE;
    delay = '0;
    sd_cmd = CMD_NOP;
    sd_cs = '0;
    sd_bank = '0;
    sd_addr = '0;
    sd_drive_data = '0;
    sd_data_out = '0;

    case (state)
      IDLE : begin
        if (pending_refresh)
          if (|open_rows)
            next_state = REFRESH_PRECHARGE;
          else
            next_state = REFRESH_PRECHARGE;
        else if (write_r || read_r)
          if (open_rows[bank_addr] && (open_row_addrs[bank_addr] == row_addr)) begin
            if (read_r)
              next_state = READ;
            else if (write_r)
              next_state = WRITE;
          end else if (open_rows[bank_addr]) begin
            next_state = PRECHARGE;
          end else begin
            next_state = ACTIVATE;
          end
      end

      // Close row
      PRECHARGE : begin
        sd_cmd = CMD_PRECHG;
        delay = tRP;
        sd_bank = bank_addr;
        next_state = ACTIVATE;
      end

      // Open row
      ACTIVATE : begin
        // TODO back to back activates must wait tRC?
        sd_cmd = CMD_ACTIVE;
        sd_bank = bank_addr;
        sd_addr = row_addr;
        delay = tRCD;
        if (read_r)
          next_state = READ;
        else if (write_r)
          next_state = WRITE;
      end

      // Read from an opened row
      READ : begin
        sd_cmd = CMD_READ;
        sd_bank = bank_addr;
        sd_addr = col_addr;
        next_state = IDLE;
        cmd_complete = 1;
      end

      WRITE : begin
        sd_cmd = CMD_WRITE;
        sd_bank = bank_addr;
        sd_addr = col_addr;
        sd_data_out = data_write_r;
        sd_drive_data = 1;
        cmd_complete = 1;
      end

      // Precharge all rows before refresh
      REFRESH_PRECHARGE : begin
        sd_cmd = CMD_PRECHG;
        sd_addr[10] = 1'b1; // PrechargeAll
        delay = tRP;
        next_state = REFRESH;
      end

      // CBR Refresh
      REFRESH : begin
        sd_cmd = CMD_AUTOREF;
        delay = tRFC;
        next_state = IDLE;
      end

      // Power on Sequence
      INIT_POWER : begin
        delay = tPOD;
        next_state = INIT_PRECHARGE;
      end

      INIT_PRECHARGE : begin
        sd_cmd = CMD_PRECHG;
        sd_addr[10] = 1'b1; // PrechargeAll
        delay = tRP;
        next_state = INIT_MODE;
      end

      INIT_MODE : begin
        sd_cmd = CMD_MRS;
        sd_addr = MODE;
        delay = tMRD; // BOZO spec says 2 cycles
        next_state = INIT_AUTOREF1;
      end

      INIT_AUTOREF1 : begin
        sd_cmd = CMD_AUTOREF;
        delay = tRFC;
        next_state = INIT_AUTOREF2;
      end

      INIT_AUTOREF2 : begin
        sd_cmd = CMD_AUTOREF;
        delay = tRFC;
        next_state = IDLE;
        power_on_seq_complete = 1;
      end
    endcase
  end

  // valid read tracker
  always_ff @(posedge clk) begin
    if (reset) begin
      cas_shift_r <= 0;
    end else begin
      cas_shift_r[tCAS-1] <= (state == READ);
      for (int i = 0; i < tCAS-1; i++)
        cas_shift_r[i] <= cas_shift_r[i+1];
    end
  end

  // refresh timer
  always_ff @(posedge clk) begin
    if (reset) begin
      refresh_timer <= tREFI - 1;
      pending_refresh <= 0;
    end else begin
      if (refresh_timer == 0)
        refresh_timer <= tREFI - 1;
      else
        refresh_timer <= refresh_timer - 1;

      if (refresh_timer == 0)
        pending_refresh <= 1;
      else if (state == REFRESH)
        pending_refresh <= 0;
    end
  end

  // keep track of which row is open in each bank
  always_ff @(posedge clk) begin
    if (reset) begin
      open_rows <= '0;
    end else begin
      case (state)
        ACTIVATE : begin
          open_rows[bank_addr] <= 1'b1;
          open_row_addrs[bank_addr] <= row_addr;
        end
        REFRESH_PRECHARGE : begin
          open_rows <= '0; // precharge all
        end
        PRECHARGE : begin
          open_rows[bank_addr] <= '0;
        end
      endcase
    end
  end

endmodule // sdram
