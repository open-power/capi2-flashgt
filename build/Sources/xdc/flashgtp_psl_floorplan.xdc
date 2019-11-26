#/ *!***************************************************************************
#/ *! Copyright 2019 International Business Machines
#/ *!
#/ *! Licensed under the Apache License, Version 2.0 (the "License");
#/ *! you may not use this file except in compliance with the License.
#/ *! You may obtain a copy of the License at
#/ *! http://www.apache.org/licenses/LICENSE-2.0 
#/ *!
#/ *! The patent license granted to you in Section 3 of the License, as applied
#/ *! to the "Work," hereby includes implementations of the Work in physical form. 
#/ *!
#/ *! Unless required by applicable law or agreed to in writing, the reference design
#/ *! distributed under the License is distributed on an "AS IS" BASIS,
#/ *! WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#/ *! See the License for the specific language governing permissions and
#/ *! limitations under the License.
#/ *!***************************************************************************

#create_pblock psl
#add_cells_to_pblock [get_pblocks psl] [get_cells -quiet [list p]]
#add_cells_to_pblock [get_pblocks psl] [get_cells -quiet [list hdk_inst]]
#add_cells_to_pblock [get_pblocks psl] [get_cells -quiet [list pcihip0]] 
#resize_pblock  [get_pblocks psl] -add {CLOCKREGION_X0Y0:CLOCKREGION_X3Y2}

