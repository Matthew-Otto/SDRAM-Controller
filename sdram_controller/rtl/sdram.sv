// Module to drive dual Alliance Memory AS4C32M16SB module connected to DE10-Nano via GPIO

// 2048 byte rows

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
  output logic        sdram_clk,
  output logic        sdram_cs,        // two chips
  output logic [1:0]  sdram_bank,      // four banks per chip
  output logic [12:0] sdram_addr,      // multiplexed address
  output logic        sdram_ras,       // row address select
  output logic        sdram_cas,       // column address select
  output logic        sdram_we,        // write enable
  input  logic [15:0] sdram_data_in,   // read data
  output logic [15:0] sdram_data_out,  // write data
  output logic        sdram_drive_data // tristate driver enable
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
  localparam tRC      = 16'(int'((tRC_ns + tCK_ns - 1) / tCK_ns) - 1);  // Row cycle time (same bank)
  localparam tRFC     = 16'(int'((tRFC_ns + tCK_ns - 1) / tCK_ns) - 1);  // Refresh cycle time
  localparam tRCD     = 16'(int'((tRCD_ns + tCK_ns - 1) / tCK_ns) - 1);  // RAS# to CAS# delay (same bank)
  localparam tRP      = 16'(int'((tRP_ns + tCK_ns - 1) / tCK_ns) - 1);  // Precharge to refresh/row activate command (same bank)
  localparam tRRD     = 16'(int'((tRRD_ns + tCK_ns - 1) / tCK_ns) - 1);  // Row activate to row activate delay (different banks) 
  localparam tRAS     = 16'(int'((tRAS_min_ns + tCK_ns - 1) / tCK_ns) - 1);  // Row activate to precharge time (same bank) (min)
  localparam tWR      = 16'(int'((tWR_ns + tCK_ns - 1) / tCK_ns) - 1);  // Write recovery
  localparam tREFI    = 16'(int'((tREFI_ns + tCK_ns - 1) / tCK_ns) - 1);  // Refresh period
  localparam tPOD     = 16'(int'((tPOD_ns + tCK_ns - 1) / tCK_ns) - 1);  // Power on delay
  localparam tMRD     = 16'(int'((tMRD_ns + tCK_ns - 1) / tCK_ns) - 1);  // Mode register set cycle time

  // SDRAM mode settings
  localparam BURST_LENGTH   = 3'b011; // 000 = none, 001 = 2, 010 = 4, 011 = 8
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
  } sdram_cmd;

  // States
  typedef enum {
    INIT_POWER,
    INIT_PRECHARGE0,
    INIT_PRECHARGE1,
    INIT_MODE0,
    INIT_MODE1,
    INIT_AUTOREF1,
    INIT_AUTOREF2,

    IDLE,
    ACTIVATE,  // Open Row
    PRECHARGE, // Close Row
    READ,
    READ_BURST,
    WRITE,
    REFRESH_PRECHARGE0, // Precharge All
    REFRESH_PRECHARGE1, // Precharge All
    REFRESH0, // AutoRefresh
    REFRESH1, // AutoRefresh
    WAIT
  } state_t;
  
  state_t state, next_state, post_delay_state;

  // input latch
  logic        read_b;
  logic        write_b;
  logic [25:0] addr_b;
  logic [15:0] data_write_b;

  logic        chip_addr, input_chip_addr;
  logic [1:0]  bank_addr, input_bank_addr;
  logic [12:0] row_addr, input_row_addr;
  logic [9:0]  col_addr, input_col_addr;

  logic        power_on_seq_complete;
  logic        cmd_complete;
  logic        udqm, ldqm; // udqm to a12, ldqm to a11
  logic [2:0]  burst_count, next_burst_count;

  logic [15:0] delay, wait_cycles;
  // rows open in every bank
  logic [7:0]  open_rows;
  logic [12:0] open_row_addrs [7:0];
  // read latency tracker
  logic [tCAS-1:0] cas_shift_r; 
  // refresh timer
  logic [15:0] refresh_timer;
  logic        pending_refresh;
  
  assign cmd_ready = ((~read_b && ~write_b) || cmd_complete) && power_on_seq_complete;
  assign {chip_addr, bank_addr, row_addr, col_addr} = addr_b;
  assign {input_chip_addr, input_bank_addr, input_row_addr, input_col_addr} = addr;

  assign sdram_clk = clk;
  assign {sdram_ras, sdram_cas, sdram_we} = sdram_cmd;
  assign data_read = sdram_data_in;
  assign data_read_val = cas_shift_r[0];
  
  // input command latch
  always_ff @(posedge clk) begin
    if (reset) begin
      read_b <= 0;
      write_b <= 0;
    end else if (cmd_ready) begin
      if (read || write) begin
        read_b <= read;
        write_b <= write;
      end else begin
        read_b <= 0;
        write_b <= 0;
      end
    end

    if (reset)
      power_on_seq_complete <= 0;
    else if (state == INIT_AUTOREF2)
      power_on_seq_complete <= 1;

    if (cmd_ready && (read || write)) begin
      addr_b <= addr;
      data_write_b <= data_write;
    end
  end

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

    burst_count <= next_burst_count;
  end

  always_comb begin
    cmd_complete = 0;
    next_state = IDLE;
    next_burst_count = 0;
    delay = '0;
    sdram_cmd = CMD_NOP;
    sdram_cs = '0;
    sdram_bank = '0;
    sdram_addr = '0;
    sdram_drive_data = '0;
    sdram_data_out = '0;

    case (state)
      IDLE : begin
        if (pending_refresh)
          if (|open_rows)
            next_state = REFRESH_PRECHARGE0;
          else
            next_state = REFRESH0;
        else if (write_b || read_b)
          if (open_rows[{chip_addr,bank_addr}]) begin
            if (open_row_addrs[{chip_addr,bank_addr}] == row_addr) begin
              if (read_b)
                next_state = READ;
              else if (write_b)
                next_state = WRITE;
            end else begin
              next_state = PRECHARGE;
            end
          end else begin
            next_state = ACTIVATE;
          end
        else
          next_state = IDLE;
      end

      // Close row
      PRECHARGE : begin
        sdram_cmd = CMD_PRECHG;
        sdram_cs = chip_addr;
        sdram_bank = bank_addr;
        delay = tRP;
        next_state = ACTIVATE;
      end

      // Open row
      ACTIVATE : begin
        // TODO back to back activates must wait tRC?
        sdram_cmd = CMD_ACTIVE;
        sdram_cs = chip_addr;
        sdram_bank = bank_addr;
        sdram_addr = row_addr;
        delay = tRCD;
        if (read_b)
          next_state = READ;
        else if (write_b)
          next_state = WRITE;
      end

      // Read from an opened row
      READ : begin
        sdram_cmd = CMD_READ;
        sdram_cs = chip_addr;
        sdram_bank = bank_addr;
        sdram_addr = {3'b0,col_addr};
        next_state = READ_BURST;
        next_burst_count = 3'd6;
      end
      
      READ_BURST : begin
        if (burst_count != 0) begin
          next_burst_count = burst_count - 1;
          next_state = READ_BURST;
        end else begin
          cmd_complete = 1;

          // bypass idle state for back-to-back reads
          if (pending_refresh)
            if (|open_rows)
              next_state = REFRESH_PRECHARGE0;
            else
              next_state = REFRESH0;
          else if (write || read)
            if (open_rows[{input_chip_addr,input_bank_addr}]) begin
              if (open_row_addrs[{input_chip_addr,input_bank_addr}] == input_row_addr) begin
                if (read)
                  next_state = READ;
                else if (write) // TODO: may need to enforce a delay here 
                  next_state = WRITE;
              end else begin
                next_state = PRECHARGE;
              end
            end else begin
              next_state = ACTIVATE;
            end
          else
            next_state = IDLE;
        end
      end

      WRITE : begin
        sdram_cmd = CMD_WRITE;
        sdram_cs = chip_addr;
        sdram_bank = bank_addr;
        sdram_addr = {3'b0,col_addr};
        sdram_data_out = data_write_b;
        sdram_drive_data = 1;
        cmd_complete = 1;

        // bypass idle state for back-to-back writes
        if (pending_refresh)
          if (|open_rows)
            next_state = REFRESH_PRECHARGE0;
          else
            next_state = REFRESH0;
        else if (write || read)
          if (open_rows[{input_chip_addr,input_bank_addr}]) begin
            if (open_row_addrs[{input_chip_addr,input_bank_addr}] == input_row_addr) begin
              if (read) // TODO: may need to enforce a delay here 
                next_state = READ;
              else if (write)
                next_state = WRITE;
            end else begin
              next_state = PRECHARGE;
            end
          end else begin
            next_state = ACTIVATE;
          end
        else
          next_state = IDLE;
      end

      // Precharge all rows before refresh
      REFRESH_PRECHARGE0 : begin
        sdram_cs = 0;
        sdram_cmd = CMD_PRECHG;
        sdram_addr[10] = 1'b1; // PrechargeAll
        next_state = REFRESH_PRECHARGE1;
      end
      REFRESH_PRECHARGE1 : begin
        sdram_cs = 1;
        sdram_cmd = CMD_PRECHG;
        sdram_addr[10] = 1'b1; // PrechargeAll
        delay = tRP-1; // -1 due to chip interleaving
        next_state = REFRESH0;
      end

      // CBR Refresh
      REFRESH0 : begin
        sdram_cs = 0;
        sdram_cmd = CMD_AUTOREF;
        next_state = REFRESH1;
      end
      REFRESH1 : begin
        sdram_cs = 1;
        sdram_cmd = CMD_AUTOREF;
        delay = tRFC;
        next_state = IDLE;
      end

      // Power on Sequence
      INIT_POWER : begin
        delay = tPOD;
        next_state = INIT_PRECHARGE0;
      end

      INIT_PRECHARGE0 : begin
        sdram_cs = 0;
        sdram_cmd = CMD_PRECHG;
        sdram_addr[10] = 1'b1; // PrechargeAll
        next_state = INIT_PRECHARGE1;
      end
      INIT_PRECHARGE1 : begin
        sdram_cs = 1;
        sdram_cmd = CMD_PRECHG;
        sdram_addr[10] = 1'b1; // PrechargeAll
        delay = tRP;
        next_state = INIT_MODE0;
      end

      INIT_MODE0 : begin
        sdram_cs = 0;
        sdram_cmd = CMD_MRS;
        sdram_addr = MODE;
        next_state = INIT_MODE1;
      end
      INIT_MODE1 : begin
        sdram_cs = 1;
        sdram_cmd = CMD_MRS;
        sdram_addr = MODE;
        delay = tMRD;
        next_state = INIT_AUTOREF1;
      end

      INIT_AUTOREF1 : begin
        sdram_cmd = CMD_AUTOREF;
        delay = tRFC;
        next_state = INIT_AUTOREF2;
      end

      INIT_AUTOREF2 : begin
        sdram_cmd = CMD_AUTOREF;
        delay = tRFC;
        next_state = IDLE;
      end
    endcase
  end

  // valid read tracker
  always_ff @(posedge clk) begin
    if (reset) begin
      cas_shift_r <= 0;
    end else begin
      // BOZO TODO reenable BURSTS
      //cas_shift_r[tCAS-1] <= ((state == READ) || (state == READ_BURST));
      cas_shift_r[tCAS-1] <= ((state == READ));
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
      else if (state == REFRESH1)
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
          open_rows[{chip_addr,bank_addr}] <= 1'b1;
        end
        PRECHARGE : begin
          open_rows[{chip_addr,bank_addr}] <= '0;
        end
        REFRESH_PRECHARGE0 : begin
          open_rows[3:0] <= '0; // precharge all
        end
        REFRESH_PRECHARGE1 : begin
          open_rows[7:4] <= '0; // precharge all
        end
      endcase
    end

    if (state == ACTIVATE)
      open_row_addrs[{chip_addr,bank_addr}] <= row_addr;
  end

endmodule : sdram
