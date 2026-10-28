///////////////////////////////////////////////////////////////////////////////////////////////////
// Company: <Name>
//
// File: reset.v
// File history:
//      <Revision number>: <Date>: <Comments>
//      <Revision number>: <Date>: <Comments>
//      <Revision number>: <Date>: <Comments>
//
// Description: To create reset which works only when PLL is locked 
//
// <Description here>
//
// Targeted device: <Family::PolarFireSoC> <Die::MPFS250TC> <Package::FCVG484>
// Author: <Name>
//
/////////////////////////////////////////////////////////////////////////////////////////////////// 

`timescale 1ns/1ps

module reset( 
    input rst_n,
    input lock,
    output rst_n_global
    );
    
    assign rst_n_global = rst_n & lock;


endmodule

