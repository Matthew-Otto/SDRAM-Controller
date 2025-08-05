// module to map SDRAM controller IO to GPIO pins

module sdram_gpio_map (
  // SDRAM interface
  input  logic        sdram_clk,
  input  logic        sdram_cs,         // two chips
  input  logic [1:0]  sdram_bank,       // four banks per chip
  input  logic [12:0] sdram_addr,       // multiplexed address
  input  logic        sdram_ras,        // row address select
  input  logic        sdram_cas,        // column address select
  input  logic        sdram_we,         // write enable
  output logic [15:0] sdram_data_in,    // read data
  input  logic [15:0] sdram_data_out,   // write data
  input  logic        sdram_drive_data, // tristate driver enable

  // GPIO
  inout  logic [35:0] GPIO
);

  // wire sdram signals to GPIO0
  assign GPIO[32] = sdram_addr[0];  // PIN_Y11
  assign GPIO[33] = sdram_addr[1];  // PIN_AA26
  assign GPIO[34] = sdram_addr[2];  // PIN_AA13
  assign GPIO[35] = sdram_addr[3];  // PIN_AA11
  assign GPIO[25] = sdram_addr[4];  // PIN_W11
  assign GPIO[22] = sdram_addr[5];  // PIN_Y19
  assign GPIO[23] = sdram_addr[6];  // PIN_AB23
  assign GPIO[20] = sdram_addr[7];  // PIN_AC23
  assign GPIO[21] = sdram_addr[8];  // PIN_AC22
  assign GPIO[18] = sdram_addr[9];  // PIN_C12
  assign GPIO[31] = sdram_addr[10]; // PIN_AB26
  assign GPIO[19] = sdram_addr[11]; // PIN_AD17
  assign GPIO[16] = sdram_addr[12]; // PIN_D12
  assign GPIO[29] = sdram_bank[0];  // PIN_Y17
  assign GPIO[30] = sdram_bank[1];  // PIN_AB25
  assign GPIO[24] = sdram_we;       // PIN_AA19
  assign GPIO[26] = sdram_cas;      // PIN_AA18
  assign GPIO[27] = sdram_ras;      // PIN_W14
  assign GPIO[28] = sdram_cs;       // PIN_Y18
  assign GPIO[17] = sdram_clk;      // PIN_AD20

  assign GPIO[1] = sdram_drive_data ? sdram_data_out[0] : 1'bz;   // PIN_E8
  assign GPIO[0] = sdram_drive_data ? sdram_data_out[1] : 1'bz;   // PIN_V12
  assign GPIO[3] = sdram_drive_data ? sdram_data_out[2] : 1'bz;   // PIN_D11
  assign GPIO[2] = sdram_drive_data ? sdram_data_out[3] : 1'bz;   // PIN_W12
  assign GPIO[5] = sdram_drive_data ? sdram_data_out[4] : 1'bz;   // PIN_AH13
  assign GPIO[4] = sdram_drive_data ? sdram_data_out[5] : 1'bz;   // PIN_D8
  assign GPIO[7] = sdram_drive_data ? sdram_data_out[6] : 1'bz;   // PIN_AH14
  assign GPIO[6] = sdram_drive_data ? sdram_data_out[7] : 1'bz;   // PIN_AF7
  assign GPIO[15] = sdram_drive_data ? sdram_data_out[8] : 1'bz;  // PIN_AE24
  assign GPIO[14] = sdram_drive_data ? sdram_data_out[9] : 1'bz;  // PIN_AD23
  assign GPIO[13] = sdram_drive_data ? sdram_data_out[10] : 1'bz; // PIN_AE6
  assign GPIO[12] = sdram_drive_data ? sdram_data_out[11] : 1'bz; // PIN_AE23
  assign GPIO[11] = sdram_drive_data ? sdram_data_out[12] : 1'bz; // PIN_AG14
  assign GPIO[10] = sdram_drive_data ? sdram_data_out[13] : 1'bz; // PIN_AD5
  assign GPIO[8] = sdram_drive_data ? sdram_data_out[14] : 1'bz;  // PIN_AF4
  assign GPIO[9] = sdram_drive_data ? sdram_data_out[15] : 1'bz;  // PIN_AH3

  assign sdram_data_in[0] = GPIO[1];   // PIN_E8
  assign sdram_data_in[1] = GPIO[0];   // PIN_V12
  assign sdram_data_in[2] = GPIO[3];   // PIN_D11
  assign sdram_data_in[3] = GPIO[2];   // PIN_W12
  assign sdram_data_in[4] = GPIO[5];   // PIN_AH13
  assign sdram_data_in[5] = GPIO[4];   // PIN_D8
  assign sdram_data_in[6] = GPIO[7];   // PIN_AH14
  assign sdram_data_in[7] = GPIO[6];   // PIN_AF7
  assign sdram_data_in[8] = GPIO[15];  // PIN_AE24
  assign sdram_data_in[9] = GPIO[14];  // PIN_AD23
  assign sdram_data_in[10] = GPIO[13]; // PIN_AE6
  assign sdram_data_in[11] = GPIO[12]; // PIN_AE23
  assign sdram_data_in[12] = GPIO[11]; // PIN_AG14
  assign sdram_data_in[13] = GPIO[10]; // PIN_AD5
  assign sdram_data_in[14] = GPIO[8];  // PIN_AF4
  assign sdram_data_in[15] = GPIO[9];  // PIN_AH3

endmodule : sdram_gpio_map
