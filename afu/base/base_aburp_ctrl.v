// *!***************************************************************************
// *! Copyright 2019 International Business Machines
// *!
// *! Licensed under the Apache License, Version 2.0 (the "License");
// *! you may not use this file except in compliance with the License.
// *! You may obtain a copy of the License at
// *! http://www.apache.org/licenses/LICENSE-2.0 
// *!
// *! The patent license granted to you in Section 3 of the License, as applied
// *! to the "Work," hereby includes implementations of the Work in physical form. 
// *!
// *! Unless required by applicable law or agreed to in writing, the reference design
// *! distributed under the License is distributed on an "AS IS" BASIS,
// *! WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// *! See the License for the specific language governing permissions and
// *! limitations under the License.
// *!***************************************************************************
// component of base_aburp.  Do not use directly
module base_aburp_ctrl(clk, reset, din_v, din_r, dout_v, dout_r, burp_v);
   input clk, reset;
   input din_v;
   output din_r;
   output dout_v;
   input  dout_r;
   output burp_v;
   wire   burp_v_in, burp_v;
   
   assign burp_v_in = ~dout_r & (burp_v | din_v);
   assign din_r = ~burp_v;
   assign dout_v = din_v | burp_v;
   base_vlat#(.width(1))    ivlat(.clk(clk), .reset(reset), .din(burp_v_in), .q(burp_v));
   
endmodule // base_burp

   
	     
	 
   
   

