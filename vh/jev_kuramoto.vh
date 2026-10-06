// Macro blackbox. Signal ports match rtl/jev_kuramoto.v.
// VPWR and VGND are the sky130_fd_sc_hd supplies of the hardened view.
// Another public PDK synthesizes the RTL and uses that PDK's supply names.
module jev_kuramoto(
`ifdef USE_POWER_PINS
  inout VPWR,
  inout VGND,
`endif
  input clk,
  input rst,
  input src0,
  input src1,
  input src2,
  input src3,
  input[3:0] src_en,
  input omega_we,
  input[31:0] omega_d,
  output[31:0] phase_out,
  output[31:0] freq_out,
  output[3:0] wrap,
  output[5:0] near,
  output[3:0] fault,
  output[3:0] lost,
  output[3:0] locked,
  output[3:0] glitch,
  output coherent,
  output quorum,
  output ec_tick,
  output[3:0] status
);
endmodule
