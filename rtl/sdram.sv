// Module to drive dual Alliance Memory AS4C32M16SB module connected to DE10-Nano via GPIO

module sdram (
  input  logic clk,
  input  logic reset,

  // SOC interface
  input  logic        read,
  input  logic        write,
  input  logic [25:0] addr,  // {chip, bank[1:0], row[12:0], col[9:0]}
  input  logic [15:0] data_write,
  output logic [15:0] data_read,
  output logic        data_read_val,


  // SDRAM interface
  output logic        sd_clk,
  output logic        sd_cs,       // two chips
  output logic [1:0]  sd_bank,     // four banks per chip
  output logic [12:0] sd_addr,     // multiplexed address
  output logic        sd_ras,      // row address select
  output logic        sd_cas,      // column address select
  output logic        sd_we,       // write enable
  output logic [15:0] sd_data_out, // write data
  input  logic [15:0] sd_data_in   // read data
);

  // Timings (cycles at 50MHz (20ns))
  localparam tCAS = 2;
  localparam tRAS = 3;  // Row Active time (min.) 42/42 ns
  localparam tRC  = 4;  // Row Cycle time (min.) 60/63 ns
  localparam tRCD = 3; // BOZO TODO: not in datasheet
  //localparam tCK3 = 1;  // Clock Cycle time (min.) 6/7 ns
  //localparam tAC3 = 1;  // Access time from CLK (max.) 5/5.4 
  localparam POWER_ON_DELAY = 10000; // 200us @ 50MHz
  localparam MODE_WRITE_DELAY = 2;
  localparam AUTOREF_DELAY = 4; // 63ns

  // Commands
  localparam CMD_NOP      = 3'b111;
  localparam CMD_ACTIVE   = 3'b011;
  localparam CMD_READ     = 3'b101;
  localparam CMD_WRITE    = 3'b100;
  localparam CMD_PRECHG   = 3'b010;
  localparam CMD_AUTOREF  = 3'b001;
  localparam CMD_MRS      = 3'b000;

  // SDRAM mode
  localparam BURST_LENGTH   = 3'b000; // 000 = none, 001 = 2, 010 = 4, 011 = 8
  localparam BURST_TYPE     = 1'b0;   // 0 = sequential, 1 = interleaved
  localparam CAS_LATENCY    = 3'd2;   // 2/3 allowed
  localparam TEST_MODE      = 2'b00;  // 0 = disabled
  localparam NO_WRITE_BURST = 1'b1;   // 1 = disabled

  localparam MODE = { 3'b000, NO_WRITE_BURST, TEST_MODE, CAS_LATENCY, BURST_TYPE, BURST_LENGTH};

  typedef enum {
    INIT_POWER,
    INIT_PRECHARGE,
    INIT_AUTO_REFRESH_1,
    INIT_AUTO_REFRESH_2,
    INIT_MRS,

    IDLE,
    ACTIVATE,  // open row
    PRECHARGE, // close row
    READ,
    READ_COMPELTE,
    WRITE,
    WRITE_COMPLETE,
    WAIT,
    REFRESH
  } state_t;
  
  state_t state, next_state, post_delay_state;

  logic        chip_addr;
  logic [1:0]  bank_addr;
  logic [12:0] row_addr;
  logic [9:0]  col_addr;

  logic [2:0] sd_cmd;
  logic [13:0] open_rows [3:0]; // MSB is valid bit
  logic [14:0] delay;

  assign {chip_addr, bank_addr, row_addr, col_addr} = addr;

  assign sd_clk = clk;
  assign data_out = sd_data;
  assign {sd_ras, sd_cas, sd_we} = sd_cmd;


  always_ff @(posedge clk) begin
    if (reset) begin
      state <= INIT_POWER;
      open_rows[0] <= '0;
      open_rows[1] <= '0;
      open_rows[2] <= '0;
      open_rows[3] <= '0;
    end else begin
      state <= IDLE;

      case (state)
        INIT_POWER : begin
          delay <= POWER_ON_DELAY;
          post_delay_state <= INIT_PRECHARGE;
          state <= WAIT;
        end

        INIT_PRECHARGE : begin
          state <= INIT_AUTO_REFRESH_1;
        end

        INIT_AUTO_REFRESH_1 : begin
          delay <= AUTOREF_DELAY;
          post_delay_state <= INIT_AUTO_REFRESH_2;
          state <= WAIT;
        end
        INIT_AUTO_REFRESH_2 : begin
          delay <= AUTOREF_DELAY;
          post_delay_state <= INIT_MRS;
          state <= WAIT;
        end

        INIT_MRS : begin
          delay <= MODE_WRITE_DELAY;
          post_delay_state <= IDLE;
          state <= WAIT;
        end

        IDLE : begin // TODO
          if (read || write) begin
            // if row already open, skip ACTIVATE
            if (open_rows[bank_addr][13] && (row_addr == open_rows[bank_addr][12:0])) begin
              if (read)
                state <= READ;
              else if (write)
                state <= WRITE;
            
            // else, open row
            end else begin
              open_rows[bank_addr] <= {1'b1, row_addr};
              state <= ACTIVATE;
              if (read)
                post_delay_state <= READ;
              else if (write)
                post_delay_state <= WRITE;
            end
          end
        end

        ACTIVATE : begin
          delay <= tRCD;
          post_delay_state <= IDLE;
          state <= WAIT;
        end

        READ : begin
          delay <=
          post_delay_state <= READ_COMPELTE;
          state <= WAIT;
        end

        READ_COMPELTE : begin
          state <= IDLE;
        end

        WRITE : begin
          delay <=
          post_delay_state <= WRITE_COMPLETE;
          state <= WAIT;
        end

        WRITE_COMPLETE : begin
          state <= IDLE;
        end

        WAIT : begin
          if (delay == 0)
            state <= post_delay_state;
          else
            delay <= delay - 1'd1;
        end
      endcase
    end
  end


  always_comb begin
    sd_cmd = CMD_NOP;
    sd_cs = 0; // TODO use both chips
    sd_bank = 'x;
    sd_addr = 'x;
    sd_data = 'z;

    case (state)
      INIT_PRECHARGE : begin
        sd_cmd = CMD_PRECHG;
      end

      REFRESH,
      INIT_AUTO_REFRESH_1,
      INIT_AUTO_REFRESH_2 : begin
        sd_cmd = CMD_AUTOREF;
      end

      INIT_MRS : begin
        // TODO initialize both chips (cs=1,0)
        //sd_cs = chip_addr;
        sd_cmd = CMD_MRS;
        sd_addr = MODE;
      end

      ACTIVATE : begin
        sd_cmd = CMD_ACTIVE;
        sd_bank = bank_addr;
        sd_addr = row_addr;
      end

      READ: begin
        sd_cmd = CMD_READ;
        sd_bank = bank_addr;
        sd_addr = col_addr;
      end

      READ_COMPELTE : begin
        data_out_val = 1'b1;
      end

      WRITE : begin
        sd_cmd = CMD_WRITE;
        sd_bank = bank_addr;
        sd_addr = col_addr;
        sd_data = data_in;
      end

      default;
    endcase
  end



endmodule // sdram
