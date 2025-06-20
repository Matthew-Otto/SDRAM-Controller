// wrapper module for SDRAM controller that maps IO to GPIO pins

module sdram_gpio #(parameter FREQ = 50000000) (
  input  logic        clk,
  input  logic        reset,

  // SOC interface
  input  logic        read,
  input  logic        write,
  input  logic [25:0] addr,  // {chip, bank[1:0], row[12:0], col[9:0]}
  output logic        cmd_ready,
  input  logic [15:0] data_write,
  output logic [15:0] data_read,
  output logic        data_read_val,

  inout  logic [35:0] GPIO
);

  logic        DQ_Write; // enable tristate DQ
  logic [15:0] SDRAM_DQ_out;
  logic [15:0] SDRAM_DQ_in;
  logic [12:0] SDRAM_A;
  logic        SDRAM_nWE;
  logic        SDRAM_nCAS;
  logic        SDRAM_nRAS;
  logic        SDRAM_nCS;
  logic  [1:0] SDRAM_BA;
  logic        SDRAM_CLK;

  // wire sdram signals to GPIO0
  assign GPIO[32] = SDRAM_A[0];  // PIN_Y11
  assign GPIO[33] = SDRAM_A[1];  // PIN_AA26
  assign GPIO[34] = SDRAM_A[2];  // PIN_AA13
  assign GPIO[35] = SDRAM_A[3];  // PIN_AA11
  assign GPIO[25] = SDRAM_A[4];  // PIN_W11
  assign GPIO[22] = SDRAM_A[5];  // PIN_Y19
  assign GPIO[23] = SDRAM_A[6];  // PIN_AB23
  assign GPIO[20] = SDRAM_A[7];  // PIN_AC23
  assign GPIO[21] = SDRAM_A[8];  // PIN_AC22
  assign GPIO[18] = SDRAM_A[9];  // PIN_C12
  assign GPIO[31] = SDRAM_A[10]; // PIN_AB26
  assign GPIO[19] = SDRAM_A[11]; // PIN_AD17
  assign GPIO[16] = SDRAM_A[12]; // PIN_D12
  assign GPIO[29] = SDRAM_BA[0]; // PIN_Y17
  assign GPIO[30] = SDRAM_BA[1]; // PIN_AB25
  assign GPIO[24] = SDRAM_nWE;   // PIN_AA19
  assign GPIO[26] = SDRAM_nCAS;  // PIN_AA18
  assign GPIO[27] = SDRAM_nRAS;  // PIN_W14
  assign GPIO[28] = SDRAM_nCS;   // PIN_Y18
  assign GPIO[17] = SDRAM_CLK;   // PIN_AD20

  assign GPIO[1] = DQ_Write ? SDRAM_DQ_out[0] : 1'bz;   // PIN_E8
  assign GPIO[0] = DQ_Write ? SDRAM_DQ_out[1] : 1'bz;   // PIN_V12
  assign GPIO[3] = DQ_Write ? SDRAM_DQ_out[2] : 1'bz;   // PIN_D11
  assign GPIO[2] = DQ_Write ? SDRAM_DQ_out[3] : 1'bz;   // PIN_W12
  assign GPIO[5] = DQ_Write ? SDRAM_DQ_out[4] : 1'bz;   // PIN_AH13
  assign GPIO[4] = DQ_Write ? SDRAM_DQ_out[5] : 1'bz;   // PIN_D8
  assign GPIO[7] = DQ_Write ? SDRAM_DQ_out[6] : 1'bz;   // PIN_AH14
  assign GPIO[6] = DQ_Write ? SDRAM_DQ_out[7] : 1'bz;   // PIN_AF7
  assign GPIO[15] = DQ_Write ? SDRAM_DQ_out[8] : 1'bz;  // PIN_AE24
  assign GPIO[14] = DQ_Write ? SDRAM_DQ_out[9] : 1'bz;  // PIN_AD23
  assign GPIO[13] = DQ_Write ? SDRAM_DQ_out[10] : 1'bz; // PIN_AE6
  assign GPIO[12] = DQ_Write ? SDRAM_DQ_out[11] : 1'bz; // PIN_AE23
  assign GPIO[11] = DQ_Write ? SDRAM_DQ_out[12] : 1'bz; // PIN_AG14
  assign GPIO[10] = DQ_Write ? SDRAM_DQ_out[13] : 1'bz; // PIN_AD5
  assign GPIO[8] = DQ_Write ? SDRAM_DQ_out[14] : 1'bz;  // PIN_AF4
  assign GPIO[9] = DQ_Write ? SDRAM_DQ_out[15] : 1'bz;  // PIN_AH3

  assign SDRAM_DQ_in[0] = GPIO[1];   // PIN_E8
  assign SDRAM_DQ_in[1] = GPIO[0];   // PIN_V12
  assign SDRAM_DQ_in[2] = GPIO[3];   // PIN_D11
  assign SDRAM_DQ_in[3] = GPIO[2];   // PIN_W12
  assign SDRAM_DQ_in[4] = GPIO[5];   // PIN_AH13
  assign SDRAM_DQ_in[5] = GPIO[4];   // PIN_D8
  assign SDRAM_DQ_in[6] = GPIO[7];   // PIN_AH14
  assign SDRAM_DQ_in[7] = GPIO[6];   // PIN_AF7
  assign SDRAM_DQ_in[8] = GPIO[15];  // PIN_AE24
  assign SDRAM_DQ_in[9] = GPIO[14];  // PIN_AD23
  assign SDRAM_DQ_in[10] = GPIO[13]; // PIN_AE6
  assign SDRAM_DQ_in[11] = GPIO[12]; // PIN_AE23
  assign SDRAM_DQ_in[12] = GPIO[11]; // PIN_AG14
  assign SDRAM_DQ_in[13] = GPIO[10]; // PIN_AD5
  assign SDRAM_DQ_in[14] = GPIO[8];  // PIN_AF4
  assign SDRAM_DQ_in[15] = GPIO[9];  // PIN_AH3

  sdram #(.FREQ(FREQ)) sdram_i (
    .clk,
    .reset,
    .read,
    .write,
    .addr,
    .cmd_ready,
    .data_write,
    .data_read,
    .data_read_val,
    .sd_clk(SDRAM_CLK),
    .sd_cs(SDRAM_nCS),
    .sd_bank(SDRAM_BA),
    .sd_addr(SDRAM_A),
    .sd_ras(SDRAM_nRAS),
    .sd_cas(SDRAM_nCAS),
    .sd_we(SDRAM_nWE),
    .sd_data_in(SDRAM_DQ_in),
    .sd_data_out(SDRAM_DQ_out),
    .sd_drive_data(DQ_Write)
  );

endmodule  // sdram_gpio
