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

//  *************************************************************************
//  File : nvme_cmp.v
//  *************************************************************************
//  *************************************************************************
//  Description :  compare two values, return lower value
//                 and its id
//  *************************************************************************

module nvme_cmp#
  ( 
    parameter max = 0,  // return largest value (default: smallest)
    parameter count = 2,  // number of data inputs
    parameter levels=$clog2(count),
    parameter count_int=(1<<levels), // force count to power of 2
    parameter width = 1, // width of individual data input
    parameter id_width = 1
    )
   (
    input [count_int*width-1:0] data,
    input [count_int*id_width-1:0] id,
  
    output [width-1:0] dout,
    output [id_width-1:0] dout_id
 
    );

   wire                   lte;

   generate
      if( count_int > 2 )
        begin : blkgt2
           localparam count_div2 = count_int/2;
           wire [count_div2*width-1:0] d0 = data[count_div2*width-1:0];
           wire [count_div2*width-1:0] d1 = data[count_int*width-1:count_div2*width];
           wire [count_div2*id_width-1:0] id0 = id[count_div2*id_width-1:0];
           wire [count_div2*id_width-1:0] id1 = id[count_int*id_width-1:count_div2*id_width];


           
           wire               [width-1:0] dout0, dout1;
           wire            [id_width-1:0] dout_id0, dout_id1;
                          
           nvme_cmp #(.count(count_div2),.width(width),.id_width(id_width)) cmp0 (.data(d0),.id(id0),.dout(dout0),.dout_id(dout_id0));
           nvme_cmp #(.count(count_div2),.width(width),.id_width(id_width)) cmp1 (.data(d1),.id(id1),.dout(dout1),.dout_id(dout_id1));
           nvme_cmp #(.count(2),.width(width),.id_width(id_width)) cmp2 (.data({dout1,dout0}),.id({dout_id1,dout_id0}),.dout(dout),.dout_id(dout_id));
           
        end
      else
        begin : blk2
           wire [width-1:0] data0 = data[width-1:0];
           wire [width-1:0] data1 = data[width*2-1:width];
           assign lte = (data0 <= data1);
           assign dout = (lte ^ max) ? data0 : data1;
           assign dout_id = (lte ^ max) ? id[id_width-1:0] : id[id_width*2-1:id_width];
        end
   endgenerate
   

endmodule


  
