///////////////////////////////////////////////////////////////////////////////////////////////////
// Company: <Name>
//
// File: Not_gate.v
// File history:
//      <Revision number>: <Date>: <Comments>
//      <Revision number>: <Date>: <Comments>
//      <Revision number>: <Date>: <Comments>
//
// Description: 
//
// <Description here>
//
// Targeted device: <Family::PolarFireSoC> <Die::MPFS250TC> <Package::FCVG484>
// Author: <Name>
//
/////////////////////////////////////////////////////////////////////////////////////////////////// 

`timescale 1ns / 1ps

module Not_gate( 
input wire latched_brake_trigger,
output wire latched_non_brake_trigger );

assign latched_non_brake_trigger = ~latched_brake_trigger;

endmodule

