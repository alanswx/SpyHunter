//============================================================================
//  Arcade: Pacman
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
	inout  [45:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        VGA_CLK,

	//Multiple resolutions are supported using different VGA_CE rates.
	//Must be based on CLK_VIDEO
	output        VGA_CE,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,

	//Base video clock. Usually equals to CLK_SYS.
	output        HDMI_CLK,

	//Multiple resolutions are supported using different HDMI_CE rates.
	//Must be based on CLK_VIDEO
	output        HDMI_CE,

	output  [7:0] HDMI_R,
	output  [7:0] HDMI_G,
	output  [7:0] HDMI_B,
	output        HDMI_HS,
	output        HDMI_VS,
	output        HDMI_DE,   // = ~(VBlank | HBlank)
	output  [1:0] HDMI_SL,   // scanlines fx

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	output  [7:0] HDMI_ARX,
	output  [7:0] HDMI_ARY,

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,    // 1 - signed audio samples, 0 - unsigned

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT
);

assign VGA_F1    = 0;
assign USER_OUT  = '1;
assign LED_USER  = ioctl_download;
assign LED_DISK  = 0;
assign LED_POWER = 0;

//assign HDMI_ARX = status[1] ? 8'd16 : status[2] ? 8'd4 : 8'd3;
//assign HDMI_ARY = status[1] ? 8'd9  : status[2] ? 8'd3 : 8'd4;
assign HDMI_ARX = status[1] ? 8'd16 : status[2] ? 8'd21 : 8'd20;
assign HDMI_ARY = status[1] ? 8'd9  : status[2] ? 8'd20 : 8'd21;

`include "build_id.v" 
localparam CONF_STR = {
	"A.KICKMAN;;",
	"F,rom;", // allow loading of alternate ROMs
	"-;",
	"O1,Aspect Ratio,Original,Wide;",
	"O2,Orientation,Vert,Horz;",
	"O35,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"-;",
	"O89,Lives,3,5,1,2;",
	"OAB,Bonus,10000,15000,20000,None;",
	"OC,Cabinet,Upright,Cocktail;",
	"OD,Alternate ghost names,No,Yes;",		
	"OEF,Coins,1 Coin 1 Play, Free Play, 2 Coins 1 Play, 1 Coin 2 Play",
	"-;",
	"R0,Reset;",
	"J1,Fire,Start 1P,Start 2P,Coin;",
	"V,v",`BUILD_DATE
};

////////////////////   CLOCKS   ///////////////////

wire clk_sys,clk_80M;
wire pll_locked;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys), // 40M
	.outclk_1(clk_80M), // 80M
	.locked(pll_locked)
);





reg ce_10m; // 10M
always @(posedge clk_sys) begin
	reg [1:0] div;
	div <= div + 1'd1;
	ce_10m <= !div;
end

///////////////////////////////////////////////////

wire [31:0] status;
wire  [1:0] buttons;
wire        forced_scandoubler;

wire        ioctl_download;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;

wire [10:0] ps2_key;

wire [15:0] joystick_0, joystick_1;
wire [15:0] joy = joystick_0 | joystick_1;

hps_io #(.STRLEN($size(CONF_STR)>>3)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.conf_str(CONF_STR),

	.buttons(buttons),
	.status(status),
	.forced_scandoubler(forced_scandoubler),

	.ioctl_download(ioctl_download),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),

	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.ps2_key(ps2_key)
);

wire       pressed = ps2_key[9];
wire [8:0] code    = ps2_key[8:0];
always @(posedge clk_sys) begin
	reg old_state;
	old_state <= ps2_key[10];
	
	if(old_state != ps2_key[10]) begin
		casex(code)
			'hX75: btn_up          <= pressed; // up
			'hX72: btn_down        <= pressed; // down
			'hX6B: btn_left        <= pressed; // left
			'hX74: btn_right       <= pressed; // right
			'h029: btn_fire1        <= pressed; // space
			'h014: btn_fire3        <= pressed; // ctrl

			'h005: btn_one_player  <= pressed; // F1
			'h006: btn_two_players <= pressed; // F2
			'h004: btn_coin        <= pressed; // F3

			'h003: btn_cheat       <= pressed; // F5
			
			// JPAC/IPAC/MAME Style Codes
			'h016: btn_start_1     <= pressed; // 1
			'h01E: btn_start_2     <= pressed; // 2
			'h02E: btn_coin_1      <= pressed; // 5
			'h036: btn_coin_2      <= pressed; // 6
			'h02D: btn_up_2        <= pressed; // R
			'h02B: btn_down_2      <= pressed; // F
			'h023: btn_left_2      <= pressed; // D
			'h034: btn_right_2     <= pressed; // G
			'h01C: btn_fire_2      <= pressed; // A

			'h0D: btn_van         <= pressed; // TAB
                        'h1A: btn_shift       <= pressed; // Y  35
                        'h12: btn_fire4       <= pressed; // shift left
                        'h11: btn_fire2       <= pressed; // alt left

		endcase
	end
end

