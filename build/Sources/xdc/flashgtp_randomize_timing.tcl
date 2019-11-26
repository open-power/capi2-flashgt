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

# use trailing digit at end of project name or implementation name as a seed for placement
# set_max_delay below is on a path that doesn't switch and could be don't cared

if { [regexp {impl.*?_(\d+)$} [pwd] -> runid] } { 
  set run [expr {$runid % 64}]
} elseif { [regexp {run(\d+)\/} [pwd] -> runid] } { 
  set run [expr {$runid % 64}]
} else {
  set run 0
}
exec /bin/sh -c "touch run$run"

set_max_delay -datapath_only -from [get_pins "a0/s0/afu_version_q_reg[$run]/C"] -through [get_pins "a0/s0/afu_version_q_reg[$run]/Q"]  2.0

