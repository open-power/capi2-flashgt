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
      
      .ah_paren(ah_paren),

      // bind the psl ports
      .ha_jval( ha_jval ),
      .ha_jcom( ha_jcom ),
      .ha_jcompar( ha_jcompar ),
      .ha_jea( ha_jea ),
      .ha_jeapar( ha_jeapar ),
      .ha_lop( ha_lop ),
      .ha_loppar( ha_loppar ),
      .ha_lsize( ha_lsize ),
      .ha_ltag( ha_ltag ),
      .ah_ldone( ah_ldone ),
      .ah_ldtag( ah_ldtag ),
      .ah_ldtagpar( ah_ldtagpar ),
      .ah_lroom( ah_lroom ),
      .ah_jrunning( ah_jrunning ),
      .ah_jdone( ah_jdone ),
      .ah_jerror( ah_jerror ),
      .ah_tbreq( ah_tbreq ),
      .ah_jyield( ah_jyield ),
      .ah_jcack( ah_jcack),
      
      .ah_cvalid( ah_cvalid ),
      .ah_ctag( ah_ctag ),
      .ah_ctagpar( ah_ctagpar),
      .ah_com( ah_com ),
      .ah_compar( ah_compar ),
      .ah_cpad( ah_cpad ),
      .ah_cabt( ah_cabt ),
      .ah_cea( ah_cea ),
      .ah_ceapar( ah_ceapar ),
      .ah_cch( ah_cch ),
      .ah_csize( ah_csize ),
      .ha_croom( ha_croom ),
      
      .ha_brvalid( ha_brvalid ),
      .ha_brtag( ha_brtag ),
      .ha_brtagpar( ha_brtagpar ),
      .ha_brad( ha_brad ),
      .ah_brlat( ah_brlat ),
      .ah_brdata( ah_brdata ),
      .ah_brpar( ah_brpar ),
      .ha_bwvalid( ha_bwvalid ),
      .ha_bwtag( ha_bwtag ),
      .ha_bwad( ha_bwad ),
      .ha_bwdata( ha_bwdata ),
      .ha_bwpar( ha_bwpar ),
      
      .ha_rvalid( ha_rvalid ),
      .ha_rtag( ha_rtag ),
      
      .ha_response( ha_response ),
      .ha_rcredits( ha_rcredits ),
      .ha_rcachestate( ha_rcachestate ),
      .ha_rcachepos( ha_rcachepos ),
      
      .ha_mmval( ha_mmval ),
      .ha_mmrnw( ha_mmrnw),
      .ha_mmdw( ha_mmdw),
      .ha_mmad( ha_mmad ),
      .ha_mmcfg(ha_mmcfg),
      .ha_mmadpar( ha_mmadpar ),
      .ha_mmdata( ha_mmdata ),
      .ha_mmdatapar( ha_mmdatapar ),
      .ha_rtagpar(ha_rtagpar),
      .ha_bwtagpar(ha_bwtagpar),
      .ah_mmack( ah_mmack ),
      .ah_mmdata(ah_mmdata),
      .ah_mmdatapar(ah_mmdatapar)