reg btn_van = 0;
reg btn_shift = 0;
reg btn_fire1 = 0;
reg btn_fire2 = 0;
reg btn_fire3 = 0;
reg btn_fire4 = 0;


reg btn_up    = 0;
reg btn_down  = 0;
reg btn_right = 0;
reg btn_left  = 0;
reg btn_one_player  = 0;
reg btn_two_players = 0;
reg btn_coin = 0;
reg btn_cheat = 0;
reg btn_fire = 0;

reg btn_start_1=0;
reg btn_start_2=0;
reg btn_coin_1=0;
reg btn_coin_2=0;
reg btn_up_2=0;
reg btn_down_2=0;
reg btn_left_2=0;
reg btn_right_2=0;
reg btn_cheat_2=0;
reg btn_fire_2 = 0;

wire m_up     = ~status[2] ? btn_left  | joystick_0[1] | joystick_1[1] : btn_up    | joystick_0[3] | joystick_1[3];
wire m_down   = ~status[2] ? btn_right | joystick_0[0] | joystick_1[0] : btn_down  | joystick_0[2] | joystick_1[2];
wire m_left   = ~status[2] ? btn_down  | joystick_0[2] | joystick_1[2] : btn_left  | joystick_0[1] | joystick_1[1];
wire m_right  = ~status[2] ? btn_up    | joystick_0[3] | joystick_1[3] : btn_right | joystick_0[0] | joystick_1[0];
wire m_fire1   = btn_fire1 | joystick_0[4] | joystick_1[4];
wire m_fire2   = btn_fire2 | joystick_0[5] | joystick_1[5];
wire m_fire3   = btn_fire3 | joystick_0[6] | joystick_1[6];
wire m_fire4   = btn_fire4 | joystick_0[7] | joystick_1[7];
wire m_van = btn_van;
wire m_shift = btn_shift;


wire m_fire = btn_fire | btn_fire_2  | joy[4];


wire m_start1 = btn_one_player  | joy[5];
wire m_start2 = btn_two_players | joy[6];
wire m_coin   = btn_coin | joy[7];



wire hblank, vblank;
wire ce_vid = ce_10m;
wire hs, vs;
wire [3:0] r,g;
wire [3:0] b;


// 512x480
//arcade_rotate_fx #(224,596,12) arcade_video
//arcade_rotate_fx #(512,480,6) arcade_video
arcade_rotate_fx #(480,512,6) arcade_video
//arcade_rotate_fx #(289,224,12) arcade_video
//arcade_rotate_fx #(224,596,8) arcade_video
(
        .*,

        .clk_video(clk_sys),
        //.clk_video(clk_80m),
        .ce_pix(ce_vid),
		  //.ce_pix(clk_sys),
        .RGB_in({r[3:2],g[3:2],b[3:2]}),
        .HBlank(hblank),
        .VBlank(vblank),
        .HSync(hs),
        .VSync(vs),

        .fx(status[5:3]),
        .no_rotate(status[2])
);

assign AUDIO_S = 0;

spy_hunter spy_hunter(
        .clock_40(clk_sys),
	.reset(RESET | status[0] |  buttons[1]|ioctl_download),
        .video_r(r),
        .video_g(g),
        .video_b(b),
        .video_blankn(video_blankn),
	.video_vblank(vblank),
	.video_hblank(hblank),
        .video_hs(hs),
        .video_vs(vs),
        .video_csync(),
        .tv15Khz_mode(1'b0),
        .separate_audio(1'b0), // TODO - look at this
        .audio_out_l(AUDIO_L),
        .audio_out_r(AUDIO_R),
        .coin1(btn_coin),
        .coin2(1'b0),
        .shift(m_shift),
        .oil(m_fire4),
        .missile(m_fire2),
        .van(m_van),
        .smoke(m_fire3),
        .gun(m_fire1),
        .steering(steering),
        .gas(gas),
        .timer(1),
        .show_lamps(status[9]),
        .demo_sound(status[8]),
        .service(status[6]),
        //.sp_addr      ( sp_addr         ),
        //.sp_graphx32_do ( sp_do         )
	//.dn_addr(ioctl_addr[15:0]),
	//.dn_data(ioctl_dout),
	//.dn_wr(ioctl_wr)
);

wire  [7:0] steering;
wire  [7:0] gas;


spy_hunter_control spy_hunter_control(
        .clock_40(clk_sys),
        .reset(reset),
        .vsync(vs),
        .gas_plus(m_up),
        .gas_minus(m_down),
        .steering_plus(m_right),
        .steering_minus(m_left),
        .steering(steering),
        .gas(gas)
  );


endmodule

module joyonedir
(
	input        clk,
	input  [3:0] indir,
	output [3:0] outdir
);

reg  [3:0] mask = 0;
reg  [3:0] in1,in2;
wire [3:0] innew = in1 & ~in2;

assign outdir = in1 & mask;

always @(posedge clk) begin
	
	in1 <= indir;
	in2 <= in1;
	
	if(innew[0]) mask <= 1;
	if(innew[1]) mask <= 2;
	if(innew[2]) mask <= 4;
	if(innew[3]) mask <= 8;
end

endmodule
