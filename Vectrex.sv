//============================================================================
//  Vectrex
//
//  Port to MiSTer
//  Copyright (C) 2017 Sorgelig
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [44:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	output  [7:0] VIDEO_ARX,
	output  [7:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S, // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)
	input         TAPE_IN,

	// SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE
);

assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = 0;

assign LED_USER  = ioctl_download;
assign LED_DISK  = 0;
assign LED_POWER = 0;

assign VIDEO_ARX = status[1] ? 8'd16 : 8'd4;
assign VIDEO_ARY = status[1] ? 8'd9  : 8'd3; 

`include "build_id.v" 
localparam CONF_STR = {
	"VECTREX;;",
	"-;",
	"F,VEC;",
	"-;",
	"O1,Aspect ratio,4:3,16:9;",
	"-;",
	"R6,Reset;",
	"J1,Button 1,Button 2,Button 3,Button 4;",
	"V,v1.00.",`BUILD_DATE
};

////////////////////   CLOCKS   ///////////////////

wire clk_sys, clk_vga;
wire pll_locked;
		
pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys),
	.outclk_1(clk_vga),
	.locked(pll_locked)
);

///////////////////////////////////////////////////

wire [31:0] status;
wire  [1:0] buttons;

wire [15:0] joystick_0, joystick_1;
wire [15:0] joya_0, joya_1;
wire        ioctl_download;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;

hps_io #(.STRLEN($size(CONF_STR)>>3)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.conf_str(CONF_STR),

	.buttons(buttons),
	.status(status),

	.ioctl_download(ioctl_download),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(0),

	.joystick_analog_0(joya_0),
	.joystick_analog_1(joya_1),
	.joystick_0(joystick_0),
	.joystick_1(joystick_1)
);

wire [9:0] audio;
assign AUDIO_L = {audio, 6'd0};
assign AUDIO_R = {audio, 6'd0};
assign AUDIO_S = 0;
assign AUDIO_MIX = 0;

wire reset_req = (RESET | status[0] | status[6] | buttons[1] | ioctl_download);
reg reset;
always @(posedge clk_sys) begin
	integer timeout;
	
	if(timeout < 12000000) begin
		reset <= 1;
		timeout <= timeout + 1;
	end else begin
		reset <= 0;
	end

	if(reset_req) timeout <= 0;
end

wire vs,hs;
wire hblank, vblank;

assign CLK_VIDEO = clk_vga;
assign CE_PIXEL = 1;

assign VGA_HS = ~hs;
assign VGA_VS = ~vs;
assign VGA_DE = ~(hblank | vblank);
assign {VGA_R[3:0],VGA_G[3:0],VGA_B[3:0]} = {VGA_R[7:4],VGA_G[7:4],VGA_B[7:4]};

reg [14:0] addr_mask;
always @(posedge clk_sys) begin
	reg old_download;
	
	old_download <= ioctl_download;
	if(~old_download & ioctl_download) addr_mask <= 0;
	if(ioctl_download && ioctl_wr && (ioctl_addr[14:0] & ~addr_mask)) addr_mask <= ((addr_mask<<1)|15'd1);
end

vectrex vectrex
(
	.reset(reset),

	.clock_24(clk_vga),
	.clock_12(clk_sys),

	.cart_data(ioctl_dout),
	.cart_addr(ioctl_addr),
	.cart_mask(addr_mask),
	.cart_wr(ioctl_wr & ioctl_download),
	
	.video_r(VGA_R[7:4]),
	.video_g(VGA_G[7:4]),
	.video_b(VGA_B[7:4]),

	.video_hs(hs),
	.video_vs(vs),
	.video_hblank(hblank),
	.video_vblank(vblank),

	.audio_out(audio),
	
	.up_1(joystick_0[4]),
	.dn_1(joystick_0[5]),
	.lf_1(joystick_0[6]),
	.rt_1(joystick_0[7]),
	.pot_x_1(joya_0[7:0]  ? joya_0[7:0]   : {joystick_0[1], {7{joystick_0[0]}}}),
	.pot_y_1(joya_0[15:8] ? ~joya_0[15:8] : {joystick_0[2], {7{joystick_0[3]}}}),

	.up_2(joystick_1[4]),
	.dn_2(joystick_1[5]),
	.lf_2(joystick_1[6]),
	.rt_2(joystick_1[7]),
	.pot_x_2(joya_1[7:0]  ? joya_1[7:0]   : {joystick_1[1], {7{joystick_1[0]}}}),
	.pot_y_2(joya_1[15:8] ? ~joya_1[15:8] : {joystick_1[2], {7{joystick_1[3]}}})
);

endmodule