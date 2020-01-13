CAPI2 Flash IP for Nallatech N250SP adapter
============================================

Provides RTL source for building FPGA images for the IBM Data Engine for NoSQL Accelerator (Nallatech N250SP).  For information on the software libraries used with the adapter, see:

* [IBM Data Engine for NoSQL Software Libraries](https://github.com/open-power/capiflash)

To build an FPGA image for N250SP:

1. clone this repository
2. install vivado 2017.4 and add to the search path
3. download [PSL9 IP](https://www-355.ibm.com/systems/power/openpower/posting.xhtml?postingId=1BED44BCA884D845852582B70076A89A)
4. unzip the PSL9 IP into psl/ip_repo
5. cd build/
6. ./flashgtp_prj.tcl
7. In the vivado gui, choose "Generate bitstream"


##### Project directories

|directory    | Description |
|-------------|-------------|
|hdk/src      | PSL9 support functions and top level wrapper (psl_fpga) |
|psl/ip_repo  | put unzipped PSL9 IP repo here |
|afu/apps/tms | implements the API required by IBM Data Engine for NoSQL software |
|afu/capi     | implements CAPI2 functions for DMA |
|afu/nvme     | implements NVME datapath and queues |
|afu/ucode    | implements SCSI to NVME translation and NVME initialization |
|afu/base     | RTL library functions |

