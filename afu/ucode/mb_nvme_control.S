/* *!***************************************************************************
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
*/

/* FlashGT+
 * mb_nvme_control.S
 * xilinx microblaze assembly code
 *
 * implements PCIe & NVMe initialization of NVMe device
 * and SCSI to NVMe command translation for Admin commands
 */
  
     
/* defines for standard PCIe config registers */
#include "linux/pci_regs.h"

#define UC_VERSION 0x00001000

#define NORMACA     

/***********************************************/
/* embedded microcontroller address space      */
/*                                             */
        
/* base address of I/O controller */
#define IO_GPO1 0x44A00010
#define IO_GPO2 0x44A00014
#define IO_GPO3 0x44A00018
#define IO_GPI1 0x44A00020
#define IO_BASE 0x44A10000


/* lower 16b addresses of I/O addressed through 
 *  I/O controller 
 */
#define SNTL_OFFSET 0x00000
#define PCIE_OFFSET 0x04000
#define ADQ_OFFSET  0x08000
#define IOQ_OFFSET  0x0A000
#define REGS_OFFSET 0x0C000

/* I/O to PCIe */
#define PCIE_CONTROL (PCIE_OFFSET | 0x00 )
 /*//  cmd reg:
   // 0 - valid
   // 1 - read
   // 2 - configop
   // 3 - reserved
   // 11:4 - byte enables
   // 15:12 - tag
   // 21:16 - reserved
   // 27:22 - reg number  (when configop is set)
   // 31:28 - ext reg number (when configop is set)
  */
#define PCIE_STATUS  (PCIE_OFFSET | 0x04 )
#define PCIE_DATA0   (PCIE_OFFSET | 0x08 )
#define PCIE_DATA1   (PCIE_OFFSET | 0x0C )
#define PCIE_ADDR0   (PCIE_OFFSET | 0x10 )
#define PCIE_ADDR1   (PCIE_OFFSET | 0x14 )
#define PCIE_INITDONE (PCIE_OFFSET | 0x18 )
#define PCIE_INITSTART (PCIE_OFFSET | 0x1c )
#define PCIE_PERST    (PCIE_OFFSET | 0x20 )
#define PCIE_CPLTO    (PCIE_OFFSET | 0x24 )
        

/* I/O to Admin Queue */
#define ASQ_ENTRY  (ADQ_OFFSET)
#define ASQ_DW15   (ASQ_ENTRY | (15<<2))
#define ASQ_DW14   (ASQ_ENTRY | (14<<2))
#define ASQ_DW13   (ASQ_ENTRY | (13<<2))
#define ASQ_DW12   (ASQ_ENTRY | (12<<2))
#define ASQ_DW11   (ASQ_ENTRY | (11<<2))
#define ASQ_DW10   (ASQ_ENTRY | (10<<2))
#define ASQ_PRP21  (ASQ_ENTRY | (9<<2))
#define ASQ_PRP20  (ASQ_ENTRY | (8<<2))
#define ASQ_PRP11  (ASQ_ENTRY | (7<<2))        
#define ASQ_PRP10  (ASQ_ENTRY | (6<<2))
#define ASQ_NSID   (ASQ_ENTRY | (1<<2))
#define ASQ_CMD    (ASQ_ENTRY)
#define ASQ_INSERT (ADQ_OFFSET | 0x40)
#define ASQ_STATUS (ADQ_OFFSET | 0x50)
#define ASQ_CLEAR0 (ADQ_OFFSET | 0x60)
#define ASQ_CLEAR1 (ADQ_OFFSET | 0x64)
#define ASQ_CLEAR2 (ADQ_OFFSET | 0x68)
#define ASQ_CLEAR3 (ADQ_OFFSET | 0x6c)
#define ASQ_RESET  (ADQ_OFFSET | 0x70)

#define ACQ_ENTRY   (ADQ_OFFSET | 0x80)
#define ACQ_STATUS  (ADQ_OFFSET | 0xB0)
#define ACQ_REMOVE  (ADQ_OFFSET | 0xC0)

/* add to ASQ/ACQ registers to access ucode I/O Queue */
#define UCIOQ_OFFSET 0x0100

/* admin command buffer controls */
#define SNTL_COMMAND      (SNTL_OFFSET | 0x00)
#define SNTL_LENGTH       (SNTL_OFFSET | 0x04)
#define SNTL_LUN03        (SNTL_OFFSET | 0x08)
#define SNTL_LUN47        (SNTL_OFFSET | 0x0C)
#define SNTL_CDB03        (SNTL_OFFSET | 0x10)
#define SNTL_CDB47        (SNTL_OFFSET | 0x14)
#define SNTL_CDB8B        (SNTL_OFFSET | 0x18)
#define SNTL_CDBCF        (SNTL_OFFSET | 0x1C)
#define SNTL_SISL_CID     (SNTL_OFFSET | 0x20)
#define SNTL_SISL_RELOFF  (SNTL_OFFSET | 0x24)
#define SNTL_SISL_LENGTH  (SNTL_OFFSET | 0x28)
#define SNTL_STATUS0      (SNTL_OFFSET | 0x2C)
#define SNTL_STATUS1      (SNTL_OFFSET | 0x30)
#define SNTL_SISL_CLEAR   (SNTL_OFFSET | 0x40)
#define SNTL_SISL_PAYLOAD (SNTL_OFFSET | 0x44)

#define SNTL_SISL_BUFFER  (SNTL_OFFSET | 0x1000)
#define SNTL_ADQ_BUFFER   (SNTL_OFFSET | 0x2000)
#define SNTL_NSID_TABLE   (SNTL_OFFSET | 0x3000)
#define SNTL_BLKSZ_TABLE  (SNTL_OFFSET | 0x3800)
#define SNTL_NSZE_TABLE   (SNTL_OFFSET | 0x3C00)

/* mmio registers visible to host and microcontroller */
#define REGS_FC_PNAME       (REGS_OFFSET | 0x300)
#define REGS_FC_PNAMEH      (REGS_OFFSET | 0x300 + 4)
#define REGS_FC_CONFIG      (REGS_OFFSET | 0x320)
#define REGS_FC_CONFIG3H    (REGS_OFFSET | 0x350 + 4)
#define REGS_FC_STATUS      (REGS_OFFSET | 0x330)
#define REGS_FC_STATUSH     (REGS_OFFSET | 0x330 + 4)
#define REGS_FC_STATUS2     (REGS_OFFSET | 0x348)
#define REGS_FC_STATUS2H    (REGS_OFFSET | 0x348 + 4)
#define REGS_FC_STATUS3     (REGS_OFFSET | 0x410)
#define REGS_FC_STATUS3H    (REGS_OFFSET | 0x410 + 4)
#define REGS_FC_NNAME       (REGS_OFFSET | 0x308)
#define REGS_FC_NNAMEH      (REGS_OFFSET | 0x308 + 4)
#define REGS_FC_ERRCAP      (REGS_OFFSET | 0x388)
#define REGS_FC_ERRSET      (REGS_OFFSET | 0x398)
#define REGS_TGT_PNAME      (REGS_OFFSET | 0x408)
#define REGS_TGT_NNAME      (REGS_OFFSET | 0x410)
#define REGS_FC_DBGDISP     (REGS_OFFSET | 0x600)
#define REGS_FC_DBGDATA     (REGS_OFFSET | 0x608)        
#define REGS_NVME_FW_STATUS (REGS_OFFSET | 0x700)        
#define REGS_NVME_FW_ACTIVE (REGS_OFFSET | 0x708)        
#define REGS_NVME_FW_NEXT   (REGS_OFFSET | 0x710)        

/* error status bits for writing FC_ERROR/FC_ERRSET */
/* bits 15:0 are reserved for microcode */
/* 7:0 cause an interrupt but no online->offline->online reset sequence */
/* 15:8 cause interrupt + reset sequence */

#define FC_ERROR_PCIELNK (1<<0)
#define FC_ERROR_PCIECAP (1<<1)
#define FC_ERROR_PCIEERR (1<<2)
#define FC_ERROR_NVMERDY (1<<4)
#define FC_ERROR_NVMERC  (1<<8)
#define FC_ERROR_PCIE_RETRY_LIMIT (1<<20)  /* send "LOGO" interrupt */
                        
/*************************************************/
/* address map for NVMe controller address space */
        
/* addr[63:52] = zero       */
/* addr[51:48] = region     */
/* addr[47:32] = cmd id     */
/* addr[31:28] = rsvd/zero  */
/* addr[27:0]  = offset     */
/* range:            region
 *                   encode   description
 *     0 -   64G-1:  0        not used
 *   64G -  256T-1:  0        NVMe regs (Samsung SM951 uses 16KB)
 *  256T -  512T-1:  1        Admin Q   (max 512G)
 *  512T -  768T-1:  2        I/O Q     (max 512G)
 *  768T - 1024T-1:  3        reserved for PRP list if needed       
 * 1024T - 1280T-1:  4        sislite payload DMA (read/write)
 * 1280T - 1536T-1:  5        admin payload DMA
 * 1536T - 1792T-1:  6        sntl write buffer (read)
 */

/* NVMe controller registers */
#define NVME_BAR1  0x00000000  /* 63:32 */
#define NVME_BAR0  0x93800000  /* 31:0 */

/* queue addresses */
/* addr[51:48]=1 for ucode controlled queues */
/* addr[51:48]=2 for sntl controlled queues */
/* addr[47]=0 for SQ, 1 for CQ */
/* addr[46:40] = queue number */
/* addr[39:28] = isq_mem base (x 64B) */
/* addr[27:0] = 0 (aligned to 128MB boundary) */
/* addr[15:0] = offset from isq_mem base for dma access */
        
#define NVME_ASQBASE1 0x00010000
#define NVME_ASQBASE0 0x00000000
#define NVME_ACQBASE1 0x00018000
#define NVME_ACQBASE0 0x00000000

#define NVME_UCSQ0BASE1 0x00010100
#define NVME_UCSQ0BASE0 0x00000000
#define NVME_UCCQ0BASE1 0x00018100
#define NVME_UCCQ0BASE0 0x00000000

#define NVME_ISQ0BASE1 0x00020000
#define NVME_ISQ0BASE0 0x00000000
        
#define NVME_ICQ0BASE1 0x00028000
#define NVME_ICQ0BASE0 0x00000000

/* I/O payload */        
#define NVME_SISL_BASE1    0x00040000
#define NVME_SISL_BASE0    0x00000000
/* Admin cmd payload */
#define NVME_ADMINWR_BASE1   0x00050000
#define NVME_ADMINWR_BASE0   0x00000000
#define NVME_ADMINRD_BASE1   0x00058000
#define NVME_ADMINRD_BASE0   0x00000000


/******************************************************************************/
/* NVMe MMIO registers - offset from NVME_BAR0/1 */
#define NVME_REG_CAP       0x0000  /* controller capabilities - 8B */
#define NVME_REG_VS        0x0008  /* version - 4B */
#define NVME_REG_INTMS     0x000c  /* interrupt mask set - 4B */
#define NVME_REG_INTMC     0x0010  /* interrupt mask clear - 4B */
#define NVME_REG_CC        0x0014  /* controller configuration - 4B */
#define NVME_REG_CSTS      0x001C  /* controller status - 4B */
#define NVME_REG_NSSR      0x0020  /* NVM subsystem reset (optional) - 4B */
#define NVME_REG_AQA       0x0024  /* Admin Queue Attributes - 4B */
#define NVME_REG_ASQB      0x0028  /* Admin submission Queue Base Address - 8B */
#define NVME_REG_ACQB      0x0030  /* Admin completion Queue Base Address - 8B */
#define NVME_REG_SQ0TDBL   0x1000  /* Submission Queue 0 Tail Doorbell (Admin) - 4B */
#define NVME_REG_CQ0HDBL   0x1004  /* Completion Queue 0 Head Doorbell (Admin) - 4B */
#define NVME_REG_SQ1TDBL   0x1008  /* Submission Queue 1 Tail Doorbell - 4B */
#define NVME_REG_CQ1HDBL   0x100C  /* Completion Queue 1 Head Doorbell - 4B */


#define ADMIN_Q_ENTRIES 4

#define IO_SQ 4
#define IO_SQ_ENTRIES 65
#define IO_CQ_ENTRIES 512

#define ADMIN_OVERRIDE_ENTRIES 4
#define ADMIN_OVERRIDE_BYTES   16       
        
/******************************************************************************/
/* internal command encode */
#define CMD_RD 0x03
#define CMD_WR 0x04
#define CMD_ABORT 0x05
#define CMD_TASKMAN 0x06
        
/******************************************************************************/
/* SCSI defines */
#define SCSI_FORMAT_UNIT 0x04
#define SCSI_INQUIRY 0x12
#define SCSI_MODE_SELECT   0x15
#define SCSI_MODE_SELECT_10   0x55
#define SCSI_MODE_SENSE   0x1A
#define SCSI_MODE_SENSE_10   0x5A
#define SCSI_LOG_SENSE   0x4D
#define SCSI_PERSISTENT_RESERVE_IN   0x5E
#define SCSI_PERSISTENT_RESERVE_OUT   0x5F
#define SCSI_READ   0x08
#define SCSI_READ_6   0x08
#define SCSI_READ_10   0x28
#define SCSI_READ_12   0xA8
#define SCSI_READ_16   0x88
#define SCSI_READ_CAPACITY    0x25
#define SCSI_READ_EXTENDED   0x28
#define SCSI_REPORT_LUNS   0xA0
#define SCSI_REQUEST_SENSE   0x03
#define SCSI_SERVICE_ACTION_IN   0x9E
#define SCSI_SERVICE_ACTION_OUT   0x9F
#define SCSI_START_STOP_UNIT   0x1B
#define SCSI_TEST_UNIT_READY   0x00
#define SCSI_WRITE   0x0A
#define SCSI_WRITE_6   0x0A
#define SCSI_WRITE_10   0x2A
#define SCSI_WRITE_12   0xAA
#define SCSI_WRITE_16   0x8A
#define SCSI_WRITE_AND_VERIFY   0x2E
#define SCSI_WRITE_AND_VERIFY_16   0x8E
#define SCSI_WRITE_EXTENDED   0x2A
#define SCSI_WRITE_SAME   0x41
#define SCSI_WRITE_SAME_16   0x93
#define SCSI_WRITE_BUFFER   0x3B
#define SCSI_UNMAP 0x42

/* NVMe status codes */
/* see NVM-Express-1_1b 4.6.1 */

/* generic status codes */
#define NVME_SC_G_SUCCESS            0x000
#define NVME_SC_G_INVALID_OPCODE     0x001
#define NVME_SC_G_INVALID_FIELD      0x002
#define NVME_SC_G_ID_CONFLICT        0x003
#define NVME_SC_G_DATA_ERROR         0x004
#define NVME_SC_G_POWERLOSS          0x005
#define NVME_SC_G_INTERNAL           0x006
#define NVME_SC_G_ABORTREQ           0x007
#define NVME_SC_G_ABORTSQDEL         0x008
#define NVME_SC_G_ABORTFUSE1         0x009
#define NVME_SC_G_ABORTFUSE2         0x00a
#define NVME_SC_G_INVALID_NSPACE     0x00b
#define NVME_SC_G_LBA_RANGE          0x080
#define NVME_SC_G_CAPACITY_EXCEED    0x081
#define NVME_SC_G_NSPACE_NOT_READY   0x082
#define NVME_SC_G_RESV_CONFLICT      0x083

/* command spec status codes */
#define NVME_SC_C_ABORT_LIMIT        0x103
#define NVME_SC_C_INVALID_FORMAT     0x10A
#define NVME_SC_C_ATTR_CONFLICT      0x180
#define NVME_SC_C_INVALID_PROT       0x181
#define NVME_SC_C_RO_WRITE           0x182

/* Media status codes */
#define NVME_SC_M_WRITE_FAULT            0x280
#define NVME_SC_M_UNRECOVERD_READ_ERROR  0x281
#define NVME_SC_M_ACCESS_DENIED          0x286

/* sislite status codes (not part of NVMe) */
#define NVME_SC_S_NOT_IMPL           0x450
#define NVME_SC_S_ID_CONFLICT        0x453
#define NVME_SC_S_INVALID_FIELD      0x454  /* invalid field in command information unit */
#define NVME_SC_S_LOGICAL_UNIT_NOT_SUPPORTED 0x455
#define NVME_SC_S_INVALID_FIELD_IN_PARAM 0x457 /* invalid field in parameter list */
#define NVME_SC_S_NOT_READY 0x458 
#define NVME_SC_S_SHUTDOWN 0x459
#define NVME_SC_S_WRITE_DMA_ERR  0x45A
#define NVME_SC_S_ABORT_COMPLETE 0x45B
        
#define NVME_SC_S_TMF_COMP    0x460       
#define NVME_SC_S_TMF_SUCCESS 0x461   
#define NVME_SC_S_TMF_REJECT  0x462       
#define NVME_SC_S_TMF_LUN     0x463
#define NVME_SC_S_TMF_FAIL    0x464

/* status code flags */
#define NVME_SC_DNR   0x4000
#define NVME_SC_MORE  0x2000
#define NVME_SC_VALID 0x8000      
        
/* GPIO bit masks */
#define GPO_CSTS_RDY        (1<<0)  // NVMe controller status reg ready bit
#define GPO_IOQ_ENABLE      (1<<1)  // IOQ is enabled and ready for I/O commands
#define GPO_SHUTDOWN        (1<<2)  // shutdown processing is active
#define GPO_SHUTDOWN_CMP    (1<<3)  // shutdown is complete
        
#define GPI_ADMIN_CMD       (1<<0)  // SNTL admin buffer has a command valid
#define GPI_ADMIN_CPL       (1<<1)  // SNTL admin completion is valid
#define GPI_CTL_ENABLE      (1<<2)  // config reg controller enable bit 
#define GPI_LINK_UP         (1<<3)  // PCIe port link up status
#define GPI_INIT_DONE       (1<<4)  // PCIe port init done. set by ucode, cleared by link down
#define GPI_ACQ_CQ0_EMPTY   (1<<5)  // NVMe Admin completion queue empty flag
#define GPI_ACQ_CQ1_EMPTY   (1<<6)  // NVMe Admin completion queue empty flag
#define GPI_SNTL_IDLE       (1<<7)  // SNTL is idle, init completed
#define GPI_LD_ROM          (1<<8)  // load program memory with new image from mmio reg
#define GPI_SHUTDOWN        (1<<9)  // start normal shutdown
#define GPI_SHUTDOWN_ABRUPT (1<<10) // start abrupt shutdown
#define GPI_ISQ_EMPTY       (1<<11) // I/O Submission Queue is empty
#define GPI_ICQ_EMPTY       (1<<12) // I/O Completion Queue is empty
#define GPI_T1_EXPIRED      (1<<13) // timer controlled by GPIO3 expired
#define GPI_LUNRESET        (1<<14) // reset LUN -> disable/enable controller

#ifdef SIM
#define PCIE_INIT_DELAY  2
#else
#define PCIE_INIT_DELAY  (100000000/32)  // 100ms - loop count to wait for link to stay up.  32ns per count
#endif
#define PCIE_INIT_RETRIES 20        
/******************************************************************************/

/* macros to read/write from PCIe space
 * macro ending in "I" is immediate
 * else parameter is a register
 */
#define CFGRD0I(REGNUM) \
        ori r5, r0, (REGNUM) ;\
        brlid r15, cfgrd0    ;\
        nop
        
#define CFGWR0I(REGNUM,DATA) \
        ori r5, r0, (REGNUM) ;\
        ori r6, r0, (DATA)   ;\
        brlid r15, cfgwr0    ;\
        nop
        
#define CFGRD0(REGNUM) \
        or r5, r0,  REGNUM   ;\
        brlid r15, cfgrd0    ;\
        nop    
           
#define CFGWR0(REGNUM,DATA) \
        or  r5, r0,  REGNUM ;\
        ori r6, r0, (DATA)  ;\
        brlid r15, cfgwr0   ;\
        nop

#define MMIORD4I(ADDR) \
        ori r5, r0, (ADDR)  ;\
        brlid r15, mmiord4  ;\
        nop

#define MMIOWR4I(ADDR, DATA) \
        ori r5, r0, (ADDR)  ;\
        ori r6, r0, (DATA)  ;\
        brlid r15, mmiowr4  ;\
        nop
        
#define MMIOWR4(ADDR, DATA) \
        ori r5, r0, (ADDR)  ;\
        or r6, r0,   DATA   ;\
        brlid r15, mmiowr4  ;\
        nop

// main line state status byte 
// store in RAM and copy to GPIO for debug   
#define UCODE_STATUS(VAL) \
        ori  r12, r0, (VAL)       ;\
        sbi  r12, r0, status_data ; \
        lwi  r12, r0, status_data ; \
        swi  r12, r0, IO_GPO2

// secondary status for subroutines        
#define UCODE_STATUS_SUB(VAL) \
        ori  r12, r0, (VAL)       ;\
        sbi  r12, r0, status_data + 1 ; \
        lwi  r12, r0, status_data ; \
        swi  r12, r0, IO_GPO2

// nvme op status error code
#define UCODE_STATUS_RC(REG) \
        shi  REG, r0, status_data + 2 ; \
        lwi  r12, r0, status_data ; \
        swi  r12, r0, IO_GPO2

/* microblaze register use - see xilinx microblaze processor reference guide UG081
 * - this is the convention when using stack & linking C code
 * R0 == zero
 * R1:  stack pointer
 * R2:  small data area pointer
 * R3, R4: volatile, used for function return value
 * R5 - R10: volatile, used to pass parameters to function
 * R11,R12: volatile, temp vars
 * R13:  small data area pointer
 * R14: interrupt return address
 * R15: function return address
 * R16: trap return address
 * R17: exception return address
 * R18: temp for assembler ops
 * R19 - R31: treated as non-volatile
 *
 * currently not using the stack, interrupts, or C code
 * mostly following the above convention
 */

/******************************************************************************/
/* PCIe initialization */
    
.section ".boot","ax"

_boot:  nop
        swi r0, r0, IO_BASE + REGS_TGT_NNAME  /* set to retry count to zero on reset or when "login" succeeds */
        /* clear status after a reset */
        UCODE_STATUS(0x00)
        UCODE_STATUS_SUB(0x00)
        ori r12, r0, 0x0000
        UCODE_STATUS_RC(r12)
        
pcie_init:           
        swi r0, r0, IO_GPO1  /* indicate not ready, no io queues */

pcie_init_1:            
        lwi  r12, r0, IO_GPI1
        andi  r3, r12, GPI_LD_ROM
        beqi  r3, pcie_init_2             
        brlid r15, load_rom     /* load rom from mmio regs for debug */
        nop
        
pcie_init_2:            
        /* wait for PCIe link up */          
        andi  r3, r12, GPI_LINK_UP
        beqi  r3, pcie_init_1
        /* wait for enable input to go active */
        andi  r3, r12, GPI_CTL_ENABLE
        beqi  r3, pcie_init_1
        /* wait for sntl init complete and queues empty */
        andi  r3, r12, GPI_SNTL_IDLE
        beqi  r3, pcie_init_1
        andi  r3, r12, GPI_ISQ_EMPTY
        beqi  r3, pcie_init_1
        andi  r3, r12, GPI_ICQ_EMPTY
        beqi  r3, pcie_init_1

        UCODE_STATUS(0x01)
        
        /* set status flag for PCI init started */
        swi r0, r0, IO_BASE + PCIE_INITSTART

        /* delay then check that link is still up */
        
        lwi  r4, r0, IO_BASE + REGS_TGT_NNAME
        addi r12, r4, 1
        swi  r12, r0, IO_BASE + REGS_TGT_NNAME        
        addi r12, r4, -PCIE_INIT_RETRIES
        bgti r12, pcie_init_too_many_tries

        /* multiply PCIE_INIT_DELAY by (2*number of retries)+1 - max 25 */
        addi r12, r4, -12
        blei r12, pcie_init_3
        ori  r4, r0, 12
pcie_init_3:        
        bslli r12, r4, 1
        addi  r12, r12, 1

        ori   r30, r0, 10  /* CRS retries remaining */

pcie_init_dly:  
        ori  r3, r0, PCIE_INIT_DELAY
        beqi r30, pcie_error_nonposted  /* got CRS status too many times */
        
pcie_init_dly_1:
        addi r3, r3, -1
        bnei r3, pcie_init_dly_1
        addi r12, r12, -1
        bnei r12, pcie_init_dly
        
        /* if initstart flag is cleared, try again */
        lwi r3, r0, IO_BASE + PCIE_INITSTART
        beqi r3, pcie_init_1 
               
        UCODE_STATUS(0x02)
        
        /* set endpoint's bus id */
        CFGRD0I(PCI_VENDOR_ID)

        /* if r4 is non-zero, then we got CRS status.  wait 100ms and try again up to 10 times */
        ori  r12, r0, 1
        addi r30, r30, -1
        bnei r4, pcie_init_dly

        /* set timeout for non-posted ops to 50ms */
        #ifdef SIM
        ori r12, r0, 19
        #else
        ori r12, r0, 50000
        #endif
        swi r12, r0, IO_BASE + PCIE_CPLTO
        
        #ifdef SIMERR
        bri pcie_error_nonposted
        #endif
        
        UCODE_STATUS(0x03)
        
        /* read BIST/Header Type/Master Latency Timer/Cache line size */
        /* should check Header_Type.MFD bit */
        CFGRD0I(PCI_CACHE_LINE_SIZE)

        /* write BARs to Fs and then read back to check BAR range */
        CFGWR0I(PCI_BASE_ADDRESS_0,0xFFFFFFFF)
        CFGWR0I(PCI_BASE_ADDRESS_1,0xFFFFFFFF)
        CFGWR0I(PCI_BASE_ADDRESS_2,0xFFFFFFFF)
        CFGWR0I(PCI_BASE_ADDRESS_3,0xFFFFFFFF)
        CFGWR0I(PCI_BASE_ADDRESS_4,0xFFFFFFFF)
        CFGWR0I(PCI_BASE_ADDRESS_5,0xFFFFFFFF)
        CFGWR0I(PCI_ROM_ADDRESS,0xFFFFFFFF)

        /* read PCI_STATUS/PCI_COMMAND */
        /* should also check for STS.CL - capabilities list (required to be 1 for pcie) */
        CFGRD0I(PCI_COMMAND)
        /* read class code (24b)/revision id (8b) */
        /* class code is expected to be 0x010802 */
        CFGRD0I(PCI_CLASS_REVISION)


        /* find PCIe express capability = id 0x10 */
        CFGRD0I(PCI_CAPABILITY_LIST)
        andi r5,r3,0x00FF

readcap:     
        CFGRD0(r5)   /* result of cfgrd returned in r3 */
        andi r20, r3, 0x00FF  /* r20 = capability id (byte 0 of capability) */
        xori  r20, r20, 0x10  /* check for id 0x10 */
        beqi  r20, pciecap                          
        bsrli r5, r3, 8      /* byte 1 of capability is next cap pointer */
        andi  r5, r5, 0x00FF /* r5 = next cap pointer */
        bnei  r5, readcap   /* next cap != 0 */
pciecaperr:
        bri pcie_init_error_pciecap 
pciecap:
        UCODE_STATUS(0x04)
        
        or    r21, r0, r5  /* r21 = pcie cap pointer */
      
        /* write PCIe Cap - Device Control register 
         * bit 4 = relaxed ordering
         * 7:5 = 128B max payload
         * 8 = extended tag enable
         * 9 = phantom functions enable
         * 10 = aux power PM enable
         * 11 = enable no snoop
         * 14:12 = max read request size = 010b 512B  (default)
         *                                 100b 2048B
         *                                 101b 4096B (max)
         */
        addi r22, r21, PCI_EXP_DEVCTL
        /* CFGWR0(r22,0x00002F10) */        
        CFGWR0(r22,0x00002F10)

        /* set completion timeout disable */
        /* bit 4 of PCI Express Device Control 2 Register */
        /* should also check capability version = 2 here */
        addi r22, r21, PCI_EXP_DEVCTL2
        CFGWR0(r22, 0x10)        

        /* read BARs and set BAR0/BAR1 at a minimum */
        /* BAR0/1 - Samsung spec shows bits 63:14 as writable
         *          16KB region for control & doorbell regs
         */
        CFGRD0I(PCI_BASE_ADDRESS_0)
        or r20, r0, r3
        CFGRD0I(PCI_BASE_ADDRESS_1)
        or r21, r0, r3     
        CFGWR0I(PCI_BASE_ADDRESS_0,NVME_BAR0 | 0x0C) /* 2:1 = 0b10 for 64b address */
        CFGWR0I(PCI_BASE_ADDRESS_1,NVME_BAR1)

        CFGWR0I(PCI_BASE_ADDRESS_2,0x00000000)
        CFGWR0I(PCI_BASE_ADDRESS_3,0x00000000)
        CFGWR0I(PCI_BASE_ADDRESS_4,0x00000400)
        CFGWR0I(PCI_BASE_ADDRESS_5,0x00000000)
        CFGWR0I(PCI_ROM_ADDRESS,0x00000000)

        #ifdef SIM
        /* enable bus master and memory space, interrupt disable=0 */
        /* denali model doesn't like having interrupts disabled */
        CFGWR0I(PCI_COMMAND, 0x00000006)
        #else
        /* enable bus master and memory space, interrupt disable=1 */
        CFGWR0I(PCI_COMMAND, 0x00000406)
        #endif
        
        /* set status flag for PCI init completed */
        swi r0, r0, IO_BASE + PCIE_INITDONE
        
        UCODE_STATUS(0x05)
        bri nvme_init


/* pcie errors */
pcie_link_reset:   
        /* set error to generate interrupt then wait for error to be cleared */          
        ori r12, r0, FC_ERROR_PCIELNK
        swi r12, r0, IO_BASE + REGS_FC_ERRSET    
        bri pcie_init_fail_stat  
        
pcie_init_error_pciecap:             
        ori r12, r0, FC_ERROR_PCIECAP
        swi r12, r0, IO_BASE + REGS_FC_ERRSET
        bri pcie_init_fail_stat
    
pcie_error_nonposted:        
        ori r12, r0, FC_ERROR_PCIEERR
        swi r12, r0, IO_BASE + REGS_FC_ERRSET
        bri pcie_init_fail_poll
                
            
pcie_init_fail_stat:            
        UCODE_STATUS_SUB(0x30)
pcie_init_fail_poll:                    
        lwi r12, r0, IO_GPI1

        andi  r3, r12, GPI_LINK_UP  
        beqi  r3, pcie_link_down    /* link is down, no need for perst */
        
        andi r3, r12, GPI_CTL_ENABLE
        beqi r3, pcie_init_fail_perst /* controller disable - do a link reset */

        lwi r12, r0, IO_BASE + REGS_FC_ERRCAP  /* check that error has been cleared, then do link reset */
        beqi r12, pcie_init_fail_perst    

        bri pcie_init_fail_poll

pcie_init_fail_perst:   
        /* perst link then reinit */        
        swi r0, r0, IO_BASE + PCIE_PERST
        
pcie_link_down:
        /* indicate link went down then restart init */
        UCODE_STATUS_SUB(0x31)
        swi r0, r0, IO_GPO1  /* controller not ready, IOQ not enabled */
        /* reset ASQ/ACQ pointers */     
        swi r0, r0, IO_BASE + ASQ_RESET        
        bri pcie_init  /* wait for link to come back up and re-init PCIe */

pcie_init_too_many_tries:
        ori r12, r0, FC_ERROR_PCIE_RETRY_LIMIT
        swi r12, r0, IO_BASE + REGS_FC_ERRSET 
        /* don't try again - wait for reset */
pcie_init_too_many_tries_1:    
        bri pcie_init_too_many_tries_1                
          
/******************************************************************************/
/* NVMe initialization - see NVMe 1.1b 7.6.1 */
        
nvme_init:
        /* wait for enable input to go active */
        lwi r12, r0, IO_GPI1

        andi r3, r12, GPI_LD_ROM
        beqi  r3, nvme_init_1             
        brlid r15, load_rom     /* load rom from mmio regs for debug */
        nop
        
        UCODE_STATUS(0x06)
        
nvme_init_1:            
        andi r3, r12, GPI_INIT_DONE
        beqi r3, pcie_link_down        /* PCIe link went down - wait for link up and reinit */

        andi r3, r12, GPI_CTL_ENABLE
        beqi r3, nvme_init
        
        UCODE_STATUS(0x07)
          
        /* NVMe register init - BAR0/1 + NVMe offset */
        MMIORD4I(NVME_REG_CAP)
        or r22, r0, r3
        MMIORD4I(NVME_REG_CAP+4)
        or r23, r0, r3
        /* should check some capabilities here:
         *  CAP.MPSMAX = memory page size max -> CC.MPS must be <= CAP.MPSMAX 
         *  CAP.MPSMIN = memory page size min
         *  CAP.DSTRD = doorbell stride -> use this to determine doorbell addresses
         *  CAP.MQES = max queue entries -> check that this is > 256 ?
         *  CAP.TO = timeout - how long to wait after enabling the controller before CSTS.RDY 
         */
        /* other regs to check:  NVME_REG_VS - expect version 1.1 or later */

        /* write controller config with page size, enable=0 */
        bsrli r24, r23, 20
        andi  r24, r24, 0xF  /* r24 = CAP.MPSMAX */
        bslli r24, r24, 7    /* 10:7 = CC.MPS */
        ori   r24, r24, 0x00460000  /* set IOCQES=4 and IOSQES=6 */
        MMIOWR4(NVME_REG_CC,r24)
        
        /* set up admin queue */
        MMIOWR4I(NVME_REG_AQA, (((ADMIN_Q_ENTRIES-1)<<16) | (ADMIN_Q_ENTRIES-1)) )  /* queue sizes is 0 based value */
        
        MMIOWR4I(NVME_REG_ASQB, NVME_ASQBASE0)
        MMIOWR4I(NVME_REG_ASQB+4, NVME_ASQBASE1)
        MMIOWR4I(NVME_REG_ACQB, NVME_ACQBASE0)
        MMIOWR4I(NVME_REG_ACQB+4, NVME_ACQBASE1)

        ori r24, r24, 0x01  /* set enable bit in controller config */
        MMIOWR4(NVME_REG_CC,r24)
        
        UCODE_STATUS(0x08)
    
        /* wait for CSTS.RDY */
        /* entry point following a controller reset */
nvme_init_rdy:  
        lwi r12, r0, IO_GPI1        
        andi r3, r12, GPI_INIT_DONE
        beqi r3, pcie_link_down        /* PCIe link went down - wait for link up and reinit */
        
        MMIORD4I(NVME_REG_CSTS)
        andi r3,r3,0x01
        /* could check for timeout here */
        beqi r3, nvme_init_rdy
        
        UCODE_STATUS(0x09)

        /* set status output to indicate NVMe controller is ready */
        ori r12, r0, GPO_CSTS_RDY
        swi r12, r0, IO_GPO1

        /* admin queue is ready - now set up I/O queue */
        /* see NVMe 1.1b 7.4.1, 7.6.1 */
        /* 1. identify controller
         * 2. identify namespace
         * 3. set features - number of I/O queues = 18
         * 4. create I/O completion queue
         * 5. create I/O submission queue
         * 6. optional:  enable async event notification
         */

        ori r11, r0, IO_BASE
        
        /* identify command - get controller config */
        ori r5, r0, 0x81 /* cmd id */
        ori r6, r0, 0x01 /* identify controller */
        ori r7, r0, 0x00 /* namespace id */
        brlid r15, admin_identify
        nop
        /* r3=status */
        /* r5=dw0 */
        bnei r3, nvme_init_fail

        
        /* save IEEE OUI from bytes 75-73 (byte 73=msb) */
        lwi   r7, r11, SNTL_ADQ_BUFFER+72        
        /* swapb r7, r7 */
        /* andi  r7, r7, 0x00FFFFFF */
        bsrli r7, r7, 8
        swi r7, r0, data_ieee_oui  /* stored as little endian */

        /* save firmware info */
        lwi   r7, r11, SNTL_ADQ_BUFFER+260
        andi  r7, r7, 0xff
        bslli r7, r7, 8
        swi   r7, r11, REGS_NVME_FW_STATUS        
        
        /* BMP - should check data returned by identify cmd here */
        UCODE_STATUS(0x0A)


        /* check for nvme 1.0 version */
        MMIORD4I(NVME_REG_VS)
        ori r7, r0, 1   /* use namespace=1 for nvme 1.0 drives */
        xori r4,r3,0x00010000
        beqi r4, nvme_init_nsid_table
        
        
        /* identify command - get namespace list */
        ori r5, r0, 0x82 /* cmd id */
        ori r6, r0, 0x02 /* namespace list */
        ori r7, r0, 0x00 /* namespace id */
        brlid r15, admin_identify
        nop
        bnei r3, nvme_init_fail
        UCODE_STATUS(0x0B)
        
        /* for multiple namespace support, loop through list and fill in the table */
        /* only 1 namespace currently supported so for now so grab the first namespace */
        lwi r7, r11, SNTL_ADQ_BUFFER

        #ifdef SIM
        /* workaround: force nsid=01 to match Samsung. */
        /* sim model doesn't allow namespace id 1 with only 1 namespace */
        /* sim model doesn't return correct namespace list either */
        ori r7, r0, 1
        #else
        or r0,r0,r0
        #endif
        
nvme_init_nsid_table:                
        swi r7, r11, SNTL_NSID_TABLE 
        
        /* identify command - get namespace info of first namespace */
        ori r5, r0, 0x83 /* cmd id */
        ori r6, r0, 0x00 /* identify namespace */
        brlid r15, admin_identify
        nop
        bnei r3, nvme_init_fail
        
        brlid r15, sntl_get_ns_blocksize  /* reads SNTL_ADQ_BUFFER, returns r12=LBADS {r6,r5} = number of 4K blocks */
        nop
        swi r12, r11, SNTL_BLKSZ_TABLE /* for multiple namespace support, loop through list and fill in the table */
        swi r0, r11, SNTL_BLKSZ_TABLE+4 /* bit 0 of 2nd word = ACA status */
        swi r5, r11, SNTL_NSZE_TABLE
        swi r6, r11, SNTL_NSZE_TABLE+4

        /* BMP - should check data returned by identify cmd here */
        
        /* copy 8B EUI to TGT_PNAME reg */
        lwi r9, r11, SNTL_ADQ_BUFFER | 120  /* big endian - MSB */
        lwi r10, r11, SNTL_ADQ_BUFFER | 124
        swapb r9, r9
        swapb r10, r10
        swi r10, r11, REGS_TGT_PNAME
        swi r9, r11, REGS_TGT_PNAME+4
        
        /* set number of I/O queues to 1 (might not be needed) */
        ori r5, r0, 0x84 /* cmd id */
        ori r6, r0, 0x07 /* feature id = number of I/O queues */
        ori r7, r0, 0x00 /* namespace id */
        ori r8, r0, 0x10012 /* 15:0=0x12 for 2+16 I/O submission queues and 31:16=1 for 2 I/O completion queue */
        brlid r15, admin_set_features
        nop
        /* save actual number of queues allocated in DW0 of completion. NCQA=31:16, NSQA=15:0 */  
        andi r27, r5, 0x00ffff    /* NSQA = number of submission queues allocated */
        swi r5, r11, REGS_FC_PNAME /* debug */
        
        /* sim model returns 0 for NSQA - override here */
        #ifdef SIM
        ori r27, r0, 0x00000008
        #else
        ori r0, r0, 0
        #endif
        bnei r3, nvme_init_fail
        UCODE_STATUS(0x0C)

        /* create I/O completion queue for ucode use */
        ori r5, r0, 0x85 /* cmd id */
        ori r6, r0,  NVME_UCCQ0BASE0
        ori r7, r0,  NVME_UCCQ0BASE1      
        ori r8, r0,  1 /* queue id */
        ori r9, r0,  3 /* entries - 1*/
        brlid r15, admin_create_icq
        nop
        bnei r3, nvme_init_fail
        UCODE_STATUS(0x0D)
        
        /* create I/O submission queue */
        ori r5, r0, 0x86 /* cmd id */
        ori r6, r0,  NVME_UCSQ0BASE0 
        ori r7, r0,  NVME_UCSQ0BASE1
        ori r8, r0,  1
        ori r9, r0,  3
        ori r10, r0, 1  /* cq id */
        brlid r15, admin_create_isq
        nop
        bnei r3, nvme_init_fail
        UCODE_STATUS(0x0E)
        
        /* create I/O completion queue */
        ori r5, r0, 0x85 /* cmd id */
        ori r6, r0,  NVME_ICQ0BASE0 
        ori r7, r0,  NVME_ICQ0BASE1      
        ori r8, r0,  2 /* queue id */
        ori r9, r0, (IO_CQ_ENTRIES-1)
        brlid r15, admin_create_icq
        nop
        bnei r3, nvme_init_fail
        UCODE_STATUS(0x0F)

        /* set up IOSQ 2-17 used by SNTL */
        ori r22, r0, 0x200  /* SQid << 8 */        
        ori r23, r0, 0x1010 /* doorbell offset from NVME_BAR0 - fixme: doorbell stride */
        /* ori r24, r0, 32 /* ioq isq_mem size */
        /* ori r25, r0, 0  /* ioq isq_mem base */
        /* ori r26, r0, 16 /* loop count */
        
        /* use fc_config3 register to configure number of IOSQ to enable */
        lwi r12, r0, IO_BASE + REGS_FC_CONFIG3H
        andi  r24, r12, 0x3ff /* ioq isq_mem size */
        ori   r25, r0, 0      /* ioq isq_mem base */
        bsrli r26, r12, 16    
        andi  r26, r26, 0xff  /* loop count */
        
        /* compare requested count to number of allocated submission queues */
        /* if( allocated sq >= requested ), create # of requested iosq  */
        /* note that allocated value is a "0s based" number so a value of 8 really means 9 submission queues */
        /* but we've already created 1 submission queue for admin use above, so don't adjust for that */
        rsub r12, r26, r27   /* r12=r27-r26 */
        bgei r12, nvme_init_iosq_base 

        /* can't create as many iosq as requested, so pick a preset for number of queues */
        addi r12, r27, -16
        blti r12, nvme_init_iosq_12       
        ori r24, r0, 32 /* ioq isq_mem size */
        ori r25, r0, 0  /* ioq isq_mem base */
        ori r26, r0, 16 /* loop count */
        bri nvme_init_iosq_base
nvme_init_iosq_12:              
        addi r12, r27, -12
        blti r12, nvme_init_iosq_8
        ori r24, r0, 40 /* ioq isq_mem size */
        ori r25, r0, 0  /* ioq isq_mem base */
        ori r26, r0, 12 /* loop count */
        bri nvme_init_iosq_base
nvme_init_iosq_8:              
        addi r12, r27, -8
        blti r12, nvme_init_iosq_4
        ori r24, r0, 64 /* ioq isq_mem size */
        ori r25, r0, 0  /* ioq isq_mem base */
        ori r26, r0, 8  /* loop count */
        bri nvme_init_iosq_base
nvme_init_iosq_4:              
        addi r12, r27, -4
        blti r12, nvme_init_iosq_1
        ori r24, r0, 128 /* ioq isq_mem size */
        ori r25, r0, 0  /* ioq isq_mem base */
        ori r26, r0, 4  /* loop count */
        bri nvme_init_iosq_base
nvme_init_iosq_1:                     
        ori r24, r0, 512 /* ioq isq_mem size */
        ori r25, r0, 0  /* ioq isq_mem base */
        ori r26, r0, 1  /* loop count */

nvme_init_iosq_base:        
        ori r27, r0, IO_BASE+IOQ_OFFSET  /* pointer to isq config register table */
        swi r0, r11, REGS_FC_PNAMEH
        
nvme_init_iosq:         
        /* create I/O submission queue */
        ori   r5, r0, 0x86 /* cmd id */
        bslli r6, r25, 28
        addi  r6, r6,  NVME_ISQ0BASE0  /* msb 4b=<lsb of base> - lower 16b map to ioq isq_mem offset */
        bsrli r7, r25, 4
        add   r7, r7, r22
        addi  r7, r7,  NVME_ISQ0BASE1  /* 0x0002_0<sqid #><upper 8b of base> */
        bsrli r8, r22,  8  /* sqid */
        swi   r8, r0, IO_BASE + REGS_FC_STATUS2H  /* status to indicate how many iosqs were created */
        addi  r9, r24, -1  /* size - 0s based */
        ori   r10, r0, 2  /* cq id */
        brlid r15, admin_create_isq
        nop
        bnei  r3, nvme_init_fail
        UCODE_STATUS(0x10)

        /* iosq configuration registers */
        swi r23, r27, 12  /* doorbell address */
        swi r25, r27, 8  /* ioq isq_mem base */
        swi  r0, r27, 4  /* head/tail */
        swi r24, r27, 0  /* size */

        addi r22, r22, 0x100
        addi r23, r23, 8 /* fixme: doorbell stride */
        add  r25, r25, r24     
        addi r27, r27, 16
        addi r26, r26, -1
        swi  r22, r11, REGS_FC_PNAMEH
        bnei r26, nvme_init_iosq
        
        
        brlid r16, nvme_firmware_status
        nop
        bnei r3, nvme_init_fail
        UCODE_STATUS(0x15)
    
        /* set status output to indicate I/O Queue enabled */
        ori r12, r0, GPO_IOQ_ENABLE | GPO_CSTS_RDY
        swi r12, r0, IO_GPO1

        /* switch pcie trace from requester to completer */
        lwi r12, r0, IO_BASE + REGS_FC_CONFIG
        ori r12, r12, 0x00180000 /* pcie debug bits 4:3 */
        swi r12, r0, IO_BASE + REGS_FC_CONFIG

        /* clear retry counter */
        swi r0, r0, IO_BASE + REGS_TGT_NNAME        
        bri poll
/******************************************************************************/   
/* config & mmio ops to PCIe                                                  */        
/******************************************************************************/        

cfgrd_enum: 
/* CfgRd - first config read after reset to register 0
 * R3 = return data
 * R4 = nonzero for CRS status
 * R11, R12 - scratch
 */          
        ori r12, r0, 0x00F7  /* be, config read of reg 0 */
        ori r11, r0, IO_BASE
        swi r12, r11, PCIE_CONTROL
        bri pcie_reg_poll_nonposted_enum
        
cfgrd0: 
/* CfgRd0
 * R5 = 11:8 ext reg number
 *       7:2  register number
 *       1:0  reserved (register addr lsbs)
 * R3 = return data
 * R11, R12 - scratch
 */          
        bslli r12, r5, 16    /* move reg number to 31:16 */
        ori r12, r12, 0x00F7  /* be, config read */
        ori r11, r0, IO_BASE
        swi r12, r11, PCIE_CONTROL
        bri pcie_reg_poll_nonposted
        
/******************************************************************************/
cfgwr0: 
/* CfgWr0
 * R5 = 11:8 ext reg number
 *       7:2  register number
 *       1:0  reserved (register addr lsbs)
 * R6 = write data
 * R11, R12 - scratch
 */
        bslli r12, r5, 16     /* move reg number to 31:16 */
        ori r12, r12, 0x00F5  /* be, config write */
        ori r11, r0, IO_BASE
        swi r6, r11, PCIE_DATA0
        swi r12, r11, PCIE_CONTROL
        bri pcie_reg_poll_nonposted
                
/******************************************************************************/
mmiord4:
/* MMIO Read - 4B
 * R5 = register offset from NVME_BAR0/1
 * R3 = return read data
 * R11, R12 - scratch
 */
        ori r12, r0, NVME_BAR1        
        ori r11, r0, IO_BASE
        swi r12, r11, PCIE_ADDR1     
        ori r12, r5, NVME_BAR0
        swi r12, r11, PCIE_ADDR0
        ori r12, r0, 0x00F3   /* be=0xF, mmio read */
        swi r12, r11, PCIE_CONTROL
        bri pcie_reg_poll_nonposted

        
/******************************************************************************/
mmiowr4:
/* MMIO Write - 4B
 * R5 = register offset from NVME_BAR0/1
 * R6 = write data
 * R11, R12 - scratch
 */
        ori r12, r0, NVME_BAR1
        ori r11, r0, IO_BASE
        swi r12, r11, PCIE_ADDR1
        ori r12, r5, NVME_BAR0
        swi r12, r11, PCIE_ADDR0
        swi  r6, r11, PCIE_DATA0
        ori r12, r0, 0x00F1   /* be=0xF, mmio write */
        swi r12, r11, PCIE_CONTROL
        
pcie_reg_poll_posted:
        UCODE_STATUS_SUB(0x80)
pcie_reg_poll_posted_1:         
        lwi r12, r11, PCIE_STATUS
        
        /* check for link down */
        andi r3, r12, 0x0C  /* bits 3:2 = link reset, link down */
        bnei r3, pcie_link_down
        /* wait for command to be accepted.  no completion for posted command */
        andi r12, r12, 0x02
        beqi r12, pcie_reg_poll_posted_1
        UCODE_STATUS_SUB(0x81)                
        rtsd r15, 8
        nop
        
/******************************************************************************/
/* shared exit point for non-posted commands (cfgrd/cfgwr/mmiord)     
 * Read status reg until completed
 * then return from subroutine
 */
pcie_reg_poll_nonposted_enum:
        UCODE_STATUS_SUB(0x82)
        ori r4, r0, 1
        bri pcie_reg_poll_nonposted_1
        
pcie_reg_poll_nonposted:
        UCODE_STATUS_SUB(0x82)
        ori r4, r0, 0
        
pcie_reg_poll_nonposted_1:              
        lwi r12, r11, PCIE_STATUS

        /* check for link down */
        andi r3, r12, 0x0C  /* bits 3:2 = link reset, link down */
        bnei r3, pcie_link_down        
        andi r3, r12, 0x01
        beqi r3, pcie_reg_poll_nonposted_1

        /* check for timeout or other error status */
        /* on error, must reset the link and restart init */
        /* non-posted requests are only used during init */
        andi r3, r12, 0xFF0
        beqi r3, pcie_reg_poll_nonposted_good

        /* status[2:0]=3'b010, error code[3:0]=4'h2 is the xilinx encode for config retry status */
        xori r12, r3, 0x220  
        beqi r12, pcie_reg_poll_nonposted_crs
        
        UCODE_STATUS_SUB(0x83)
        UCODE_STATUS_RC(r3)
        bri pcie_error_nonposted

pcie_reg_poll_nonposted_good:
        UCODE_STATUS_SUB(0x84)
        or  r4, r0, r0
        lwi r3, r11, PCIE_DATA0
        rtsd r15, 8
        nop

pcie_reg_poll_nonposted_crs:
        UCODE_STATUS_SUB(0x85)
        UCODE_STATUS_RC(r3)
        beqi r4, pcie_error_nonposted /* if r4 is zero, CRS is treated as error */
        ori r4, r0, 2                 /* CRS status flag */
        lwi r3, r11, PCIE_DATA0        
        rtsd r15, 8
        nop
        
/***************************************/
nvme_init_fail:
        /* set error to generate interrupt */
        /* r3 = NVMe command status */
        ori r12, r0, FC_ERROR_NVMERC
        swi r12, r0, IO_BASE + REGS_FC_ERRSET
        UCODE_STATUS_SUB(0x50)
        UCODE_STATUS_RC(r3)
nvme_init_fail_poll:            
        lwi r12, r0, IO_GPI1
        andi r3, r12, GPI_INIT_DONE
        beqi r3, pcie_link_down        /* PCIe link went down - wait for link up and reinit */

        lwi r12, r0, IO_BASE + REGS_FC_ERRCAP  /* check that error has been cleared, then do a controller reset */
        beqi r12, nvme_controller_reset     
        
        bri nvme_init_fail_poll    
        
/***************************************/
/* wait for GPI input event            */                                 
poll:        
        ori r11, r0, IO_BASE
        UCODE_STATUS(0x40)

poll_1: 
        lwi r12, r0, IO_GPI1
        
        andi r3, r12, GPI_INIT_DONE
        beqi r3, pcie_link_down        /* PCIe link went down - wait for link up and reinit */

        andi r3, r12, GPI_CTL_ENABLE
        beqi r3, nvme_controller_reset /* controller disabled - do a reset */

        andi r3, r12, GPI_LUNRESET     /* SCSI LUN reset maps to NVMe controller reset */
        bnei r3, nvme_controller_reset 

        andi r3, r12, GPI_ADMIN_CMD
        bnei r3, sntl_cmd              /* process sislite command from SNTL */

        andi r3, r12, GPI_SHUTDOWN
        bnei r3, nvme_shutdown         /* Do normal NVMe shutdown processing */

        andi r3, r12, GPI_SHUTDOWN_ABRUPT
        bnei r3, nvme_shutdown_abrupt  /* Do abrupt NVMe shutdown processing */
        
        andi r3, r12, GPI_LD_ROM
        beqi  r3, poll_1
        brlid r15, load_rom            /* load rom from mmio regs for debug */
        nop
        
        bri poll_1


/*************************************************************/
/* subroutine to set firmware status reg */
/* input:     r16 = return address */
/* modifies:  r3, r5, r6, r7, r8, r12  */
nvme_firmware_status:        
        /* get current firmware status */
        andi r5, r27, 0x0FFF   /* cmd id */
        ori r6, r0, 15         /* number of dwords (0s based) = 64B/4-1 */
        ori r7, r0, 0xFFFFFFFF /* namespace id == global */
        ori r8, r0, 0x03       /* log page id = firmware slot info */
        brlid r15, admin_get_log
        nop
        bnei  r3, nvme_firmware_status_2
        
        lwi    r7, r11, SNTL_ADQ_BUFFER  /* byte 0 = Active Firmware info */
        andi   r7,  r7, 0xff
        lwi    r6, r11, REGS_NVME_FW_STATUS
        andi   r6,  r6, 0xff00            /* keep 15:8 and replace 7:0 with AFI */
        or     r6,  r7, r6
        swi    r6, r11, REGS_NVME_FW_STATUS
        
        andi    r6,  r7, 0x7  /* active slot */
        bslli   r6,  r6, 3   /* x 8 */
        add     r6,  r6, r11  /* add offset to base address */
        lwi    r12,  r6, SNTL_ADQ_BUFFER
        swi    r12, r11, REGS_NVME_FW_ACTIVE        
        lwi    r12,  r6, SNTL_ADQ_BUFFER+4
        swi    r12, r11, REGS_NVME_FW_ACTIVE+4
       
        andi   r6,  r7, 0x70  /* next slot */
        bsrli  r6,  r6, 1     /* (shift 4 left then 3 right ) == x 8 */        
        bnei   r6, nvme_firmware_status_1  /* if zero, then set fw_next = fw_active */
        
        andi    r6,  r7, 0x7  /* active slot */
        bslli   r6,  r6, 3   /* x 8 */
nvme_firmware_status_1: 
        
        add    r6,  r6, r11   /* add offset to base address */
        lwi   r12,  r6, SNTL_ADQ_BUFFER
        swi   r12, r11, REGS_NVME_FW_NEXT
        lwi   r12,  r6, SNTL_ADQ_BUFFER+4
        swi   r12, r11, REGS_NVME_FW_NEXT+4

nvme_firmware_status_2: 
        rtsd  r16, 8
        nop 
        

/*************************************************************/
/* NVMe controller reset                                     */
/*************************************************************/     
/* reset if after init of NVMe controller, enable input is deasserted */
nvme_controller_reset:   
        UCODE_STATUS_SUB(0x20)    
        
        /* disable NVMe controller  */
        MMIORD4I(NVME_REG_CC)        
        andi r3, r3, 0xFFFFFFFE  /* clear enable bit in controller config */
        MMIOWR4(NVME_REG_CC,r3)   
      
nvme_controller_reset_nrdy:    
        /* wait for controller status ready = 0 */         
        MMIORD4I(NVME_REG_CSTS)
        andi r3,r3,0x01      
        bnei r3, nvme_controller_reset_nrdy

        UCODE_STATUS_SUB(0x21)
        
         /* after controller is idle, set status output to indicate I/O Queue disabled and controller not ready */
        swi r0, r0, IO_GPO1     
        /* reset ASQ/ACQ pointers */      
        swi r0, r0, IO_BASE + ASQ_RESET

        /* wait for enable then reinit NVMe controller */
nvme_controller_reset_init:     
        lwi r12, r0, IO_GPI1
        andi r3, r12, GPI_INIT_DONE
        beqi r3, pcie_link_down    /* PCIe link went down - wait for link up and reinit */
        andi r3, r12, GPI_CTL_ENABLE
        beqi r3, nvme_controller_reset_init
        
        UCODE_STATUS_SUB(0x22)       


        MMIORD4I(NVME_REG_CAP+4)        
        /* write controller config with page size, enable=0 */
        bsrli r24, r3, 20
        andi  r24, r24, 0xF  /* r24 = CAP.MPSMAX */
        bslli r24, r24, 7    /* 10:7 = CC.MPS */
        ori   r24, r24, 0x00460000  /* set IOCQES=4 and IOSQES=6 */
        MMIOWR4(NVME_REG_CC,r24)
        ori r24, r24, 0x01  /* set enable bit in controller config */
        MMIOWR4(NVME_REG_CC,r24)   
        bri nvme_init_rdy    
  

/*************************************************************/
/* NVMe normal shutdown                                      */
/*************************************************************/
nvme_shutdown:  
        /* see NVMe 1.1b 7.6.2 */

        /* indicate shutdown is active.  leave port in ready state so that driver doesn't try to recover */
        ori r12, r0, GPO_SHUTDOWN | GPO_IOQ_ENABLE | GPO_CSTS_RDY
        swi r12, r0, IO_GPO1

        UCODE_STATUS_SUB(0x40)
nvme_shutdown_1:        
        /* wait for I/O submission and completion queues to empty */
        lwi r12, r0, IO_GPI1
        andi r12, r12, (GPI_ISQ_EMPTY | GPI_ICQ_EMPTY)
        xori r12, r12, (GPI_ISQ_EMPTY | GPI_ICQ_EMPTY)
        bnei r12, nvme_shutdown_1

        /* fc_config3 register hold number of IOSQs for sntl use */
        lwi r12, r0, IO_BASE + REGS_FC_CONFIG3H        
        bsrli r12, r12, 16
        andi  r26, r12, 0xff  /* loop count */

        /* delete I/O submission queues */
        /* first delete the iosq used by microcode */
        ori r5, r0, 0x87 /* cmd id */
        ori r8, r0, 1
        brlid r15, admin_delete_isq
        nop       

        ori r8, r0, 2
nvme_shutdown_isq:            
        ori r5, r0, 0x87 /* cmd id */
        brlid r15, admin_delete_isq
        nop
        addi r8, r8, 1
        addi r26, r26, -1
        bnei r26, nvme_shutdown_isq
                          
        /* delete I/O completion queue */
        ori r5, r0, 0x87 /* cmd id */    
        ori r8, r0, 1    
        brlid r15, admin_delete_icq
        nop                                       
        ori r5, r0, 0x87 /* cmd id */    
        ori r8, r0, 2   
        brlid r15, admin_delete_icq
        nop                               

        /* write Shutdown notification = 01b (normal) in CC.SHN */
        MMIORD4I(NVME_REG_CC)
        ori r3, r3, (0x01 << 14)

        MMIOWR4(NVME_REG_CC,r3)
        
        UCODE_STATUS_SUB(0x41)
nvme_shutdown_status:
        lwi r12, r0, IO_GPI1        
        andi r3, r12, GPI_INIT_DONE
        beqi r3, pcie_link_down    /* PCIe link went down - wait for link up and reinit */      
        andi r3, r12, GPI_CTL_ENABLE        
        beqi r3, nvme_controller_reset /* controller disabled - do a reset */
          
        MMIORD4I(NVME_REG_CSTS)
        andi r3, r3, 0x0c
        xori r3, r3, 0x08
        bnei r3, nvme_shutdown_status

        /* indicate shutdown complete.  leave IOQ enabled so the driver sees "port ready" */
        ori r12, r0, GPO_SHUTDOWN_CMP | GPO_SHUTDOWN | GPO_IOQ_ENABLE | GPO_CSTS_RDY
        swi r12, r0, IO_GPO1
        
        UCODE_STATUS_SUB(0x42)
nvme_shutdown_wait:     
        lwi r12, r0, IO_GPI1        
        andi r3, r12, GPI_INIT_DONE
        beqi r3, pcie_link_down        /* PCIe link went down - wait for link up and reinit */      
        andi r3, r12, GPI_CTL_ENABLE
        beqi r3, nvme_controller_reset /* controller disabled - do a reset */
        bri nvme_shutdown_wait        

nvme_shutdown_abrupt:
        UCODE_STATUS_SUB(0x43)
        ori r12, r0, GPO_SHUTDOWN | GPO_IOQ_ENABLE | GPO_CSTS_RDY
        swi r12, r0, IO_GPO1
 
        /* write Shutdown notification = 10b (abrupt) in CC.SHN */
        MMIORD4I(NVME_REG_CC)
        ori r3, r3, (0x02 << 14)
        MMIOWR4(NVME_REG_CC,r3)  
        bri nvme_shutdown_status
               
                   
/******************************************************************************/ 
/* SNTL - SCSI NVMe Translation layer                                         */
/* translate SCSI command to NVMe                                             */
/******************************************************************************/      
sntl_cmd:      
        /* new SCSI command available for translation */
        UCODE_STATUS(0x21)
       
        ori r12, r0, GPO_IOQ_ENABLE | GPO_CSTS_RDY
        swi r12, r0, IO_GPO1

        ori r11, r0, IO_BASE
        lwi r19, r11, SNTL_COMMAND
        lwi r20, r11, SNTL_LENGTH
        lwi r21, r11, SNTL_LUN03
        lwi r22, r11, SNTL_LUN47
        lwi r23, r11, SNTL_CDB03
        lwi r24, r11, SNTL_CDB47
        lwi r25, r11, SNTL_CDB8B
        lwi r26, r11, SNTL_CDBCF
        lwi r27, r11, SNTL_SISL_CID

        swi r0, r11, SNTL_SISL_RELOFF 
        swi r0, r11, SNTL_SISL_LENGTH  /* default length to zero for error status */
        swi r0, r11, SNTL_STATUS1 

        /* decode command encode */
        andi r28, r19, 0xff
        xori r29, r28, CMD_RD
        beqi r29, sntl_cmd_rd

        xori r29, r28, CMD_WR
        beqi r29, sntl_cmd_wr

        xori r29, r28, CMD_TASKMAN
        beqi r29, sntl_cmd_taskman

        xori r29, r28, CMD_ABORT
        beqi r29, sntl_cmd_abort
        
        bri sntl_sc_not_impl /* unimplemented command response */

sntl_cmd_rd:
        /* decode opcode */
        bsrli r28, r23, 24 /* move CDB byte 0 to r28[7:0] */

        xori r29, r28, SCSI_INQUIRY
        beqi r29, sntl_inquiry

        xori r29, r28, SCSI_REPORT_LUNS
        beqi r29, sntl_report_luns
        
        xori r29, r28, SCSI_READ_CAPACITY
        beqi r29, sntl_read_cap
        xori r29, r28, SCSI_SERVICE_ACTION_IN
        beqi r29, sntl_read_cap

        xori r29, r28, SCSI_MODE_SENSE
        beqi r29, sntl_mode_sense
        xori r29, r28, SCSI_MODE_SENSE_10
        beqi r29, sntl_mode_sense_10
        
        xori r29, r28, SCSI_TEST_UNIT_READY
        beqi r29, sntl_sc_success

        xori r29, r28, 0xC0
        beqi r29, sntl_cmd_passthru

        xori r29, r28, SCSI_LOG_SENSE
        beqi r29, sntl_log_sense

        bnei r20, sntl_sc_not_impl  /* if length=0, allow WRITE_BUFFER to use READ flag */
        
        xori r29, r28, SCSI_WRITE_BUFFER
        beqi r29, sntl_write_buffer
        
        bri  sntl_sc_not_impl  
        
sntl_cmd_wr:
        /* decode opcode */
        bsrli r28, r23, 24 /* move CDB byte 0 to r28[7:0] */

        xori r29, r28, SCSI_FORMAT_UNIT
        beqi r29, sntl_format_unit

        xori r29, r28, SCSI_WRITE_BUFFER
        beqi r29, sntl_write_buffer

        xori r29, r28, SCSI_MODE_SELECT
        beqi r29, sntl_mode_select
        xori r29, r28, SCSI_MODE_SELECT_10
        beqi r29, sntl_mode_select_10
        
        xori r29, r28, SCSI_UNMAP
        
        #ifdef UNMAP
        beqi r29, sntl_unmap
        #else
        beqi r29, sntl_sc_not_impl
        #endif
        
        bri sntl_sc_not_impl
        
sntl_cmd_abort:
        /* abort I/O command */
        andi r5, r27, 0xFFFF   /* cmd id */
        andi r6, r22, 0x1F /* SQID */
        brlid r15, admin_abort_io
        nop
        ori r12, r0,  (NVME_SC_VALID | NVME_SC_S_ABORT_COMPLETE)
        swi r12, r11, SNTL_STATUS0
        bri sntl_sc_poll
        

sntl_cmd_taskman:
        /* task management commands are defined in sislite */
        /* ClearACA and LUNRESET are handled in HW */
        /* return "rejected" status for others */
        bri sntl_sc_tmf_reject

        /* debug NVMe passthru */
sntl_cmd_passthru:             
        ori  r5, r27, 0    /* command id */
        
        bsrli r6, r23, 16  /* move CDB byte 1 to r6[7:0] */
        andi r6, r6, 0xFF  /* opcode */
        ori  r7, r21, 0    /* lunid bytes 0-3 */
        ori  r8, r24, 0    /* CDB4-7 = DW10 */
        ori  r9, r25, 0    /* CDB8-11 = DW11 */
        brlid r15, admin_passthru
        nop
        /* r6 = dw3 (status) r5 = dw0 on exit */
        bsrli r12, r6, 17  /* dw3[31:17] == status */
        ori r12, r0, NVME_SC_VALID
        swi r12, r11, SNTL_STATUS0
        bri sntl_sc_poll

/*****************************************************************************/
/* sntl response - set status code & valid then wait for the sislite response to be taken */
                      
sntl_sc_not_impl:    
        ori r12, r0,  (NVME_SC_VALID | NVME_SC_S_NOT_IMPL)
        swi r12, r11, SNTL_STATUS0
        bri sntl_sc_poll
        
sntl_sc_success:    /* send status=success completion to host */
        ori r12, r0,  (NVME_SC_VALID | NVME_SC_G_SUCCESS)
        swi r12, r11, SNTL_STATUS0        
        bri sntl_sc_poll

sntl_sc_invalid: /* send status="invalid field in cdb" completion to host */
        ori r12, r0,  (NVME_SC_VALID | NVME_SC_G_INVALID_FIELD)
        swi r12, r11, SNTL_STATUS0        
        bri sntl_sc_poll
        
sntl_sc_invalid_param: /* send status="invalid field in parameter list" completion to host */
        ori r12, r0,  (NVME_SC_VALID | NVME_SC_S_INVALID_FIELD_IN_PARAM)
        swi r12, r11, SNTL_STATUS0        
        bri sntl_sc_poll
        
sntl_sc_lun_not_supported: /* send status="lun not supported" completion to host */
        /* invalid LUN - SAM-5 5.11 states that check condition/illegal request/logical unit not supported 
         *               should be returned for command other than request_sense, report_luns, or inquiry */
        ori r12, r0,  (NVME_SC_VALID | NVME_SC_S_LOGICAL_UNIT_NOT_SUPPORTED )
        swi r12, r11, SNTL_STATUS0        
        bri sntl_sc_poll

sntl_sc_admin_error:    /* error status for admin command */
        ori r12, r3, NVME_SC_VALID
        swi r12, r11, SNTL_STATUS0
        bri sntl_sc_poll

sntl_sc_tmf_reject:
        ori r12, r0,  (NVME_SC_VALID | NVME_SC_S_TMF_REJECT )
        swi r12, r11, SNTL_STATUS0        
        bri sntl_sc_poll
                         
sntl_sc_tmf_lun:
        ori r12, r0,  (NVME_SC_VALID | NVME_SC_S_TMF_LUN )
        swi r12, r11, SNTL_STATUS0        
        bri sntl_sc_poll
                         
        
sntl_sc_poll:   
        UCODE_STATUS(0x22)
sntl_sc_poll_1:
        lwi r12, r0, IO_GPI1
        andi r12, r12, GPI_ADMIN_CPL  /* wait for completion busy = 0 */
        bnei r12, sntl_sc_poll_1
        bri poll
                                
/*****************************************************************************
 * MODE_SENSE(6)
 * cdb byte 1 bit    3: DBD bit (disable block descriptor)
 * cdb byte 2 bit  7:6: PC bit  (page control (current/changeable/default/saved values)
 * cdb byte 2 bits 5:0: page code
 * cdb byte 3:          subpage code
 * cdb byte 4:          allocation length
 * cdb byte 5:          control
 *
 * returns:
 * bytes 0-3: mode parameter header (1B length, 1B medium type, 1B device specific param, 1B block descriptor length)
 *       4-?: mode page data
 *
 * MODE_SENSE(10)
 * cdb byte 1 bit    3: DBD bit
 * cdb byte 1 bit    4: LLBAA bit 
 * cdb byte 2 bit  7:6: PC bit
 * cdb byte 2 bits 5:0: page code
 * cdb byte 3:          subpage code
 * cdb byte 7&8:        allocation length
 * cdb byte 9:          control
 *
 * returns:     
 * bytes 0-3: mode parameter header (2B length, 1B medium type, 1B device specific param)
 *       4-7: byte 4 bit 0=LONGLBA flag, 6/7=2B block descriptor length
 *       8-?: mode page data
 *
 *
 * on entry: 
 *  r11 = IO_BASE
 *  r19-r27 = command fields
 *  r28 = scsi opcode
 * modifies: 
 *  r3-r7, r12, r15, r28, r29 - temp variables
 *    r10 = write protect flag 
 *    r30 = allocation length
 *
 * spec references: NVM Express SCSI Translation v1.5 6.4
 *                  SPC-4 6.13 & 6.14
 */
sntl_mode_sense:
sntl_mode_sense_10:
        swi r0, r11, SNTL_SISL_CLEAR  /* clear SISL (response) buffer */
        
        or    r10, r0, r0  /* initial value for write protect bit */

        /* check PC */
        bsrli r29, r23, 14  
        andi  r29, r29, 0x03  /* r28 = PC = cdb byte 2 bits 7:6 */

        xori  r12, r29, 0x03  
        beqi  r12, sntl_sc_invalid         /* PC=11b */  
        beqi  r29, sntl_mode_sense_current /* PC=00b */
        xori  r12, r29, 0x01               
        beqi  r12, sntl_mode_sense_changeable                
        bri   sntl_sc_not_impl

     
                        
sntl_mode_sense_current:
        /* first get the WP header bit value */
        andi r5, r27, 0x0FFF   /* cmd id */
        ori r6, r0, 47         /* number of dwords (0s based) = 192B/4-1 */
        ori r7, r0, 0xFFFFFFFF /* namespace id == global */
        ori r8, r0, 0x02       /* log page id = SMART/Health Info */
        brlid r15, admin_get_log
        nop

        lwi r10, r11, SNTL_ADQ_BUFFER
        bsrli r10, r10, 3
        andi  r10, r10, 0x01  /* r10 = "media in read only mode" bit from Critical Warning byte */

        /* get "Temperature Threshold" value and save in page 00 */
        andi r5, r27, 0x0FFF   /* cmd id */
        ori r6, r0, 0x04       /* feature id  */
        ori r7, r0, 0x00000000 /* namespace id == reserved */
        ori r8, r0, 0x00       /* select = current  */     
        brlid r15, admin_get_features
        nop
        andi r5, r5, 0x00FFFF /* temp threshold in Kelvin */
        or   r6, r0, r0
        beqi r5, sntl_mode_sense_no_temp
        xori r12, r5, 0x00FFFF
        beqi r12, sntl_mode_sense_no_temp
        addi r12, r5, -273  /* convert to Celcius */
        blei r12, sntl_mode_sense_no_temp
        or   r6, r12, r0
        
sntl_mode_sense_no_temp:
        ori r12, r0, mode_page_00_threshold
        sb  r6, r12, r0
        
        /* get "Time limited Error Recovery" value */
        andi r5, r27, 0x0FFF   /* cmd id */
        ori r6, r0, 0x05       /* feature id = 0x05 "Error Recovery" */
        ori r7, r0, 0x00000000 /* namespace id == reserved */
        ori r8, r0, 0x00       /* select = current  */     
        brlid r15, admin_get_features
        nop
        
        andi r5, r5, 0x00FFFF   /* r5 = time limited error recovery value from completion DW0 */
        /* change to 1ms units from 100ms units */
        brlid r15, div10
        nop
        brlid r15, div10
        nop
        ori r12, r0, mode_page_01_time
        sh  r5, r12, r0  /* store 16b time value */

        /* get number of blocks for descriptor */
        /* parse LUNID => namespace id */
        or r5, r21, r0
        or r6, r22, r0
        brlid r15, lunid2nsid
        nop
        bnei r4, sntl_sc_lun_not_supported
        
        andi r5, r27, 0x0FFF   /* cmd id */
        ori r6, r0, 0x00 /* identify namespace */
        or  r7, r0, r3   /* namespace id */
        brlid r15, admin_identify
        nop
                
        brlid r15, sntl_get_ns_blocksize  /* reads SNTL_ADQ_BUFFER, returns r12=LBADS {r6,r5} = number of 4K blocks */
        nop
     
        beqi  r6, sntl_mode_sense_descriptor_nlba
        ori   r5, r5, 0xFFFFFFFF  /* number of logical blocks too large */
sntl_mode_sense_descriptor_nlba:
        swapb r5, r5
        swi   r5, r0,  mode_block_descriptor
        
sntl_mode_sense_changeable:      
        /* set r5 = length of mode page header (4 for MODE_SENSE(6), 8 for MODE_SENSE(10)) */
        /* set r30 = allocation length */
        /* assume MODE_SENSE(6) */
        ori    r5,  r0, 4
        bsrli r30, r24, 24  /* r24 = CDB bytes 4..7.  allocation length == byte 4 */
        
        xori  r12, r28, SCSI_MODE_SENSE  /* r28=opcode on entry */
        beqi  r12, sntl_mode_sense_page
        /* MODE_SENSE(10) specific code */
        ori    r5,  r0, 8
        bsrli r30, r25, 24  /* CDB byte 8 = lsb of allocation length */
        andi  r12, r24, 0xff
        bslli r12, r12, 8
        or    r30, r30, r12   /* r30 == allocation length */
        
sntl_mode_sense_page:                   
        /* get page code from CDB bytes 2 */ 
        bsrli r28, r23, 8
        andi  r28, r28, 0x3F  /* r28 = page code */

        beqi r28, sntl_mode_sense_00
        xori r12, r28, 0x01
        beqi r12, sntl_mode_sense_01
        xori r12, r28, 0x08
        beqi r12, sntl_mode_sense_08
        xori r12, r28, 0x0A
        beqi r12, sntl_mode_sense_0A
        xori r12, r28, 0x1A
        beqi r12, sntl_mode_sense_1A
        xori r12, r28, 0x1C
        beqi r12, sntl_mode_sense_1C
        xori r12, r28, 0x3F
        beqi r12, sntl_mode_sense_3F
        bri  sntl_sc_invalid

        /* r5 = length of header */
sntl_mode_sense_00:               
        /* set r6 = address of mode page data */
        ori r6, r0, mode_page_00
        /* set r7 = length of mode page data */
        ori r7, r0, 16       
        bri sntl_mode_sense_payload
        
sntl_mode_sense_01:               
        /* set r6 = address of mode page data */
        ori r6, r0, mode_page_01 
        /* set r7 = length of mode page data */
        ori r7, r0, 12       
        bri sntl_mode_sense_payload
        
sntl_mode_sense_08:                      
        ori r6, r0, mode_page_08        
        ori r7, r0, 20       
        bri sntl_mode_sense_payload
        
sntl_mode_sense_0A:              
        ori r6, r0, mode_page_0A     
        ori r7, r0, 12       
        bri sntl_mode_sense_payload

sntl_mode_sense_1A:       
        ori r6, r0, mode_page_1A 
        ori r7, r0, 40       
        bri sntl_mode_sense_payload
        
sntl_mode_sense_1C:       
        ori r6, r0, mode_page_1C
        ori r7, r0, 12       
        bri sntl_mode_sense_payload
        
sntl_mode_sense_3F:       
        ori r6, r0, mode_page_01
        ori r7, r0, 112       
        bri sntl_mode_sense_payload

sntl_mode_sense_payload:
        /* build header for MODE_SENSE(6) first */
        /* byte 0 = length */
        /* byte 1 = medium type = 00 for direct access block device */
        /* byte 2 = device parameters - see SBC-3 6.51 - bit 7=WP  bit 4=DPOFUA */
        /* byte 3 = block descriptor length */
        /* r5 = length of header */
        /* r7 = length of mode page data */
        add r12, r5, r7    
        addi r12, r12, 8 
        swi r12, r11, SNTL_SISL_LENGTH 
        addi r12, r12, -1  /* length does not include length byte itself */        
        /* r10 = WP - move to byte 2 bit 7 */
        bslli r8, r10, 23
        or r12, r12, r8
        ori r12, r12, 0x08100000  /* set byte 2 bit 4 = DPOFUA */
        swi r12, r11, SNTL_SISL_BUFFER
        xori r12, r5, 4
        beqi r12, sntl_mode_sense_descriptor_copy

        /* build header for MODE_SENSE(10) */
        /* byte 0&1 = length */
        /* byte 2 = medium type = 00 for direct access block device */
        /* byte 3 = device parameters - see SBC-3 6.51 - bit 7=WP  bit 4=DPOFUA */
        /* byte 6&7 = block descriptor length */
        /* r5 = length of header */
        /* r7 = length of mode page data */
        add r12, r5, r7      
        addi r12, r12, 8 
        swi r12, r11, SNTL_SISL_LENGTH 
        addi r12, r12, -2  /* length does not include length bytes */
        bslli r12, r12, 8  /* length lsb in byte 1 */
        /* r10 = WP - move to byte 3 bit 7 */
        bslli r8, r10, 31
        or r12, r12, r8
        ori r12, r12, 0x10000000  /* set byte 3 bit 4 = DPOFUA */
        swi r12, r11, SNTL_SISL_BUFFER
        ori r12, r0, 0x08000000
        swi r12, r11, SNTL_SISL_BUFFER+4

sntl_mode_sense_descriptor_copy:             
        lwi r12, r0, mode_block_descriptor
        swi r12, r5, IO_BASE+SNTL_SISL_BUFFER   
        lwi r12, r0, mode_block_descriptor+4
        swi r12, r5, IO_BASE+SNTL_SISL_BUFFER+4
        addi r5, r5, 8
        
sntl_mode_sense_copy:   
        /* copy payload to buffer */
        /* source = r6 */
        /* dest = IO_BASE+SNTL_SISL_BUFFER+r5 */
        /* length in bytes = r7 */
        
        ori r8, r0, -4
        addi r5, r5, IO_BASE+SNTL_SISL_BUFFER
        
        xori  r12, r29, 0x01               
        beqi  r12, sntl_mode_sense_copy_changeable

sntl_mode_sense_copy_loop:
        add r7, r7, r8  /* decrement offset by 1 dword */
        lw  r12, r6, r7
        sw  r12, r5, r7
        bnei r7, sntl_mode_sense_copy_loop          
    
sntl_mode_sense_length:             
        /* check allocation length vs length */
        lwi r12, r11, SNTL_SISL_LENGTH
        rsub r12, r30, r12  /* r12=length-allocation length */
        blei r12, sntl_mode_sense_length_1
        swi r30, r11. SNTL_SISL_LENGTH  /* set length = allocation length */
sntl_mode_sense_length_1:         
        swi r0, r11, SNTL_SISL_PAYLOAD  /* send payload to host */                
        bri sntl_sc_success                

sntl_mode_sense_copy_changeable:
        /* just copy the first 2 bytes and leave everything else as zero */
        lw   r12, r6, r0
        andi r12, r12, 0x00ffff
        sw  r12, r5, r0
        bri sntl_mode_sense_length
        
.data     
        /* build data in memory for all mode pages in the order required by page=all */

        .balign 4
mode_page_01:
        /* Read-Write Error Recovery mode page - SBC-3 6.5.8  and SNTL 6.3.3.1 */
        .byte 0x01, 0x0A  /* page code/length */
        .byte 0b11000000  /* error handling flags - AWRE, ARRE, TB, RC, EER, PER, DTE, DCR */        
        .byte 0x10        /* read retry count = dummy value unspecified by SNTL */
        .byte 0x00,0x00,0x00 /* reserved */
        .byte 0x00        /* LBPERE bit (not specified by SNTL), reserved */
        .byte 0x10        /* write retry count = dummy value unspecified by SNTL */
        .byte 0x00        /* reserved */
mode_page_01_time:      
        .byte 0x00,0x00   /* recovery time limit - maps to NVME "Time Limited Error Recovery" of Error Recovery Feature */
        
mode_page_08:
        /* Caching Mode Page Field - SBC-3 6.5.5 and SNTL 6.3.3.2 */
        /* all fields except "WCE" are unspecified by SNTL */
        /* WCE = byte 2 bit 2 maps to NVME "Volatile Write Cache Enable" in the Volatile Write Cache Feature */
        /* note: the Samsung part does not have a write cache */
        .byte 0x08, 0x12
        .byte 0x00  /* IC, ABPF, CAP, DISC, SIZE, WCE, MF, RCD */
        .byte 0x00  /* demand read retention priority, write retention priority */
        .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00  /* prefetch lengths */
        .byte 0x00 /* FSW, LBCSS, DRA, vendor specific 2b, SYNC_PROG 2b, NV_DIS */
        .byte 0x00 /*nubmer of cache segments */
        .byte 0x00, 0x00 /* cache segment size */
        .byte 0x00,0x00,0x00,0x00 /* reserved/obsolete */
        
mode_page_0A:
        /* Control mode page - SPC-4 7.5.7 & SNTL 6.3.3.3 */
        .byte 0x0A, 0x0A  /* page code/length */
        .byte 0b00001110  /* TST=000 TMF_ONLY=0 DPICZ=1 D_SENSE=1 GLTSD=1 RLEC=0 (should check DPICZ value?) */
        .byte 0b00010010  /* QUEUE ALGO MODIFIER=0b0001 NUAR=0 (reservations not supported) QERR=0b01 */
        .byte 0b00000000  /* VS RAC=0 UA_INTLCK_CTRL=0b00 SWP=0 */
        .byte 0b11000000  /* ATO=1 TAS=1 ATMPE=0 RWWP=0 revs AUTOLOAD MODE=000 */
        .byte 0x00, 0x00  /* obsolete */
        .byte 0xff, 0xff  /* byte timeout period */
        .byte 0x00, 0x00  /* extended self-test completion time */
mode_page_1A:
        /* Power Condition mode page - SPC-4 7.5.12 and SNTL 6.3.3.4 */
        .byte 0x1A, 0x26  /* page code/length */
        /* timers not supported - bytes 2-39 all zeros */
        .byte 0x00, 0x00
        .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
        .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
        .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
        .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
        .byte 0x00, 0x00, 0x00, 0x00
mode_page_1C:
        /* Informational Expections Control mode page - SBC-3 6.5.6 and SNTL 6.3.3.7 */
        .byte 0x1C, 0x0A  /* page code/length */
/*        .byte 0b10001000  */ /* PERF=1 resv EBF=0 EWASC=0 DEXCPT=1 TEST=0 EBACKERR=0 LOGERR=0 */
        /* SNTL has PERF=1 DEXCPT=1.  But smartmon wants PERF=0 and DEXCPT=0 */
        .byte 0b00000000  /* PERF=0 resv EBF=0 EWASC=0 DEXCPT=0 TEST=0 EBACKERR=0 LOGERR=0 */
        .byte 0x00        /* MRIE=0x0 */
        .byte 0x00, 0x00, 0x00, 0x00 /* interval timer */
        .byte 0x00, 0x00, 0x00, 0x00 /* report count */
                        
mode_page_00:
        /* Vendor defined page for setting temp threshold with MODE_SELECT */
        .byte 0x00, 0x0E  /* page code/length */        
        .byte 0x00, 0x00,0x00,0x00,0x00,0x00,0x00        /* bytes 2-8 reserved */
mode_page_00_threshold: 
        .byte 0x00  /* temp threshold in celcius */  
        .byte 0x00,0x00,0x00,0x00,0x00,0x00        /* bytes 10-15 reserved */    
   
mode_block_descriptor:  
        .byte 0x00, 0x00, 0x00, 0x00  /* number of logical blocks */
        .byte 0x00  /* reserved */
        .byte 0x00, 0x10, 0x00  /* logical block length = 4096B */
        
.section .boot
        
/*****************************************************************************/
div10:  
        /* binary divide by 10 without mult/div instructions */
        /* input = r3 */
        /* output = r3 */
        /* accurate for 16b */
        /* r3/10 = r3 * 1/10 = r3 * 0b0.00011001100110011 = r3 * 0x0.1999A = r3 * 0x1999A/(2*20) */
        /* uses r12 */
        bsrli r12, r3, 2
        add   r12, r12, r3
        bsrli r12, r12, 1  /* r12 = r3 * 0.101 */
        add   r12, r12, r3               
        bsrli r12, r12, 3  /* r12 = r3 * 0.001101 */
        add   r12, r12, r3               
        bsrli r12, r12, 1  /* r12 = r3 * 0.1001101 */
        add   r12, r12, r3               
        bsrli r12, r12, 3  /* r12 = r3 * 0.0011001101 */
        add   r12, r12, r3               
        bsrli r12, r12, 1  /* r12 = r3 * 0.10011001101 */
        add   r12, r12, r3               
        bsrli r12, r12, 3  /* r12 = r3 * 0.00110011001101 */
        add   r12, r12, r3               
        bsrli r12, r12, 1  /* r12 = r3 * 0.100110011001101 */
        add   r12, r12, r3               
        bsrli r3, r12, 4  /* r12 = r3 * 0.0001100110011001101 */       
        rtsd r15, 8
        nop  
        
mul10:  
        /* multiply by 10 */
        /* x*10 = x*8 + x*2 */
        bslli r12, r3, 3
        bslli r3, r3, 1
        add r3, r3, r12
        rtsd r15, 8
        nop

/*****************************************************************************
 * MODE_SELECT(6) - SPC-4 6.11
   // +=====-=======-=======-=======-=======-=======-=======-=======-=======+
   // |  Bit|   7   |   6   |   5   |   4   |   3   |   2   |   1   |   0   |
   // |Byte |       |       |       |       |       |       |       |       |
   // |=====+=======================+=======================================|
   // | 0   |                        Operation code (15h)                   |
   // |-----+---------------------------------------------------------------|
   // | 1   |  Reserved             |  PF   |  reserved             |  SP   |
   // |-----+---------------------------------------------------------------|
   // | 2   |                                                               |
   // |-----+---                     Reserved                            ---|
   // | 3   |                                                               |
   // |-----+---------------------------------------------------------------|
   // | 4   |                        Parameter List Length                  |
   // |-----+---------------------------------------------------------------|
   // | 5   |                        Control                                |  
   // |=====+===============================================================|
        
 * MODE_SELECT(10) SPC-4 6.12        
   // +=====-=======-=======-=======-=======-=======-=======-=======-=======+
   // |  Bit|   7   |   6   |   5   |   4   |   3   |   2   |   1   |   0   |
   // |Byte |       |       |       |       |       |       |       |       |
   // |=====+=======================+=======================================|
   // | 0   |                        Operation code (55h)                   |
   // |-----+---------------------------------------------------------------|
   // | 1   |  Reserved             |  PF   |  reserved             |  SP   |
   // |-----+---------------------------------------------------------------|
   // | 2   |                                                               |
   // |-----+---                     Reserved                            ---|
   // | 6   |                                                               |
   // |-----+---------------------------------------------------------------|
   // | 7   | (MSB)                                                         |
   // |-----+----                    Parameter List Length               ---|
   // | 8   |                                                        (LSB)  |
   // |-----+---------------------------------------------------------------|
   // | 9   |                        Control                                |  
   // |=====+===============================================================|        
 */

 /* SNTL 4.3 defines translation
  * only page supported is 0x00 - vendor unique parameters (not in SPC/SBC)
  * use definition from HGST SSD as a guide
   // +=====-=======-=======-=======-=======-=======-=======-=======-=======+
   // |  Bit|   7   |   6   |   5   |   4   |   3   |   2   |   1   |   0   |
   // |Byte |       |       |       |       |       |       |       |       |
   // |=====+=======================+=======================================|
   // | 0   | PS    |  0    |          Page Code (00h)                      |
   // |-----+---------------------------------------------------------------|
   // | 1   |                          Page Length (0Eh)                    |
   // |-----+---------------------------------------------------------------|
   // | 2   |                                                               |
   // |-----+---                     Reserved                            ---|
   // | 8   |                                                               |
   // |-----+---------------------------------------------------------------|
   // | 9   |                        Temperature Threshold (Celcius)        |
   // |-----+---------------------------------------------------------------|
   // | 10  |                                                               |
   // |-----+---                                                         ---|
   // | 15  |                        Reserved                               |  
   // |=====+===============================================================|        
  */
            
sntl_mode_select:
        /* set r30=list length */
        bsrli r30, r24, 24    /* r24 = CDB4-7 */
        bri sntl_mode_select_1
               
sntl_mode_select_10:
        andi  r30, r24, 0xff    /* r24 = CDB4-7 */
        bslli r30, r30, 8
        bsrli r12, r25, 24      /* r25 = CDB8-11 */
        or    r30, r30, r12
        
sntl_mode_select_1:        
        /* check list length > 0 */
        beqi  r30, sntl_sc_invalid
               
        /* check PF */
        andi  r12, r23, 0x00100000  /* r23 = CDB0-3 PF=byte1 bit 4*/
        bnei  r12, sntl_mode_select_2 /* PF=1b */ 
        bri   sntl_sc_invalid

sntl_mode_select_2:
        /* issue DMA request to host to get mode page data */        
        swi r30, r11, SNTL_SISL_LENGTH
        swi  r0, r11, SNTL_SISL_RELOFF
        lwi r12, r11, SNTL_SISL_CID
        ori r12, r12, 0x20000  /* bit 17 = send dma request */
        swi r12, r11, SNTL_SISL_CID

sntl_mode_select_poll:  
        lwi  r12, r11, SNTL_SISL_CID
        andi r12, r12, 0x10000  /* bit 16 = dma completed */
        beqi r12, sntl_mode_select_poll

        /* read byte 7 to get length of descriptor if any */
        /* then skip over it */
        lwi  r5, r11, SNTL_SISL_BUFFER+4
        bsrli r5, r5, 24  /* size of descriptors */
        addi r5, r5, 8    /* add 8 for header */
        add  r5, r5, r11  /* r5 = start of parameter data = IO base + offset into ADQ buffer */
        
        lwi  r12, r5, SNTL_SISL_BUFFER
        andi r12, r12, 0xff7F  /* check page length and page code */
        xori r12, r12, 0x0E00
        beqi r12, sntl_mode_select_00h
        /* return invalid field in parameter list if not page 00h with expected length */
        bri sntl_sc_invalid_param
        
sntl_mode_select_00h:           
        lwi   r12, r5, SNTL_SISL_BUFFER+8
        bsrli r12, r12, 8
        andi   r8, r12, 0xff  /* r8 = new temp threshold in celcius */
        addi   r8, r8, 273    /* convert to kelvin */

        andi r5, r27, 0x0FFF   /* cmd id */
        ori r6, r0, 0x04 /* feature id = temp threshold */
        ori r7, r0, 0x00 /* namespace id */
        /* r8 = parameter */ 
        brlid r15, admin_set_features
        nop        
            
        bri sntl_sc_success     

/*****************************************************************************
 * UNMAP - SBC-3 5.28
   // +=====-=======-=======-=======-=======-=======-=======-=======-=======+
   // |  Bit|   7   |   6   |   5   |   4   |   3   |   2   |   1   |   0   |
   // |Byte |       |       |       |       |       |       |       |       |
   // |=====+=======================+=======================================|
   // | 0   |                        Operation code (42h)                   |
   // |-----+---------------------------------------------------------------|
   // | 1   |  Reserved                                            |  ANC   |
   // |-----+---------------------------------------------------------------|
   // | 2   |                                                               |
   // |.....+---                     Reserved                            ---|
   // | 5   |                                                               |
   // |-----+---------------------------------------------------------------|
   // | 6   |  Reserved              |  Group Number                        |
   // |-----+---------------------------------------------------------------|
   // | 7   | (MSB)                  Parameter List Length                  |
   // |-----+------                                                 --------|
   // | 8   |                                                       (LSB)   |
   // |-----+---------------------------------------------------------------|
   // | 9   |                        Control                                |  
   // |=====+===============================================================|
 */     

 /*// +=====-=======-=======-=======-=======-=======-=======-=======-=======+
   // |  Bit|   7   |   6   |   5   |   4   |   3   |   2   |   1   |   0   |
   // |Byte |       |       |       |       |       |       |       |       |
   // |=====+=======================+=======================================|
   // | 0   | (MSB)                                                         |
   // |-----+-------         UNMAP DATA LENGTH (n-1)                --------|
   // | 1   |                                                       (LSB)   |
   // |-----+---------------------------------------------------------------|
   // | 2   | (MSB)                                                         |
   // |-----+-------    UNMAP BLOCK DESCRIPTOR DATA LENTH (n-7)     --------|
   // | 3   |                                                       (LSB)   |
   // |-----+---------------------------------------------------------------|
   // | 4   |                                                               |
   // |.....+------          Reserved                               --------|
   // | 7   |                                                               |
   // |-----+---------------------------------------------------------------|
   // |            UNMAP Block Descriptor list (if any)                     |
   // |-----+---------------------------------------------------------------|
   // | 8   |                UNMAP block descriptor (first)                 |
   // |.....+    8-15:  8B LBA                                              |
   // |     |    16-19: number of blocks                                    |
   // | 23  |    20-23: reserved
   // |-----+---------------------------------------------------------------|
   // |-----+---------------------------------------------------------------|
   // | n-15|                UNMAP block descriptor (last)                  |
   // |.....+                                                               |
   // | n   |                                                               |
   // |=====+===============================================================|
 */      

/*        
 * modifies: 
 *  r3-r7, r12, r28, r29, r30 - temp variables
 */
                   
sntl_unmap:
        UCODE_STATUS(0x31)
        UCODE_STATUS_SUB(0x61)
        /* set r30=list length */
        andi  r30, r24, 0xff    /* r24 = CDB4-7 */
        bslli r30, r30, 8
        bsrli r12, r25, 24      /* r25 = CDB8-11 */
        or    r30, r30, r12
     
        /* check list length > 0 */
        beqi  r30, sntl_sc_invalid

        /* check list length < 4096 */
        addi  r12, r30, -4096
        bgei  r12, sntl_sc_invalid
               
        /* check ANC */
        andi  r12, r23, 0x00010000  /* r23 = CDB0-3 ANC=byte1 bit 0*/
        beqi  r12, sntl_unmap_2 /* ANC=0b */ 
        bri   sntl_sc_invalid

sntl_unmap_2:
        /* issue DMA request to host to get mode page data */        
        swi r30, r11, SNTL_SISL_LENGTH
        swi  r0, r11, SNTL_SISL_RELOFF
        lwi r12, r11, SNTL_SISL_CID
        ori r12, r12, 0x20000  /* bit 17 = send dma request */
        swi r12, r11, SNTL_SISL_CID

sntl_unmap_poll:  
        lwi  r12, r11, SNTL_SISL_CID
        andi r12, r12, 0x10000  /* bit 16 = dma completed */
        beqi r12, sntl_unmap_poll

        
        UCODE_STATUS(0x32)
        /* get length fields from bytes 0-3 */        
        lwi   r29, r11, SNTL_SISL_BUFFER
        swapb r29, r29
        andi  r29, r29, 0xFFFF /* r29 = block descriptor data length */        
        beqi  r29, sntl_sc_invalid
        addi  r12, r29, -4089  /* check for more block descriptors than we have room for in 4KB */
        bgei  r12, sntl_sc_invalid
        
        UCODE_STATUS(0x33)
        lwi   r28, r11, SNTL_BLKSZ_TABLE /* r28 = blocksize (0x9=512B, 0xC=4KB) */
        
        or    r6, r11, r0 /* pointer into sisl & adq buffers */       
        or    r7, r0,  r0 /* bytes of parameter data consumed */

sntl_unmap_3:
        UCODE_STATUS(0x34)
           
        lwi   r3, r6, SNTL_SISL_BUFFER+8   /* lba MSB */
        swapb r3, r3
        lwi   r4, r6, SNTL_SISL_BUFFER+12  /* lba LSB */
        swapb r4, r4
        lwi   r5, r6, SNTL_SISL_BUFFER+16  /* number of 4K blocks */
        swapb r5, r5
        addi  r7, r7, 16

        xori r12, r28, 0x9
        bnei r12, sntl_unmap_4

        /* convert to 512B block LBA/NUMLBA - shift left by 3 = x8 */        
        bslli r3, r3, 3
        bsrli r12, r4, 29
        or    r3, r3, r12
        bslli r4, r4, 3
        bslli r5, r5, 3
        
sntl_unmap_4:
        swi   r0, r6, SNTL_ADQ_BUFFER+0  /* context attributes */
        /* addi  r5, r5, -1 */  /* length is not zero based for deallocate range */
        swi   r5, r6, SNTL_ADQ_BUFFER+4  /* length in logical blocks */
        swi   r4, r6, SNTL_ADQ_BUFFER+8  /* LSB starting LBA */
        swi   r3, r6, SNTL_ADQ_BUFFER+12

        addi  r6, r6, 16  /* 16 bytes per entry in both SCSI and NVMe formats */
        /* check if done */
        rsub  r12, r7, r29  /* (r29)block descriptor data length - (r7)current length */
        bgti  r12, sntl_unmap_3

        bsrli r29, r7, 4  /* divide by 16 == number of ranges */
        addi  r29, r29, -1 /* make 0 based */

        UCODE_STATUS(0x35)
  
        /* issue deallocate command in ISQ */
        /* parse LUNID => namespace id */
        or r5, r21, r0
        or r6, r22, r0
        brlid r15, lunid2nsid
        nop
        bnei r4, sntl_sc_lun_not_supported
        
        andi r5, r27, 0x0FFF   /* cmd id */
        ori  r6, r29, 0        /* number of ranges */
        or   r7, r0, r3        /* namespace id */
        brlid r15, admin_deallocate
        nop
        bnei  r3, sntl_sc_admin_error        
        bri sntl_sc_success     
                                      
                                          
/*****************************************************************************
   // LOG_SENSE
   // SCSI SPC-4 6.8         
   // +=====-=======-=======-=======-=======-=======-=======-=======-=======+
   // |  Bit|   7   |   6   |   5   |   4   |   3   |   2   |   1   |   0   |
   // |Byte |       |       |       |       |       |       |       |       |
   // |=====+=======================+=======================================|
   // | 0   |                        Operation code (4Dh)                   |
   // |-----+---------------------------------------------------------------|
   // | 1   |  Reserved                                     |obsolte|  SP   |
   // |-----+---------------------------------------------------------------|
   // | 2   |     PC        |        Page Code                              |
   // |-----+---------------------------------------------------------------|
   // | 3   |                        Subpage Code                           |
   // |-----+---------------------------------------------------------------|
   // | 4   |                        Reserved                               |
   // |-----+---------------------------------------------------------------|
   // | 5   | (MSB)                                                         |
   // |-----+---                     Parameter Pointer                   ---|
   // | 6   |                                                        (LSB)  |
   // |-----+---------------------------------------------------------------|
   // | 7   | (MSB)                                                         |
   // |-----+---                     Allocation Length                   ---|
   // | 8   |                                                        (LSB)  |
   // |-----+---------------------------------------------------------------|
   // | 9   |            control                                            |  
   // |=====+===============================================================|

        SP = 0 PC = 01 Page Codes: 0x00, 0x0D, 0x11, 0x2F, 0x19 are supported
        All others return invalid field in cdb
 */
        
sntl_log_sense: 

        swi r0, r11, SNTL_SISL_CLEAR  /* clear SISL (response) buffer */

        /* check PC */
        bsrli r29, r23, 14    /* r23 = CDB0-3 */
        andi  r29, r29, 0x03  /* r28 = PC = cdb byte 2 bits 7:6 */

        xori  r12, r29, 0x01  
        beqi  r12, sntl_log_sense_1 /* PC=01b */  
        bri   sntl_sc_invalid
       
sntl_log_sense_1:
        /* set r30 = allocation length */
        bsrli r30, r25, 24    /* CDB byte 8 = lsb of allocation length */
        andi  r12, r24, 0xff  /* CDB byte 7 = msb of allocation length */
        bslli r12, r12, 8
        or    r30, r30, r12   /* r30 == allocation length */

        /* check for SP = 0 */
        bsrli r29, r23, 16
        andi  r29, r29, 0x01
        beqi  r29, sntl_log_sense_page
        bri   sntl_sc_invalid
        
sntl_log_sense_page:
                        
        /* get page code from CDB bytes 2 */ 
        bsrli r28, r23, 8
        andi  r28, r28, 0x3F  /* r28 = page code */

        beqi r28, sntl_log_sense_00

        /* get the smart log page used by each page */
        andi r5, r27, 0x0FFF   /* cmd id */
        ori r6, r0, 47         /* number of dwords (0s based) = 192B/4-1 */
        ori r7, r0, 0xFFFFFFFF /* namespace id == global */
        ori r8, r0, 0x02       /* log page id = SMART/Health Info */
        brlid r15, admin_get_log
        nop
        bnei  r3, sntl_sc_admin_error

        /* set r29 = current temp */
        /* temp in Kelvin is bytes 2:1 of smart data - NVME 1.1b 5.10.1.2 */
        lwi   r12, r11, SNTL_ADQ_BUFFER
        bsrli r12, r12, 8
        andi  r12, r12, 0xffff
        addi  r29, r12, -273    /* convert to Celsius */
        bgti  r29, sntl_log_sense_temperature
        or    r29, r0, r0       /* set to 0 if negative according to SPC-4 */
sntl_log_sense_temperature:
        addi  r12, r29, -255
        blei  r12, sntl_log_sense_temperature_over
        ori   r29, r0, 0xff     /* max value = 255 C */
sntl_log_sense_temperature_over:                      

        /* set r28 = temperature threshold */
        andi r5, r27, 0x0FFF   /* cmd id */
        ori r6, r0, 0x04       /* feature id = 0x04 "Temperature Threshold" */
        ori r7, r0, 0x00       /* namespace id == reserved */
        ori r8, r0, 0x00       /* select = current  */     
        brlid r15, admin_get_features
        nop
        bnei  r3, sntl_sc_admin_error
               
        andi  r12, r5, 0xffff    /* r5 = completion dw0 == temp threshold */        
        addi  r28, r12, -273     /* convert to Celsius */
        bgti  r28, sntl_log_sense_tempthresh
        or    r28, r0, r0       /* set to 0 if negative according to SPC-4 */
sntl_log_sense_tempthresh:
        addi  r12, r28, -255
        blei  r12, sntl_log_sense_tempthresh_over
        ori   r28, r0, 0xff     /* max value = 255 C */
sntl_log_sense_tempthresh_over:
        
        bsrli r10, r23, 8
        andi  r10, r10, 0x3F  /* r10 = page code */        
        xori r12, r10, 0x0D
        beqi r12, sntl_log_sense_0D
        xori r12, r10, 0x11
        beqi r12, sntl_log_sense_11
        xori r12, r10, 0x2F
        beqi r12, sntl_log_sense_2F
        xori r12, r10, 0x19
        beqi r12, sntl_log_sense_19
        bri  sntl_sc_invalid
/*
   log sense payload data format
   // SPC-4 7.3.2.1
   // +=====-=======-=======-=======-=======-=======-=======-=======-=======+
   // |  Bit|   7   |   6   |   5   |   4   |   3   |   2   |   1   |   0   |
   // |Byte |       |       |       |       |       |       |       |       |
   // |=====+=======================+=======================================|
   // | 0   | DS    | SPF   |        Page Code                              |
   // |-----+---------------------------------------------------------------|
   // | 1   |                        Subpage Code                           |
   // |-----+---------------------------------------------------------------|
   // | 2   |  (MSB)                                                        |
   // |- - -+---                     Page Length (n-3)                   ---|
   // | 3   |                                                      (LSB)    |
   // |=====+===============================================================|
   // |     |                  Log Parameters                               |
   // |=====+===============================================================|
   // | 4   |                                                               |
   // |- - -+---               Log parameter (first)                     ---|
   // | x+3 |                                                               |
   // |-----+---------------------------------------------------------------|
   // |     |                                                               |
   // |-----+---------------------------------------------------------------|
   // |n-y+1|                                                               |
   // |- - -+---               Log parameter (last)                      ---|
   // | n   |                                                               |
   // |=====+===============================================================|

        Log parameter - SPC-4 7.3.2.2.1
   // +=====-=======-=======-=======-=======-=======-=======-=======-=======+
   // |  Bit|   7   |   6   |   5   |   4   |   3   |   2   |   1   |   0   |
   // |Byte |       |       |       |       |       |       |       |       |
   // |=====+=======================+=======================================|
   // | 0   | (MSB)                                                         |
   // |-----+---                     Parameter Code                      ---|
   // | 1   |                                                         (LSB) |
   // |-----+---------------------------------------------------------------|
   // | 2   |                        Parameter Control Byte                 |
   // |     |  DU   |  Obs  | TSD   |  ETC  |  TMC          | Format/Link   |
   // |-----+---------------------------------------------------------------|
   // | 3   |                        Parameter Length                       |
   // |-----+---------------------------------------------------------------|
   // | 4   | (MSB)                                                         |
   // |- - -+---                     Parameter Value                     ---|
   // | n   |                                                         (LSB) |
   // |=====+===============================================================|
*/        
sntl_log_sense_00:
        /* supported log page list - SNTL 6.2.1*/
        ori r12, r0, 0x05000000
        swi r12, r11, SNTL_SISL_BUFFER
        ori r12, r0, 0x2F110D00
        swi r12, r11, SNTL_SISL_BUFFER+4
        ori r12, r0, 0x00000019
        swi r12, r11, SNTL_SISL_BUFFER+8
        ori r12, r0, 12
        swi r12, r11, SNTL_SISL_LENGTH
        bri sntl_log_sense_length
        
sntl_log_sense_0D:
        /* temperature log page - SNTL 6.2.2 SPC-4 7.3.21 */
        ori r12, r0, 0x0C00000D
        swi r12, r11, SNTL_SISL_BUFFER

        /* first parameter - current temp */
        ori r12, r0, 0x02030000  /* length=2 format=3 (binary) code=0x0000 */
        swi r12, r11, SNTL_SISL_BUFFER+4

        bslli r12, r29, 8       /* move temp to byte 5 */
        
        /* second parameter starts at byte 6 - temperature threshold */
        ori   r12, r12, 0x01000000  /* parameter code = 0001h */
        swi   r12, r11, SNTL_SISL_BUFFER+8
      
        bslli r12, r28, 24      /* move temp threshold to byte 15  */
        ori   r12, r12, 0x00000203  /* length=2 format=3 (binary) */
        swi   r12, r11, SNTL_SISL_BUFFER+12

        ori r12, r0, 16
        swi r12, r11, SNTL_SISL_LENGTH
        bri sntl_log_sense_length
        
sntl_log_sense_11:
        /* solid state media log page - SNTL 6.2.3  SBC-3 6.4.6.2 */
        ori r12, r0, 0x08000011
        swi r12, r11, SNTL_SISL_BUFFER

        /* first parameter - percentage used */
        ori r12, r0, 0x04030100  /* length=4 format=3 (binary) code=0x0001 */
        swi r12, r11, SNTL_SISL_BUFFER+4

        /* byte 5 of the smart log == percentaged used */
        lwi   r12, r11, SNTL_ADQ_BUFFER+4
        andi  r12, r12, 0x00ff00
        bslli r12, r12, 16  /* move to byte 7 of the parameter */
        swi   r12, r11, SNTL_SISL_BUFFER+8
        
        ori r12, r0, 12
        swi r12, r11, SNTL_SISL_LENGTH
        bri sntl_log_sense_length

        
sntl_log_sense_2F:      
        /* information exceptions log page - SNTL 6.2.4 SPC-4 */
        /* for parameter > 0000 
         *  byte 4 = SMART parameter sense code
         *  byte 5 = SMART parameter sense qualifier 
         *  byte 6 = percentage of threshold
         *  byte 7 = trip (threshold exceeded)
         */       
        
        ori r12, r0, 0x2800002F 
        swi r12, r11, SNTL_SISL_BUFFER

        /* parameter 0000 - 8 bytes starting at offset 4 - current temp */
        ori r12, r0, 0x04230000  /* length=4 TSD=1 format=3 (binary) code=0x0000 */
        swi r12, r11, SNTL_SISL_BUFFER+4

        bslli r12, r28, 8      /* temp threshold */
        or    r12, r12, r29    /* current temp */
        bslli r12, r12, 16     /* r12 byte3=threshold byte2=temp */        
        swi r12, r11, SNTL_SISL_BUFFER+8

        /* parameter 0001 - 8 bytes - remaining reserve (spare) 1 */
        ori r12, r0, 0x04030100  /* length=4 format=3 (binary) code=0x0001 */
        swi r12, r11, SNTL_SISL_BUFFER+12

        /* reuse r29 for other parameters */
        lwi   r29, r11, SNTL_ADQ_BUFFER
        andi   r3, r29, 0x01      /* byte 0 bit 0 == "spare critical" */
        bslli  r3,  r3, 24        /* put in byte 7 */
        bsrli r12, r29,  8        /* available spare */
        andi  r12, r12, 0x00ff0000
        or     r3,  r3, r12       /* r3 byte 6 == available spare */
        ori    r3,  r3, 0x005d
        swi    r3, r11, SNTL_SISL_BUFFER+16
        
        /* parameter 0002 - 8 bytes - remaining reserve (spare) 2 */
        ori r12, r0, 0x04030200  /* length=4 format=3 (binary) code=0x0002 */
        swi r12, r11, SNTL_SISL_BUFFER+20
            
        andi   r3, r29, 0x04      /* byte 0 bit 2 == "reliability degraded" */
        bslli  r3,  r3, 22        /* put in byte 7 */
        bsrli r12, r29,  8        /* available spare */
        andi  r12, r12, 0x00ff0000
        or     r3,  r3, r12       /* r3 byte 6 == available spare */
        ori    r3,  r3, 0x005d
        swi    r3, r11, SNTL_SISL_BUFFER+24

        /* parameter 0003 - 8 bytes - volatile mem fail */
        ori r12, r0, 0x04030300  /* length=4 format=3 (binary) code=0x0003 */
        swi r12, r11, SNTL_SISL_BUFFER+28
            
        andi   r3, r29, 0x10      /* byte 0 bit 4 == "volatile mem fail" */
        bslli  r3,  r3, 20        /* put in byte 7 */
        beqi   r3, sntl_log_sense_2F_2
        ori    r3,  r3, 0x00640000
sntl_log_sense_2F_2:
        ori    r3,  r3, 0x005d
        swi    r3, r11, SNTL_SISL_BUFFER+32
        
        /* parameter 0004 - 8 bytes - wear indicator */
        ori r12, r0, 0x04030400  /* length=4 format=3 (binary) code=0x0004 */
        swi r12, r11, SNTL_SISL_BUFFER+36

        lwi    r3, r11, SNTL_ADQ_BUFFER+4
        bslli  r3,  r3, 8         /* byte 5 = percent used */
        andi   r3,  r3, 0x00ff    
        
        /* trip if read only or wear>=100 ?*/
        addi   r12, r3, -100
        bslli   r3, r3, 16
        blei   r12, sntl_log_sense_2F_3
        ori     r3, r3, 0x01000000
sntl_log_sense_2F_3:            
        andi   r12, r29, 0x08      /* byte 0 bit 3 == "read only" */
        bslli  r12, r12, 21        /* put in byte 7 */
        or      r3, r3, r12        
        ori    r3,  r3, 0x000B
        swi    r3, r11, SNTL_SISL_BUFFER+40   
                    
        ori r12, r0, 44
        swi r12, r11, SNTL_SISL_LENGTH
        bri sntl_log_sense_length

sntl_log_sense_19:      
        /* page 0x19 - general statistics and performance - SPC-4 */
       
        ori r12, r0, 0x5C000019     /* page length=x5C bytes  page code=x19 */
        swi r12, r11, SNTL_SISL_BUFFER
        ori r12, r0, 0x40020100     /* parameter=0001  length=0x40 */
        swi r12, r11, SNTL_SISL_BUFFER+4
         
        lwi r12, r11, SNTL_ADQ_BUFFER+64  /* reads LSB             */
        swapb r12, r12
        swi r12, r11, SNTL_SISL_BUFFER+12
        lwi r12, r11, SNTL_ADQ_BUFFER+68  /* reads MSB (truncated) */
        swapb r12, r12
        swi r12, r11, SNTL_SISL_BUFFER+8
        
        lwi r12, r11, SNTL_ADQ_BUFFER+80  /* writes LSB             */
        swapb r12, r12 
        swi r12, r11, SNTL_SISL_BUFFER+20
        lwi r12, r11, SNTL_ADQ_BUFFER+84  /* writes MSB (truncated) */
        swapb r12, r12
        swi r12, r11, SNTL_SISL_BUFFER+16
        
        /* bytes/blocks written */
        /* use NVMe value of in units of 512B*1000 */
        /* truncate to 8B value */
        lwi r12, r11, SNTL_ADQ_BUFFER+48
        swapb r12, r12
        swi r12, r11, SNTL_SISL_BUFFER+28
        lwi r12, r11, SNTL_ADQ_BUFFER+52
        swapb r12, r12
        swi r12, r11, SNTL_SISL_BUFFER+24
        
        /* bytes/blocks read */
        /* use NVMe value of in units of 512B*1000 */
        /* truncate to 8B value */
        lwi r12, r11, SNTL_ADQ_BUFFER+32
        swapb r12, r12
        swi r12, r11, SNTL_SISL_BUFFER+36
        lwi r12, r11, SNTL_ADQ_BUFFER+36
        swapb r12, r12
        swi r12, r11, SNTL_SISL_BUFFER+32

        /* parameter 2 & 3 - placeholders */
        ori r12, r0, 0x08020200
        swi r12, r11, SNTL_SISL_BUFFER+72
        ori r12, r0, 0x08030300
        swi r12, r11, SNTL_SISL_BUFFER+84

        ori r12, r0, 96
        swi r12, r11, SNTL_SISL_LENGTH
        bri sntl_log_sense_length

       
sntl_log_sense_length:            
        /* check allocation length vs length */
        lwi r12, r11, SNTL_SISL_LENGTH
        rsub r12, r30, r12  /* r12=length-allocation length */
        blei r12, sntl_log_sense_length_1
        swi r30, r11. SNTL_SISL_LENGTH  /* set length = allocation length */        
sntl_log_sense_length_1:            
        swi r0, r11, SNTL_SISL_PAYLOAD  /* send payload to host */
        bri sntl_sc_success                                        
                                
/*****************************************************************************
 * READ_CAPACITY(10)
 * cdb byte 9:    control
 * returns: 8 bytes = 4B last lba, 4B block length (bytes)     
 *
 * READ_CAPACITY(16)/SERVICE_ACTION_IN
 * cdb byte 1:  service action=0x10
 * cdb byte 10-13: allocation length
 * cdb byte 15:  control
 * returns: 32 bytes - 8B last lba, 4B block length + misc
 *                
 * on entry: 
 *  r11 = IO_BASE
 *  r19-r27 = command fields
 *  r28 = scsi opcode
 * modifies: 
 *  r3-r7, r12, r15, r28, r29, r30
 *
 * spec references: NVM Express SCSI Translation v1.5 6.4
 *                  SBC-3 5.15 & 5.16
 */
        
sntl_read_cap:
              
        swi r0, r11, SNTL_SISL_CLEAR  /* clear SISL (response) buffer */
        
        /* parse LUNID => namespace id */
        or r5, r21, r0
        or r6, r22, r0
        brlid r15, lunid2nsid
        nop
        bnei r4, sntl_sc_lun_not_supported
        
        andi r5, r27, 0x0FFF   /* cmd id */
        ori r6, r0, 0x00 /* identify namespace */
        or  r7, r0, r3   /* namespace id */
        brlid r15, admin_identify
        nop
        
        /* always report block size == 4096 */
        ori   r30, r0, 4096       
        swapb r30, r30      /* change bytes per block to big endian */
        
        brlid r15, sntl_get_ns_blocksize  /* reads SNTL_ADQ_BUFFER, returns r12=LBADS {r6,r5} = number of 4K blocks */
        nop
                              
        /* decrement number of blocks by 1 to get last LBA # */        
        addi  r5, r5, -1  /* carry clear only if r5=0 */ 
        addic r6, r6, -1  /* only decrement if r5 was 0 */
        swapb r5, r5      /* change last LBA to big endian */
        swapb r6, r6

        xori r28, r28, SCSI_SERVICE_ACTION_IN
        beqi r28, sntl_read_cap16
        /* else readcap10 */
        
        /* bytes 0-3 = big endian last LBA */
        beqi r6, sntl_read_cap10_1  
        ori  r5, r5, 0xFFFFFFFF            /* last LBA overflow */
sntl_read_cap10_1:       
        swi r5, r11, SNTL_SISL_BUFFER     /* write last lba */
        swi r30, r11, SNTL_SISL_BUFFER+4  /* write bytes per block */
        ori r12, r0, 8
        swi r12, r11, SNTL_SISL_LENGTH
        swi r0, r11, SNTL_SISL_PAYLOAD    /* send payload to host */
        bri sntl_sc_success
        
sntl_read_cap16:
        
        /* length is 32 bytes or allocation length, whichever is less */
                                          /* get allocation length from CDB bytes 10-13 */
        bslli  r4, r24, 16                /* r24  = CDB8-11.  move bytes 10-11 to msb of r4 */
        bsrli r29, r25, 16                /* r25  = CDB12-15. move bytes 12-13 to lsb of r29 */
        or     r4,  r4, r29               /* r4   = allocation length */
        rsubi r12,  r4, 32                /* r12=32-allocation length */
        blei  r12, sntl_read_cap16_1
        ori    r4,  r0, 32
sntl_read_cap16_1:      
        swi    r4, r11, SNTL_SISL_LENGTH
                     
        swi   r6, r11, SNTL_SISL_BUFFER    /* write last lba msb */
        swi   r5, r11, SNTL_SISL_BUFFER+4  /* write last lba lsb */     
        swi   r30, r11, SNTL_SISL_BUFFER+8 /* bytes per block */
        /* use zeros for other fields:
         * PROT_EN = 0    - no protection support
         * P_TYPE  = 000b - no protection support
         * LOGICAL BLOCKS PER PHYS EXPONENT = 0
         * P_I_EXPONENT = 0 - no protection support
         * TPE - thin provisioning
         * TPRZ - unmapped LBA bits
         * lowest aligned LBA = 0
         */
        /* set LBPME bit (byte 14 bit 7) for "resource provisioned" */
        ori r4, r0, 0x00800000
        swi r4, r11, SNTL_SISL_BUFFER+12  /* bytes 15-12 */
        
        swi r0, r11, SNTL_SISL_PAYLOAD  /* send payload to host */
        bri sntl_sc_success
        
sntl_read_cap_unsupp:
        bri sntl_sc_lun_not_supported

        
/*****************************************************************************/
sntl_get_ns_blocksize:
        /* block size = LBA Data Size of format pointed to by FLBAS field (byte 26) */
        /*            = 1 << (byte (130 + FLBAS[3:0]*4)) */
        lwi   r12, r11, SNTL_ADQ_BUFFER+24
     
        bsrli r12, r12, 16
        andi  r12, r12, 0x0F  /* r12 = FLBAS */
        bslli r12, r12, 2  /* r12 = FLBAS x 4 bytes per LBAFx entry */
        addik r12, r12, SNTL_ADQ_BUFFER+128  /* r12 = FLBASx4+128 -> pointer to current LBA format structure */
        lw    r12, r11, r12   /* r12 == LBA Format Data Structure - see NVME 1.1b 5.11 Figure 86 */
        andi  r6,  r12, 0xffff /* r6 = metadata size */
        bnei  r6, sntl_get_ns_blocksize_0  /* if metadata size is non-zero, return 0 for blocksize */
        bsrli r12, r12, 16
        andi  r12, r12, 0xff  /* r12 == LBADS */

        /* always report block size == 4096 and convert size to 4096 */        
        /* Namespace size NSZE = byte 7-0 (logical blocks) */
        lwi r5, r11, SNTL_ADQ_BUFFER   /* bytes 3-0 little endian */
        lwi r6, r11, SNTL_ADQ_BUFFER+4 /* bytes 7-4 little endian */
 
        xori r7, r12, 0x0C  /* 4096B=2^12 */
        beqi r7,  sntl_get_ns_blocksize_4k
        xori r7, r12, 0x09  /* 512B=2^9 */
        bnei r7, sntl_get_ns_blocksize_0

        /* divide NSZE by 8 for 4096B blocks */
        bslli r7, r6, 29
        bsrli r6, r6, 3
        bsrli r5, r5, 3
        or    r5, r5, r7
        
sntl_get_ns_blocksize_4k:          
        andi  r5, r5, 0xFFFFE000  /* round to 32mb boundary for virtual luns */      
        rtsd r15, 8               /* return r12=LBADS {r6,r5} = number of 4K blocks */
        nop

        /* namespace not usable - metadata non-zero or blocksize not 512B or 4096B */
sntl_get_ns_blocksize_0:
        or   r12, r0, r0
        or   r5, r0, r0
        or   r6, r0, r0
        rtsd r15, 8
        nop        

                
/*****************************************************************************
 * REPORT_LUNS
 * cdb byte 2:     select report
 * cdb bytes 6-9:  allocation length
 * cdb byte 11:    control
 *
 * on entry: 
 *  r11 = IO_BASE
 *  r19-r27 = command fields
 * modifies: 
 *  r3-r7, r12, r15, r28, r29, r30
 */
sntl_report_luns:
        swi r0, r11, SNTL_SISL_CLEAR  /* clear SISL (response) buffer */

        bsrli r28, r23, 8  /* CDB0-3 :   byte 2 = select report */
        andi r28, r28, 0xff  /* r28 = select report */

        /* check for select report = 0x00, 0x02, or (0x11 with lun==0)  */
        /* SNTL spec ays to return good status with empty list if select report doesn't match the above or 0x01, 0x10, 0x11 with lun!=0, 0x12 */
        beqi r28, sntl_report_luns_list
        xori r29, r28, 0x02
        beqi r29, sntl_report_luns_list
        
        xori r29, r28, 0x01
        beqi r29, sntl_report_luns_0
        xori r29, r28, 0x10
        beqi r29, sntl_report_luns_0
        xori r29, r28, 0x12
        beqi r29, sntl_report_luns_0
        xori r29, r28, 0x11
        bnei r29, sntl_report_luns_0        
        or   r29, r21, r22   /* check for lun=0 */        
        beqi r29, sntl_report_luns_list
        
sntl_report_luns_0:
        /* return empty lun list */        
        ori r12, r0, 8
        swi r12, r11, SNTL_SISL_LENGTH
        swi r0, r11, SNTL_SISL_PAYLOAD  /* send payload to host */
        bri sntl_sc_success
        
sntl_report_luns_list:
        /* return list of LUNs */

        /* identify command - get controller config - number of namespaces bytes 519:516*/
        andi r5, r27, 0x0FFF   /* cmd id */
        ori r6, r0, 0x01 /* identify controller */
        ori r7, r0, 0x00 /* namespace id 0 */
        brlid r15, admin_identify
        nop

        lwi r28, r11, SNTL_ADQ_BUFFER + 516 /* r28 = number of namespaces */

        /* workaround: force number of namespaces to 1 */
        /* sim and hw are inconsistent with namespace ids */
        ori r28, r0, 1
        
        /* payload length is 8B*number of namespaces + 8 */
        /* first namespace->lunid is at offset 8 */
        /* max payload: least of: 4KB, allocation length in CDB, or sislite length */
        /* max number of namespaces is then 512 if only 1 4KB buffer is used */
        
        ori r29, r0, 8 /* starting offset */
        ori r30, r0, 0 /* starting namespace id index */
        /* format namespace id as a hierarchical LUN id - see SAM-5 4.7 */
        /* use address method=0b00 bus id=0b000000 for namespace ids 0-255 - peripheral device addressing method */

sntl_report_luns_loop:
        andi r5, r27, 0x0FFF   /* cmd id */
        ori r6, r0, 0x00 /* identify namespace */
        lwi  r7, r30, IO_BASE | SNTL_NSID_TABLE  /* current namespace */
        xori r12, r7, 0xFFFFFFFF
        beqi r12, sntl_report_luns_done  /* nsid == 0xFFFFFFFF indicates end of NSID table */
        brlid r15, admin_identify
        nop

        /* bytes 15:8 = NCAP namespace capacity (logical blocks) */
        lwi r3, r11, SNTL_ADQ_BUFFER + 8
        lwi r4, r11, SNTL_ADQ_BUFFER + 12
        or  r4, r4, r3  /* just checking for non-zero NCAP */
        beqi r4, sntl_report_luns_nxt
        /* non-zero NCAP - write id to sislite buffer */

        andi r7, r30, 0x00ff  /* assume namespace id < 256 for now  */
        bslli r7, r7, 8       /* move id to byte 1 for periperal device addressing */
        swi r7, r29, (IO_BASE | SNTL_SISL_BUFFER)
        addik r29, r29, 8                 

sntl_report_luns_nxt:
        /* increment current namespace and check for end conditions */
        addik r30, r30, 1
        rsub r7, r30, r28 /* r7=NN-current nsid index */
        bgei r7, sntl_report_luns_done  /* current nsid index < NN ? */

        /* stop if at end of 4KB buffer or allocation length */
        /* get allocation length from CDB bytes 6-9 */
        bslli r30, r24, 16  /* r24 = CDB4-7.  move bytes 6&7 to msb of r30 */
        bsrli r12, r25, 16  /* r25 = CDB8-11.  move bytes 8&9 to lsb of r12 */
        or r30, r30, r12    /* r30 = allocation length */   
        
        rsubi r7, r29, 4096  /* r7=4096-buffer offset */
        blei  r7, sntl_report_luns_done
        rsub  r7, r29, r30   /* r7=allocation length-buffer offset */
        bgti  r7, sntl_report_luns_loop  /* next namespace */
                        
sntl_report_luns_done:  
        /* set lun list length based on number of namespaces, not actual payload */
        bslli r7, r28, 3  /* NN*8 */
        swapb r7, r7
        swi r7, r11, SNTL_SISL_BUFFER  /* bytes 0-3 = big endian number of LUNs */
        /* set length to send to sislite == payload length */
        swi r29, r11, SNTL_SISL_LENGTH
        
        swi r0, r11, SNTL_SISL_PAYLOAD /* send payload now */

        bri sntl_sc_success  /* send completion==success */
        
        
/*****************************************************************************
 * INQUIRY opcode
 * Pages supported: std, x00, x80, x83, xB0, xB1, xB2, xB3
 */
sntl_inquiry:     
        
        /* SW361286 - check LUNID for inquiry.  otherwise, scsi_scan gets confused */
        /* parse LUNID => namespace id */
        or r5, r21, r0
        or r6, r22, r0
        brlid r15, lunid2nsid
        nop
        bnei r4, sntl_sc_lun_not_supported
                                 
        swi r0, r11, SNTL_SISL_CLEAR /* clear the 4K SISL buffer to zeros */
        
        /* get allocation length from CDB bytes 3&4 */
        andi r30, r23, 0x00FF
        bslli r30, r30, 8   /* byte 3 -> r30[15:8] */
        bsrli r12, r24, 24  
        or r30, r30, r12    /* byte 4 -> r30[7:0] */

        /* parse CDB to determine which page was requested */
        /* CDB byte 1 bit 0 == EVPD */
        bsrli r28, r23, 16
  
        andi r28, r28, 0x01
        beqi r28, sntl_inquiry_std
        
                 
        /* EVPD=1 */
        /* byte 2 of CDB = page code */
        bsrli r28, r23, 8
        andi r28, r28, 0xFF
        beqi r28, sntl_inquiry_x00
        
        xori r12, r28, 0x80
        beqi r12, sntl_inquiry_x80
        xori r12, r28, 0x83
        beqi r12, sntl_inquiry_x83
        xori r12, r28, 0xB0
        beqi r12, sntl_inquiry_xB0
        xori r12, r28, 0xB1
        beqi r12, sntl_inquiry_xB1        
        xori r12, r28, 0xB2
        beqi r12, sntl_inquiry_xB2
        xori r12, r28, 0xB3
        beqi r12, sntl_inquiry_xB3
        
        /* unsupported page */
        bri sntl_sc_invalid
        
/*****************************************************************************/      
sntl_inquiry_std:
        /* standard inquiry page - see NVME-STR 6.1.1 and t10-SPC4 6.6.2 */
        /* payload is 36 bytes */
    
        /* some of the response data needs identify controller results */        
        andi r5, r27, 0x0FFF   /* cmd id */
        ori r6, r0, 0x01 /* identify controller */
        ori r7, r0, 0x00 /* namespace id 0 */
        brlid r15, admin_identify
        nop  

        /* fill in payload data */
        /* bytes 3-0: 0-peripheral qualifier/device type=0
         *            1-RMB/reserved = 0
         *            2-version=6 
         *            3-normaca=1 hisup=1 format=2 (SPC-4) */
        #ifdef NORMACA
        ori r12, r0, 0x32060000
        #else
        ori r12, r0, 0x12060000
        #endif
        
        swi r12, r11, SNTL_SISL_BUFFER

        /* bytes 7-4: 4-Additional length=0x1f (36 bytes total).  
         *            5-PROTECT=0  protection not enabled
         *            6-MULTIP=0 (could get this from Identify Controller)
         *            7-CMDQUE=1
         */           
        ori r12, r0, 0x0200001F
        swi r12, r11, SNTL_SISL_BUFFER | 0x4
        
        /* bytes 8-15 = T10 Vendor Id.  set to "NVMe    " */
        /* 6/2/2016 - change to "IBM     " based on discussion with Jim Allen */
        la  r6, r0, t10_vendor_id_string
        lwi r12, r6, 0x00
        swi r12, r11, SNTL_SISL_BUFFER | 0x8
        lwi r12, r6, 0x04
        swi r12, r11, SNTL_SISL_BUFFER | 0xc
               
        /* bytes 16-31 = Product ID -> copy from first 16B of Model Number at 63:24 */
        lwi r12, r11, SNTL_ADQ_BUFFER | 24
        swi r12, r11, SNTL_SISL_BUFFER | 16
        lwi r12, r11, SNTL_ADQ_BUFFER | 28
        swi r12, r11, SNTL_SISL_BUFFER | 20
        lwi r12, r11, SNTL_ADQ_BUFFER | 32
        swi r12, r11, SNTL_SISL_BUFFER | 24
        lwi r12, r11, SNTL_ADQ_BUFFER | 36
        swi r12, r11, SNTL_SISL_BUFFER | 28
        
        /* bytes 32-35 = product revision level - copy from last 4 non-space chars of Firmware Revision field at byte 64-71*/
        lwi r12, r11, SNTL_ADQ_BUFFER | 64
        lwi r13, r11, SNTL_ADQ_BUFFER | 68       
        swapb r13, r13  /* reorder bytes 68,69,70,71 */
        /* check if rightmost byte == space */
sntl_inquiry_std_spc0:   
        andi r6, r13,0xff
        xori r6, r6, 0x20
        bnei r6, sntl_inquiry_std_spc1  /* non-space found */
        /* shift space off the right */
        bsrli r13, r13, 8
        /* move next byte into r13 from r12 */
        andi r6, r12, 0xff000000
        bslli r12, r12, 8 /* move next byte into leftmost position */
        or r13, r13, r6
        bnei r13, sntl_inquiry_std_spc0
        /* fall through if r13=zero - no non-space value in FR field*/
                
sntl_inquiry_std_spc1:
        swapb r13, r13  /* put back in little endian order */
        swi r13, r11, SNTL_SISL_BUFFER | 32
       
        /* send payload to host */
        ori r31, r0, 36

sntl_inquiry_chk_alloc:
        /* r30 = allocation length */
        /* r31 = length */
        
        rsub r12, r31, r30
        bgei r12, sntl_inquiry_chk_alloc1
        or   r31, r30, r0  /* use allocation length */
sntl_inquiry_chk_alloc1:                
        swi r31, r11, SNTL_SISL_LENGTH
        swi  r0, r11, SNTL_SISL_PAYLOAD

        bri sntl_sc_success

/*****************************************************************************/      
sntl_inquiry_x00:
        /* page 00 - Supported VPD Pages */
        /* bytes 3-0: 0-peripheral qualifier/device type=0
         *            1-page code=00
         *            2-00
         *            3-number of pages (SPC-4) */
        ori r12, r0, 0x07000000
        swi r12, r11, SNTL_SISL_BUFFER

        /* bytes 4-n : list of pages supported */
        ori r12, r0, 0xB0838000
        swi r12, r11, SNTL_SISL_BUFFER | 4
        
        ori r12, r0, 0x00B3B2B1
        swi r12, r11, SNTL_SISL_BUFFER | 8

        /* send payload to host */
        ori r31, r0, 11       
        bri sntl_inquiry_chk_alloc

sntl_inquiry_x80:
        /* page x80 - unit serial number */

        /* identify command - get namespace info */
      
        /* parse LUNID => namespace id */
        or r5, r21, r0
        or r6, r22, r0
        brlid r15, lunid2nsid
        nop
        bnei r4, sntl_sc_lun_not_supported
 
        andi r5, r27, 0x0FFF   /* cmd id */
        ori r6, r0, 0x00 /* identify namespace */
        or  r7, r0, r3   /* namespace id */
        brlid r15, admin_identify
        nop

        /* bytes 3-0: 0-peripheral qualifier/device type=0
         *            1-page code=80
         *            2-msb page length
         *            3-lsb page length (SPC-4) */
        /* page length is either 40 or 20 bytes - set to 40 assuming NGUID will be used */
        ori r12, r0, 0x28008000
        swi r12, r11, SNTL_SISL_BUFFER
        ori r31, r0, 44
        
        /* fill in "_" char in template */
        ori r7, r0, '_'
        sbi r7, r0, inquiry_template+4
        sbi r7, r0, inquiry_template+9
        sbi r7, r0, inquiry_template+14
        sbi r7, r0, inquiry_template+19
        sbi r7, r0, inquiry_template+24
        sbi r7, r0, inquiry_template+29
        sbi r7, r0, inquiry_template+24
        ori r7, r0, '.'
        sbi r7, r0, inquiry_template+39
        
        /* EUI64 field - bytes 127:120 */
        /* NGUID field - bytes 119:104 - namespace globally unique id - not in 1.1b spec */
        /* use NGUID if it is non-zero (NVMe 1.2 feature) otherwise use EUI64 */
        lwi r7, r11, SNTL_ADQ_BUFFER | 104
        lwi r8, r11, SNTL_ADQ_BUFFER | 108
        lwi r9, r11, SNTL_ADQ_BUFFER | 112
        lwi r10, r11, SNTL_ADQ_BUFFER | 116
        swapb r7, r7
        swapb r8, r8
        swapb r9, r9
        swapb r10, r10
        or r12, r7, r8
        or r12, r12, r9
        or r12, r12, r10
        bnei r12, sntl_inquiry_x80_nguid  

        /* NGUID is zero.  check EUI64 */
        /* load EUI64 into r7-r10 - 8 bytes */
        or r7, r0, r0
        or r8, r0, r0
        lwi r10, r11, SNTL_ADQ_BUFFER | 120
        lwi r9, r11, SNTL_ADQ_BUFFER | 124
        swapb r10, r10
        swapb r9, r9
        or r12, r9, r10
        beqi r12, sntl_inquiry_x80_v10
        
        /* set page length to 20 for EUI64 */
        ori r12, r0, 0x14008000
        swi r12, r11, SNTL_SISL_BUFFER
        ori r31, r0, 24
        
        ori r12, r0, '.'
        sbi r12, r0, inquiry_template+19


sntl_inquiry_x80_nguid: 
        /* ASCII encoding of EUI64 or NGUID starts at byte 4 */
        /* first build the ascii string in local memory, then copy to SISL_BUFFER */
        /* r7-r10 are little endian.  start with msb=r10[31:24] */
        /* for now, just do this inline instead of a loop */
 
        bsrli r5, r10, 24
        brlid r15, sntl_byte2ascii
        nop
        sbi r4, r0, inquiry_template
        sbi r3, r0, inquiry_template+1
        
        bsrli r5, r10, 16
        brlid r15, sntl_byte2ascii
        nop
        sbi r4, r0, inquiry_template+2
        sbi r3, r0, inquiry_template+3
        
        bsrli r5, r10, 8
        brlid r15, sntl_byte2ascii
        nop
        sbi r4, r0, inquiry_template+5 /* skip _ char */
        sbi r3, r0, inquiry_template+6
        
        bsrli r5, r10, 0
        brlid r15, sntl_byte2ascii
        nop
        sbi r4, r0, inquiry_template+7 
        sbi r3, r0, inquiry_template+8

        bsrli r5, r9, 24
        brlid r15, sntl_byte2ascii
        nop
        sbi r4, r0, inquiry_template+10 /* skip _ char */
        sbi r3, r0, inquiry_template+11
        
        bsrli r5, r9, 16
        brlid r15, sntl_byte2ascii
        nop
        sbi r4, r0, inquiry_template+12
        sbi r3, r0, inquiry_template+13
        
        bsrli r5, r9, 8
        brlid r15, sntl_byte2ascii
        nop
        sbi r4, r0, inquiry_template+15 /* skip _ char */
        sbi r3, r0, inquiry_template+16
        
        bsrli r5, r9, 0
        brlid r15, sntl_byte2ascii
        nop
        sbi r4, r0, inquiry_template+17
        sbi r3, r0, inquiry_template+18

         
        bsrli r5, r8, 24
        brlid r15, sntl_byte2ascii
        nop
        sbi r4, r0, inquiry_template+20
        sbi r3, r0, inquiry_template+21
        
        bsrli r5, r8, 16
        brlid r15, sntl_byte2ascii
        nop
        sbi r4, r0, inquiry_template+22
        sbi r3, r0, inquiry_template+23
        
        bsrli r5, r8, 8
        brlid r15, sntl_byte2ascii
        nop
        sbi r4, r0, inquiry_template+25 /* skip _ char */
        sbi r3, r0, inquiry_template+26
        
        bsrli r5, r8, 0
        brlid r15, sntl_byte2ascii
        nop
        sbi r4, r0, inquiry_template+27 
        sbi r3, r0, inquiry_template+28

        bsrli r5, r7, 24
        brlid r15, sntl_byte2ascii
        nop
        sbi r4, r0, inquiry_template+30 /* skip _ char */
        sbi r3, r0, inquiry_template+31
        
        bsrli r5, r7, 16
        brlid r15, sntl_byte2ascii
        nop
        sbi r4, r0, inquiry_template+32
        sbi r3, r0, inquiry_template+33
        
        bsrli r5, r7, 8
        brlid r15, sntl_byte2ascii
        nop
        sbi r4, r0, inquiry_template+35 /* skip _ char */
        sbi r3, r0, inquiry_template+36
        
        bsrli r5, r7, 0
        brlid r15, sntl_byte2ascii
        nop
        sbi r4, r0, inquiry_template+37
        sbi r3, r0, inquiry_template+38
     
        /* copy 40 bytes from local memory */
        ori r5, r0, 40
        ori r6, r0, 4
sntl_inquiry_x80_copy:        
        rsub r5, r6, r5
        lwi r12, r5, inquiry_template   
        swi r12, r5, IO_BASE | SNTL_SISL_BUFFER | 4
        bnei r5, sntl_inquiry_x80_copy

        /* send payload to host */        
        bri sntl_inquiry_chk_alloc

        /* nvme v1.0 doesn't have EUI64 or NGUID.  use serial number + NSID instead */
        /* NVMe STR 1.5 6.1.3.1.3 */
        /* example:  "0123456789ABCDEF_00000001" */
sntl_inquiry_x80_v10:
        andi r5, r27, 0x0FFF   /* cmd id */
        ori  r6, r0, 0x01  /* identify controller */
        ori  r7, r0, 0x00  /* namespace id */
        brlid r15, admin_identify
        nop

        ori r12, r0, 0x1E008000
        swi r12, r11, SNTL_SISL_BUFFER
        ori r31, r0, 34

        /* copy serial number to buffer */
        lwi r12, r11, SNTL_ADQ_BUFFER  + 4
        swi r12, r11, SNTL_SISL_BUFFER + 4
        lwi r12, r11, SNTL_ADQ_BUFFER  + 8
        swi r12, r11, SNTL_SISL_BUFFER + 8
        lwi r12, r11, SNTL_ADQ_BUFFER  + 12
        swi r12, r11, SNTL_SISL_BUFFER + 12
        lwi r12, r11, SNTL_ADQ_BUFFER  + 16
        swi r12, r11, SNTL_SISL_BUFFER + 16
        lwi r12, r11, SNTL_ADQ_BUFFER  + 20
        swi r12, r11, SNTL_SISL_BUFFER + 20

        /* append "_00000001." */
        ori r12, r0, 0x3030305F /* "_000" */
        swi r12, r11, SNTL_SISL_BUFFER + 24
        ori r12, r0, 0x30303030
        swi r12, r11, SNTL_SISL_BUFFER + 28
        ori r12, r0, 0x00002E31
        swi r12, r11, SNTL_SISL_BUFFER + 32

        /* send payload to host */        
        bri sntl_inquiry_chk_alloc
        
        
sntl_inquiry_x83:
   /*
   // SCSI SPC-4 7.8.6
   // SCSI SPC-3 7.6.3
   //            SCSI-3 INQUIRY - Device Identification VPD Page (0x83)
   // +=====-=======-=======-=======-=======-=======-=======-=======-=======+
   // |  Bit|   7   |   6   |   5   |   4   |   3   |   2   |   1   |   0   |
   // |Byte |       |       |       |       |       |       |       |       |
   // |=====+=======================+=======================================|
   // | 0   | Peripheral qualifier  |           Peripheral device type      |
   // |-----+---------------------------------------------------------------|
   // | 1   |                  Page Code (83h)                              |
   // |-----+---------------------------------------------------------------|
   // | 2   |  (MSB)                                                        |
   // |- - -+---                     Page Length                         ---|
   // | 3   |                                                      (LSB)    |
   // |=====+===============================================================|
   // |     |                  Identifier descriptor list                   |
   // |=====+===============================================================|
   // | 4   |                                                               |
   // |- - -+---               Identification descriptor (first)         ---|
   // |     |                                                               |
   // |-----+---------------------------------------------------------------|
   // |     |                                                               |
   // |-----+---------------------------------------------------------------|
   // |     |                                                               |
   // |- - -+---               Identification descriptor (last)          ---|
   // | n   |                                                               |
   // |=====+===============================================================|

   //  descriptor format    
   // +=====-=======-=======-=======-=======-=======-=======-=======-=======+
   // |  Bit|   7   |   6   |   5   |   4   |   3   |   2   |   1   |   0   |
   // |Byte |       |       |       |       |       |       |       |       |
   // |=====+=======================+=======================================|
   // | 0   |  Protocol Indentifier |          Code Set                     |
   // |-----+---------------------------------------------------------------|
   // | 1   | PIV   | Resv  | Association   |    Identifier Type            |
   // |-----+---------------------------------------------------------------|
   // | 2   |                   Reserved                                    |
   // |- - -+---------------------------------------------------------------|
   // | 3   |                  Identifier Length (n-3)                      |
   // |- - -+---------------------------------------------------------------|
   // | 4   |                                                               |
   // |- - -+---               Identifier                                ---|
   // | n   |                                                               |
   // |=====+===============================================================|
   
*/

        /* if EUI64 field is non-zero: */     
        /* NAA IEEE Registered Extended - 4B + 16B */
        /* EUI-64 - 4B + 8B */

        /* if NGUID field is non-zero */
        /* EUI-64 - 4B + 16B */

        /* if EUI64 and NGUID are both zero, then NAA based on serial number */
        /* NAA IEEE Registered Extended - 4B + 16B */
       
        /* identify command - get namespace data */
      
        /* parse LUNID => namespace id */
        or r5, r21, r0
        or r6, r22, r0
        brlid r15, lunid2nsid
        nop
        bnei r4, sntl_sc_lun_not_supported
        
        andi r5, r27, 0x0FFF   /* cmd id */
        ori r6, r0, 0x00 /* identify namespace */
        or  r7, r0, r3   /* namespace id */
        brlid r15, admin_identify
        nop


        ori r31, r0, 0  /* starting page length */
        
        /* EUI64 field - bytes 127:120 */
        /* NGUID field - bytes 119:104 - namespace globally unique id - not in 1.1b spec */
        /* use NGUID if it is non-zero (NVMe 1.2 feature) otherwise use EUI64 */
        lwi r7, r11, SNTL_ADQ_BUFFER | 104  /* NGUID is big endian  */
        lwi r8, r11, SNTL_ADQ_BUFFER | 108
        lwi r9, r11, SNTL_ADQ_BUFFER | 112
        lwi r10, r11, SNTL_ADQ_BUFFER | 116 /* r10[31:24] = lsb */        
        or r12, r7, r8
        or r12, r12, r9
        or r12, r12, r10
        beqi r12, sntl_inquiry_x83_eui64
        
        /* NGUID is non-zero */
        /* EUI-64 based designator header - NVMe STR 1.5 6.1.4.5 */
        /* 0 = protocol id=0, code set = 1 */
        /* 1 = PIV=0, ASSOC=00, TYPE=2 */
        /* 2 = reserved */
        /* 3 = length = 16B for NGUID */
        ori r12, r0, 0x10000201
        swi r12, r11, SNTL_SISL_BUFFER | 4   /* 4 byte offset for page header */
        
        swi r7, r11, SNTL_SISL_BUFFER | 8   /* big endian binary data - msb goes in byte 4 */     
        swi r8, r11, SNTL_SISL_BUFFER | 12      
        swi r9, r11, SNTL_SISL_BUFFER | 16      
        swi r10, r11, SNTL_SISL_BUFFER | 20        
                     
        ori r31, r0, 20  /* 20B for NGUID based designator */  
        
        /* if eui64 is zero, use part of NGUID for NAA id - not in SNTL spec */
        lwi r5, r11, SNTL_ADQ_BUFFER | 120 /* r8[7:0] = msb */  
        lwi r6, r11, SNTL_ADQ_BUFFER | 124
        or    r12, r5, r6
        bnei  r12, sntl_inquiry_x83_eui64 /* use EUI64 for NAA field */

        /* load 100b of NGUID into r8,r7,r6,r5 for building NAA */
        /* bytes 104-111 = identifier extension */
        /* bytes 115-119 = vendor specific extension id */
        /* total of 104 bits - xor 2 nibbles to pack into 100b ? */
        
        /* 0 = protocol id=0, code set = 1 */
        /* 1 = PIV=0, ASSOC=00, TYPE=3 */
        /* 2 = reserved */
        /* 3 = length = 16B  */
        addik r6, r31, IO_BASE + SNTL_SISL_BUFFER + 4  /* r6 = start of this designator */
        addik r31, r31, 20                              /* 20B in this designator */
        ori r12, r0, 0x10000301
        swi r12, r6, 0

        swapb r7, r7
        swapb r8, r8
        swapb r9, r9
        swapb r10, r10
        /* [ 8B identifier extension ] [ company id ] [ 5B vendor specific extension] == [ r7 | r8 | r9 | r10 ] (16B, r7=msb) */
        /* want: 0x6 | company id | 7.5B identifier extention | 5B vendor specific ] == 0x6/r9[31:8]/r7[27:24] | r7[23:0]/r8[31:24] | r8[23:0]/r9[7:0] | r10 */
        
        /* 0x6/r9[31:8]/r7[27:24] */
        /* work in little endian, then swap */
        bsrli r5, r9, 8 
        ori   r5, r5, 0x06000000    /* 6 = NAA type */
        bslli r5, r5, 4
        bsrli r12, r7, 28
        or    r12, r12, r5
        bsrli r5,  r7, 24
        andi  r5, r5, 0x00F
        xor   r12, r12, r5
        swapb r12, r12
        swi   r12, r6, 4

        /* next 4 bytes =  r7[23:0]/r8[31:24] */
        bslli  r5, r7, 8
        bsrli r12, r8, 24
        or    r12, r12, r5
        swapb r12, r12
        swi   r12, r6, 8

        /* next 4 bytes =  r8[23:0]/r9[7:0] */
        bslli  r5, r8, 8
        andi  r12, r9, 0x0FF
        or    r12, r12, r5
        swapb r12, r12
        swi   r12, r6, 12

        swapb r10, r10
        swi   r10, r6, 16
        
        bri   sntl_inquiry_x83_end
                        
sntl_inquiry_x83_eui64:                 

        /* NAA IEEE Registered Extended ID field - NVMe STR 1.5 6.1.4.1 */

        /* load EUI64 into r7-r8 - 8 bytes (big endian) */
        lwi r8, r11, SNTL_ADQ_BUFFER | 120 /* r8[7:0] = msb */  
        lwi r7, r11, SNTL_ADQ_BUFFER | 124
        /* change to little endian */
        swapb r8, r8
        swapb r7, r7
        or    r12, r8, r7
        beqi  r12, sntl_inquiry_x83_serial  /* skip this designator since EUI64 is zero */
                
        /* 0 = protocol id=0, code set = 1 */
        /* 1 = PIV=0, ASSOC=00, TYPE=3 */
        /* 2 = reserved */
        /* 3 = length = 16B  */
        addik r9, r31, IO_BASE + SNTL_SISL_BUFFER + 4  /* r9 = start of this designator */
        addik r31, r31, 20                              /* 20B in this designator */
        ori r12, r0, 0x10000301
        swi r12, r9, 0

        /* next 4 bytes = 0x6 | 24b ieee oui | msb 4b of EUI64 */
        /* work in little endian, then swap */
        lwi   r10, r0, data_ieee_oui 
        ori   r10, r10, 0x06000000    /* 6 = NAA type */
        bslli r10, r10, 4
        bsrli r12, r8, 28
        or    r12, r12, r10
        swapb r12, r12
        swi   r12, r9, 4

        /* next 4 bytes = EUI64 bits 59:28 */
        bslli r10, r8, 4
        bsrli r12, r7, 28
        or    r12, r12, r10
        swapb r12, r12
        swi   r12, r9, 8

        /* next 4 bytes = EUI64 27:0 & 0 */
        bslli r12, r7, 4
        swapb r12, r12
        swi   r12, r9, 12
        
        /* next 4 bytes = 0 */         

        /* EUI-64 based designator header - NVMe STR 1.5 6.1.4.5 */
        addik r9, r31, IO_BASE + SNTL_SISL_BUFFER + 4  /* r9 = start of this designator */
        addik r31, r31, 12                             /* add 12B to the length for this descriptor */
        
        /* 0 = protocol id=0, code set = 1 */
        /* 1 = PIV=0, ASSOC=00, TYPE=2 */
        /* 2 = reserved */
        /* 3 = length = 8B for EUI64 */                
        ori r12, r0, 0x08000201
        swi r12, r9, 0

        /* load EUI64 8 bytes (big endian) */
        lwi   r8, r11, SNTL_ADQ_BUFFER | 120 /* r8[7:0] = msb */  
        lwi   r7, r11, SNTL_ADQ_BUFFER | 124
        swi   r8, r9, 4   /* big endian binary data - msb goes in byte 4 */
        swi   r7, r9, 8
        bri sntl_inquiry_x83_end
        
sntl_inquiry_x83_serial:
        /* both NGUI and EUI64 are zero - use serial number */
        /* NAA IEEE Registered Extended ID field - NVMe STR 1.5 6.1.4.1 */

        andi r5, r27, 0x0FFF   /* cmd id */
        ori  r6, r0, 0x01 /* identify controller */
        ori  r7, r0, 0x00   /* namespace id */
        brlid r15, admin_identify
        nop
        
        /* 0 = protocol id=0, code set = 1 */
        /* 1 = PIV=0, ASSOC=00, TYPE=3 */
        /* 2 = reserved */
        /* 3 = length = 16B  */
        addik r9, r31, IO_BASE + SNTL_SISL_BUFFER + 4  /* r9 = start of this designator */
        addik r31, r31, 20                              /* 20B in this designator */
        ori r12, r0, 0x10000301
        swi r12, r9, 0

        
       /* serial number is bytes 23:4 of admin identify controller.  oui is bytes 75-73  
        * 00000000: 8680 8680 5048 4d32 3734 3930 3031 4d32  ....PHM2749001M2
        * 00000010: 3238 3041 474e 2020 494e 5445 4c20 5353  280AGN  INTEL SS  
        * 00000040: 4532 3031 3033 3235 00e4 d25c 0005 0000  E2010325...\....
        */

        /* next 4 bytes = 0x6 | 24b ieee oui | nibble 0 of serial number */
        /* work in little endian, then swap */
        lwi   r10, r0, data_ieee_oui 
        ori   r10, r10, 0x06000000    /* 6 = NAA type */
        bslli r10, r10, 4

        /* get first 4b from serial number */
        lwi   r12, r11, SNTL_ADQ_BUFFER  + 4
        bsrli r12, r12, 28
        or    r12, r12, r10
        swapb r12, r12
        swi   r12, r9, 4

        /* next 32b from serial number */
        lwi    r12, r11, SNTL_ADQ_BUFFER  + 4
        bslli  r12, r12, 4
        lwi    r10, r11, SNTL_ADQ_BUFFER  + 8
        bsrli  r10, r10, 28
        or     r12, r12, r10
        swi    r12, r9,  8

        /* next 32b from serial number */
        lwi    r12, r11, SNTL_ADQ_BUFFER  + 8
        bslli  r12, r12, 4
        lwi    r10, r11, SNTL_ADQ_BUFFER  + 12
        bsrli  r10, r10, 28
        or     r12, r12, r10
        swi    r12, r9,  12
        
        /* next 32b from serial number */
        lwi    r12, r11, SNTL_ADQ_BUFFER  + 12
        bslli  r12, r12, 4
        lwi    r10, r11, SNTL_ADQ_BUFFER  + 16
        bsrli  r10, r10, 28
        or     r12, r12, r10
        swi    r12, r9,  16
        /* fall through to sntl_inquiry_x83_end */  

              
sntl_inquiry_x83_end:             
        /* page 0x83 header
         * bytes 3-0: 0-peripheral qualifier/device type=0
         *            1-page code=83
         *            2-msb page length
         *            3-lsb page length (SPC-4) */
        swapb r12, r31  /* length of descriptors -> page length */
        ori r12, r12, 0x00008300
        swi r12, r11, SNTL_SISL_BUFFER
        addik r31, r31, 4
                      
        /* send payload to host */        
        bri sntl_inquiry_chk_alloc
        
sntl_inquiry_xB0:
        /* block limits VPD - SBC-3 6.6.3 */

        /* identify command - get controller config for max transfer size param */
        andi r5, r27, 0x0FFF   /* cmd id */
        ori r6, r0, 0x01 /* identify controller */
        ori r7, r0, 0x00 /* namespace id 0 */
        brlid r15, admin_identify
        nop

        /* set max transfer size to lesser of:
         * - Id controller MDTS - Max Data Transfer Size (MDTS=byte 77.  max size = 2^MDTS * CAP.MPSMIN)
         *                        if MDTS=0, then no limit
         * - CAP.MPSMAX -> max page size is a design limit because we're only using 1 PRP
         * - 16M -> afu sislite length field size limit.  datalen_width=25.  2^25 = 32M-1
         */
        /* 10/3/2017 toddg: this no longer depends on MDTS or MPSMAX because all I/O to the NVMe device is 4KB
         *                  just set to 16MB
         */
        ori   r6, r0, 0x1000  /*  r6 = max transfer size in 4K blocks = 16MB */

        /* bytes 3-0: 0-peripheral qualifier/device type=0
         *            1-page code=B0
         *            2-msb page length
         *            3-lsb page length (SPC-4) */
        ori r12, r0, 0x3C00B000
        swi r12, r11, SNTL_SISL_BUFFER
        ori r31, r0, 64       

        /* byte 4:     reserved, WSNZ (write same non-zero)=1 (value of zero for write same logical blocks is not supported)  */
        /* byte 5:     max compare and write length == 0 because fused op not supported by samsung part */
        /* byte 6,7:   optimal transfer length granularity - not specified by SNTL - 0=no optimal length reported */
        ori r12, r0, 0x00000001
        swi r12, r11, SNTL_SISL_BUFFER + 4

        /* byte 8-11:  max transfer length - in logical blocks */
        swapb r6, r6
        swi r6, r11, SNTL_SISL_BUFFER + 8
        
        /* byte 12-15: optimal transfer length - not specified by SNTL - use 0 for not length reported*/
        /* byte 16-19: max prefetch length - not specified by SNTL - prefetch command not supported so use 0 */

        #ifdef UNMAP
        /* Dataset Management deallocate is supported by PM953.  */
        /* byte 20-23: max unmap lba count - 0 if Dataset Management Deallocate is not supported */
        ori r12, r0, 0xFFFFFFFF  /* no limit, but see next field */
        swi r12, r11, SNTL_SISL_BUFFER + 20
        /* byte 24-27: max unmap block descriptor count - 0 if Dataset Management Deallocate is not supported */
        ori r12, r0, 255  /* 255 descriptors fills up a 4KB buffer */
        swapb r12, r12
        swi r12, r11, SNTL_SISL_BUFFER + 24
        #endif
        
        /* byte 28-31: optimal unmap granularity - not specified by SNTL  */
        /* byte 32-35: UGAVALID bit, unmap granularity alignment - not specified by SNTL */
        
        /* byte 36-43: max write same length - not specified by SNTL - logical blocks.  0=no limit
         *             set to 16MB because write_same implementation uses same length fields as normal I/O
         */
        swi r6, r11, SNTL_SISL_BUFFER + 40
        /* byte 44-63: reserved */

        /* send payload to host */                 
        bri sntl_inquiry_chk_alloc

        
sntl_inquiry_xB1:
        /* Block device characteristics VPD page - SBC-3 6.6.2 */

        /* bytes 3-0: 0-peripheral qualifier/device type=0
         *            1-page code=B1
         *            2-msb page length
         *            3-lsb page length (SPC-4) */
        ori r12, r0, 0x3C00B100
        swi r12, r11, SNTL_SISL_BUFFER
        ori r31, r0, 64

        /* bytes 5-4: medium rotation rate = 0x0001 for non-rotating medium */
        /* bytes   6: product type = 0 (not specified) */
        /* bytes   7: WABEREQ|WACEREQ|Nominal form factor = 00 (not specified) | 00 (not specified) | 0h (not specified) */
        ori r12, r0, 0x00000100
        swi r12, r11, SNTL_SISL_BUFFER + 4
        
        /* bytes   8: reserved|FUAB|VBULS - FUAB relates to SYNCHRONIZE CACHE | VBULS - VERIFY or WRITE and VERIFY unmapped LBA handling */
        /* bytes 63-9: reserved */
        
        /* send payload to host */
        bri sntl_inquiry_chk_alloc
        
sntl_inquiry_xB2:
        /* Logical Block Provisioning VPD Page */
        /* modify if thin provisioning is supported */

        /* bytes 3-0: 0-peripheral qualifier/device type=0
         *            1-page code=B2
         *            2-msb page length
         *            3-lsb page length */
        ori r12, r0, 0x0400B200
        swi r12, r11, SNTL_SISL_BUFFER
        /* byte 7-4:  4 - threshold exponent=00 
         *            5 - LBPU|LBPWS|LBPWS10|2b resv|LBPRZ|ANC_SUP|DP
         *            6 - 5b resv|PROVISIONING_TYPE
         *            7 - reserved */
        ori r12, r0, 0x0000C000
        swi r12, r11, SNTL_SISL_BUFFER+4
        
        ori r31, r0, 8
        /* send payload to host */
        bri sntl_inquiry_chk_alloc
        
        
sntl_inquiry_xB3:
        /* Referrals VPD Page - SBC 6.6.5 */
                
        /* clear the 4K SISL buffer to zeros */
        swi r0, r11, SNTL_SISL_CLEAR

        /* bytes 3-0: 0-peripheral qualifier/device type=0
         *            1-page code=B3
         *            2-msb page length
         *            3-lsb page length (SPC-4) */
        ori r12, r0, 0x0C00B300
        swi r12, r11, SNTL_SISL_BUFFER
        ori r31, r0, 16

        /* bytes 11-8: user data segment size = 0 */
        /* bytes 12-15: user data segment multiplier = 0 */
        
        /* send payload to host */
        bri sntl_inquiry_chk_alloc    


sntl_format_unit:
   /*
   // SCSI SBC-3 5.3
   //            SCSI-3 FORMAT_UNIT
   // +=====-=======-=======-=======-=======-=======-=======-=======-=======+
   // |  Bit|   7   |   6   |   5   |   4   |   3   |   2   |   1   |   0   |
   // |Byte |       |       |       |       |       |       |       |       |
   // |=====+=======================+=======================================|
   // | 0   |        Operation code (04h)                                   |
   // |-----+---------------------------------------------------------------|
   // | 1   |  FMTPINFO     |LONGLST|FMTDATA| CMPLST| DEFECT LIST FORMAT    |
   // |-----+---------------------------------------------------------------|
   // | 2   |            vendor specific                                    |
   // |-----+---------------------------------------------------------------|
   // | 3   |                                                               |
   // |-----+---         obsolete                                        ---|
   // | 4   |                                                               |
   // |-----+---------------------------------------------------------------|
   // | 5   |            control                                            |  
   // |=====+===============================================================|
  */

        /* return CHECK_CONDITION, ILLEGAL REQUEST, ILLEGAL_FIELD_IN_CDB
           if attempting to format with protection information
        */
        andi r12, r23, 0x00C00000  /* cdb byte 1 */
        bnei r12, sntl_sc_invalid

        /* should check LONGLST|FMTDATA|CMPLST|DEFECT LIST FORMAT and
                 get data from host buffer here */
        
        /* parse LUNID => namespace id */
        or r5, r21, r0
        or r6, r22, r0
        brlid r15, lunid2nsid
        nop
        bnei r4, sntl_sc_lun_not_supported
        or r8, r0, r3  /* save namespace id for later */
        
        /* get namespace data structure to find allowable formats */
        andi r5, r27, 0x0FFF   /* cmd id */
        ori r6, r0, 0x00 /* identify namespace */
        or  r7, r0, r3   /* namespace id */
        brlid r15, admin_identify
        nop

        /* loop thru LBA format at offset 128 - 191 */
        /* select first LBA format that has "best" perf and 4KB or 512B with no metadata */
        lwi   r5, r11, SNTL_ADQ_BUFFER+24
        bsrli r5, r5, 8
        andi  r5, r5, 0xff /* r5 == number of LBA formats (NLBAF) */
        beqi  r5, sntl_sc_lun_not_supported
        
        or r6, r0, r0 /* start with LBAF==0 */
       
        
sntl_format_lbaf_best:               
        bslli r12, r6, 2  /* multiply r6 * 4 */
        addik r12, r12, SNTL_ADQ_BUFFER+128  /* r12 = 128+LBA format pointer */
        lw    r12, r11, r12   /* r12 == LBA Format Data Structure - see NVME 1.1b 5.11 Figure 86 */     
        xori  r7, r12, 0x090000  /* 31:24=0x00 -> "best performance" 23:16=9 for 512B data size.  15:0=0 for no metadata */
        beqi  r7, sntl_format_cmd
        xori  r7, r12, 0x0C0000  /* 31:24=0x00 -> "best performance" 23:16=C for 4KB data size.  15:0=0 for no metadata */
        beqi  r7, sntl_format_cmd
        addi  r6, r6, 1
        addi  r5, r5, -1
        bnei  r5, sntl_format_lbaf_best

        // didn't find a "best" perf.  accept anything with eith 4KB or 512B and no metadata
        lwi   r5, r11, SNTL_ADQ_BUFFER+24
        bsrli r5, r5, 8
        andi  r5, r5, 0xff /* r5 == number of LBA formats (NLBAF) */        
        or r6, r0, r0 /* start with LBAF==0 */

sntl_format_lbaf:               
        bslli r12, r6, 2  /* multiply r6 * 4 */
        addik r12, r12, SNTL_ADQ_BUFFER+128  /* r12 = 128+LBA format pointer */
        lw    r12, r11, r12   /* r12 == LBA Format Data Structure - see NVME 1.1b 5.11 Figure 86 */
        andi  r12, r12, 0x00ffffff  /* mask off relative performance field */
        xori  r7, r12, 0x090000  /*  23:16=9 for 512B data size.  15:0=0 for no metadata */
        beqi  r7, sntl_format_cmd
        xori  r7, r12, 0x0C0000  /* 23:16=C for 4KB data size.  15:0=0 for no metadata */
        beqi  r7, sntl_format_cmd
        addi  r6, r6, 1
        addi  r5, r5, -1
        bnei  r5, sntl_format_lbaf
        
        /* error - no valid format found */
        bri sntl_sc_lun_not_supported
       
        
sntl_format_cmd:
        /* r6 = LBAF */
        /* clear entry */
        ori r11, r0, IO_BASE        
        swi r0, r11, ASQ_CLEAR0
        swi r0, r11, ASQ_CLEAR1
        swi r0, r11, ASQ_CLEAR2
        swi r0, r11, ASQ_CLEAR3
        
        /* opcode = CMD[7:0] = 0x80                 */
        /* cmd id = CMD[31:16]                      */
        /* see NVMe 1.1b 5.13 */

        andi r5, r27, 0x0FFF   /* cmd id */
        bslli r12, r5, 16     /* move r5=cmd id 31:16 */
        ori r12, r12, 0x80    /* opcode */
        swi r12, r11, ASQ_CMD

        /* DW10 - 3:0 == LBA Format (LBAF) */
        /* all other fields are zero - no metadata, protection, security */
        swi r6, r11, ASQ_DW10      
        swi r8, r11, ASQ_NSID
    
        swi r0, r11, ASQ_INSERT       

        brlid r15, admin_cpl_poll2  /* wait for completion */
        nop
     
        /* r6 = dw3 (status) r5 = dw0 on exit */
        bsrli r12, r6, 17  /* dw3[31:17] == status */
        bnei r6, sntl_format_result

        /* update lunid table info */           
        andi r5, r27, 0x0FFF   /* cmd id */
        ori r6, r0, 0x00 /* identify namespace */
        ori r7, r8, 0x00
        brlid r15, admin_identify
        nop
        bnei r3, sntl_format_result
        
        brlid r15, sntl_get_ns_blocksize  /* reads SNTL_ADQ_BUFFER, returns r12=LBADS {r6,r5} = number of 4K blocks */
        nop
        /* note: doesn't handle multiple namespaces */
        swi r12, r11, SNTL_BLKSZ_TABLE
        swi r0, r11, SNTL_BLKSZ_TABLE+4 /* bit 0 of 2nd word = ACA status */
        swi r5, r11, SNTL_NSZE_TABLE
        swi r6, r11, SNTL_NSZE_TABLE+4
        ori r6, r0, 0x00  /* overall status */
        
sntl_format_result:             
        ori r12, r0, NVME_SC_VALID
        swi r12, r11, SNTL_STATUS0
        bri sntl_sc_poll             




sntl_write_buffer:
   /*
   // SCSI SPC-4 6.48, SNTL 4.12
   //            SCSI-4 WRITE_BUFFER
   // +=====-=======-=======-=======-=======-=======-=======-=======-=======+
   // |  Bit|   7   |   6   |   5   |   4   |   3   |   2   |   1   |   0   |
   // |Byte |       |       |       |       |       |       |       |       |
   // |=====+=======================+=======================================|
   // | 0   |        Operation code (3Bh)                                   |
   // |-----+---------------------------------------------------------------|
   // | 1   |  Mode Specific        |          Mode                         |
   // |-----+---------------------------------------------------------------|
   // | 2   |            buffer id                                          |
   // |-----+---------------------------------------------------------------|
   // | 3   | (msb)                                                         |
   // |-----+---         buffer offset                                      |
   // | 4   |                                                               |
   // |-----+                                                            ---|
   // | 5   |                                                        (lsb)  |
   // |-----+---------------------------------------------------------------|
   // | 6   | (msb)                                                         |
   // |-----+---         parameter list length                              |
   // | 7   |                                                               |
   // |-----+                                                            ---|
   // | 8   |                                                        (lsb)  |
   // |-----+---------------------------------------------------------------|
   // | 9   |            control                                            |  
   // |=====+===============================================================|
  */
             
        /* note: identify controller data structure    */
        /* byte 260 == Firmware Updates (FRMW)         */
        /*   bits 7:5 = reserved                       */
        /*   bit    4 = activate without reset         */
        /*   bits 3:1 = number of firmware slots       */
        /*   bit    0 = first slot (id 1) is read only */
        /* expected for Samsung PM953: 3 slots, slot 1 read only */
        
        /* note: get log page id 03h has firmware slot status */
        /* just pass fields through to NVMe controller and let it return appropriate status */

        
        /* translate parameter list length (bytes) in cdb bytes 6,7,8  to number of dwords (0s based) */
        /* r24 = cdb 4,5,6,7 r25 = cdb 8,9,10,11 */
        andi  r12, r24, 0xFFFF
        bslli r12, r12, 8
        bsrli  r5, r25, 24
        or    r12, r12, r5   /* r12 = parameter list length */
        andi   r5, r12, 0x3  /* save lower 2 bits */
        bsrli r12, r12, 2    /* divide by 4 to get dwords */
        bnei   r5, sntl_write_buffer_dword
        beqi  r12, sntl_write_buffer_dword
        addi  r12, r12, -1   /* decrement if non-zero and alligned on dword boundary */
sntl_write_buffer_dword:
        ori  r24, r12, 0  /* r24 = total NUMD */
        
        /* translate SCSI buffer offset in CDB 3,4,5 to NVMe offset */
        /* r23 = cdb 0,1,2,3 r24 = cdb 4,5,6,7 */
        bsrli r12, r24, 16
        andi   r5, r23, 0xff
        bslli  r5,  r5, 16
        or    r12, r12, r5
        bsrli r25, r12, 2  /* r25 = dword offset */
        ori   r26, r0, 0 /* byte offset in host buffer */

sntl_write_buffer_4k:        
       
        /* clear ASQ entry */
        ori r11, r0, IO_BASE        
        swi r0, r11, ASQ_CLEAR0
        swi r0, r11, ASQ_CLEAR1
        swi r0, r11, ASQ_CLEAR2
        swi r0, r11, ASQ_CLEAR3
        
        /* opcode = CMD[7:0] = 0x11 firmware image download */
        /* cmd id = CMD[31:16]                      */
        /* see NVMe 1.1b 5.8 */
  
        bslli r12, r27, 16     /* move r27=cmd id 31:16 */
        ori r12, r12, 0x11     /* opcode */
        swi r12, r11, ASQ_CMD

        /* PRP1 = sislite host buffer */
        /* { zero[63:52], ENUM_ADDR_SISL, sntl_ioq_req_cmdid[cid_width-1:0], zero[3:0], offset[27:0] }; */       
        ori r12, r26, NVME_SISL_BASE0
        swi r12, r11, ASQ_PRP10
                
        andi r12, r27, 0xFFFF /* put cmdid in bits 47:32 of address */
        ori  r12, r12, NVME_SISL_BASE1
        swi r12, r11, ASQ_PRP11


        swi  r24, r11, ASQ_DW10 /* DW10 = NUMD */              
        addi r12, r24, -1023    /* test for NUMD > 4K (min page size) */
        blei r12, sntl_write_buffer_offset
        ori  r12, r0, 1023
        swi  r12, r11, ASQ_DW10 
sntl_write_buffer_offset: 
        swi  r25, r11, ASQ_DW11 /* DW11 = NVMe offset */
        addi r24, r24, -1024
        addi r25, r25, 1024
        addi r26, r26, 4096

        /* mode 05h - download microcode, save, and activate */
        /* mode 07h - download microcode with offsets, save, and activate (return error: can't assume what last offset is?) */
        /* mode 0Eh - download microcode with offsets, save, and defer activate */
        /* mode 0Fh - activate deferred microcode */
        /* other modes - return ILLEGAL FIELD in CDB */
        
        bsrli r5, r23, 16
        andi  r5,  r5, 0x1F  /* r12 = Mode */
        xori  r12, r5, 0x05
        beqi  r12, sntl_write_buffer_5
        xori  r12, r5, 0x07
        beqi  r12, sntl_sc_invalid
        xori  r12, r5, 0x0E
        beqi  r12, sntl_write_buffer_E
        xori  r12, r5, 0x0F
        beqi  r12, sntl_write_buffer_F
        bri   sntl_sc_invalid

         

sntl_write_buffer_5:    
          
        swi r0, r11, ASQ_INSERT       
        brlid r15, admin_cpl_poll2  /* wait for completion */
        nop

        /* if successful, then active */
        /* r6 = dw3 (status) r5 = dw0 on exit */
        bsrli r12, r6, 17  /* dw3[31:17] == status */
        bnei  r12, sntl_write_buffer_status
        bgei  r24, sntl_write_buffer_4k  /* next 4K */
        bri   sntl_write_buffer_activate
        
sntl_write_buffer_E:
        swi r0, r11, ASQ_INSERT        
        brlid r15, admin_cpl_poll2  /* wait for completion */
        nop
        bsrli r12, r6, 17  /* dw3[31:17] == status */
        bnei  r12, sntl_write_buffer_status /* error status? */
        bgei  r24, sntl_write_buffer_4k  /* next 4K */
        bri   sntl_write_buffer_status /* done - good status */       
        
sntl_write_buffer_F:
sntl_write_buffer_activate:
        
        /* change opcode to firmware activate */
        /* opcode = CMD[7:0] = 0x10 firmware image activate/commit */
        /* cmd id = CMD[31:16]                      */
        /* see NVMe 1.1b 5.7 */
           
        bslli r12, r27, 16     /* move r27=cmd id 31:16 */
        ori r12, r12, 0x10     /* opcode */
        swi r12, r11, ASQ_CMD
        
        swi r0, r11, ASQ_PRP10
        swi r0, r11, ASQ_PRP11
        swi r0, r11, ASQ_DW11

        /* DW10 5:3 = commit action */
        /* use commit action == 01b - downloaded image replaces image in slot.*/
        /* image is activated at the next reset */
        /* DW10 2:0 = firmware slot */
        bsrli r5, r23, 8
        andi  r5, r5, 0xff  /* cdb byte 2 = buffer id */
        andi  r12, r5, 0x78 /* check for buffer id > 7 */
        bnei  r12, sntl_sc_invalid
        ori   r6, r0, 8  /* commit action */
        andi  r12, r5, 0x80 /* if msb of buffer id is set, use commit action = 2 = active firmware slot (no downloaded image) */
        beqi  r12, sntl_write_buffer_activate_2
        ori   r6, r0, 0x10 /* commit action = 2 */
sntl_write_buffer_activate_2:   
        andi  r12, r5, 0x7
        or    r12, r12, r6
        swi r12, r11, ASQ_DW10
        
        swi r0, r11, ASQ_INSERT        
        brlid r15, admin_cpl_poll2  /* wait for completion */
        nop

sntl_write_buffer_status:              
        /* r6 = dw3 (status) r5 = dw0 on exit */
        bsrli r12, r6, 17  /* dw3[31:17] == status */
        swi r12, r11, SNTL_STATUS0

        brlid r16, nvme_firmware_status
        nop

        lwi r12, r11, SNTL_STATUS0
        ori r12, r12, NVME_SC_VALID
        swi r12, r11, SNTL_STATUS0
        
        bri sntl_sc_poll             

        
/******************************************************************************
 *
 * subroutines: 
 * inputs: r5-r10
 * results: r3,r4
 * r11, r12 - temp variables
 * return address: r15
 */
/******************************************************************************/      
sntl_byte2ascii:
/* convert one byte to two ascii chars */
        /* r5 = input byte */
        /* r3 = result byte 0 - lower nibble */
        /* r4 = result byte 1 - upper nibble */
        andi r3, r5, 0xf
        rsubi r12, r3, 10  /* r12=(10-r3) so will be r12>0 if r3<10 */        
        ori r3, r3, 0x30  /* convert 0-9 to ascii 0-9 0x30-0x39 */
        bgti r12, sntl_byte2ascii_r4 
        addi r3, r3, 0x07 /* r3>=10 so convert to ascii A-F 0x41-0x46 */
        
sntl_byte2ascii_r4:      
        andi r4, r5, 0xf0
        bsrli r4, r4, 4
        rsubi r12, r4, 10
        ori r4, r4, 0x30
        bgti r12, sntl_byte2ascii_end
        addi r4, r4, 0x07
        
sntl_byte2ascii_end:
        rtsd r15, 8
        nop

/******************************************************************************/      
lunid2nsid:
/* convert 64b SCSI lunid to 32b namespace id */
/* input: r5 = lunid bytes 0-3  (big endian msb = byte 0)
/*        r6 = lunid bytes 4-7
/* output r3 = namespace id */
/*        r4 = non-zero on error */
        
/* inquiry data has HiSUP set, so lunids are hierarchical - see SAM-5 4.7 */
/* report_luns only uses address method 0b00 and 0b01 */
/* address method=0b00 bus id=0b000000 for namespace ids 1-255 - peripheral device addressing method */
/* address method=0b01 for namespace ids 256-16383 (0x3FFF) - flat space address method */
        bsrli r3,  r5, 16      /* r3  == LUN byte 0 & 1 */
        andi  r3,  r3, 0x3FFF  /* r3  == namespace id = lun byte 0 bits 5:0 & byte 1 */
        andi  r4,  r5, 0xFFFF  
        or    r4,  r4, r6      /* r4  == 0 if bytes 2-7 are zero */
        bsrli r12, r5, 24      /* r12 == lun byte 0 */
        bnei  r12, lunid2nsid_1
        /* byte 0 is zero = address method 0b00 - return r3=namespace id*/
        /* use r3 as index into table */
        lwi r3, r3, IO_BASE | SNTL_NSID_TABLE        
        rtsd  r15, 8
        nop
        
lunid2nsid_1: /* r12=lun byte 0 is non-zero */
        andi r12, r12, 0xc0  /* address method=bits 7:6 */
        xori r12, r12, 0x40  /* check for address method = 0b01 */
        or   r4, r4, r12     /* if address method != 0b01, set r4 to non-zero to indicate error */
        /* use r3 as index into table */
        lwi r3, r3, IO_BASE | SNTL_NSID_TABLE        
        rtsd r15, 8          /* return r3=namespace id */
        nop  

/******************************************************************************/        
/* Admin commands to NVMe controller                                          */
/* input parameters: r5,r6,r7            (may be modified)                    */
/* outputs:          r3 = completion DW0                                      */
/*                   r4 = completion DW3 (status/phase/command id)            */
/* r12 is overwritten                                                         */
/* r11 is set to IO_BASE                                                      */
/******************************************************************************/      
admin_identify:
/* issue NVMe Identify commands to Admin Queue */
/* payload data is returned to internal admin buffer */
        
        /* r5 = command id
         * r6 = "Controller or Namespace Structure" (CNS)
         *      0x01 = controller
         *      0x00 = namespace
         *      0x02 = namespace list
         * r7 = NSID  (namespace id)
         */
        
        /*
         * as long as there's only 1 admin command outstanding
         * the queue cannot be full
         */

        /* clear entry */
        ori r11, r0, IO_BASE        
        swi r0, r11, ASQ_CLEAR0
        swi r0, r11, ASQ_CLEAR1
        swi r0, r11, ASQ_CLEAR2
        swi r0, r11, ASQ_CLEAR3
        
        /* opcode = CMD[7:0] = 0x06                 */
        /* cmd id = CMD[31:16]                      */
        /* PRP1 = internal buffer (4K returned)     */
        /* DW10 = 0x0000001 for identify controller */
        /* see NVMe 1.1b 5.11                       */
        
        bslli r12, r5, 16    /* move r5=cmd id 31:16 */
        ori r12, r12, 0x06    /* opcode */
        swi r12, r11, ASQ_CMD
       
        swi r6, r11, ASQ_DW10
        swi r7, r11, ASQ_NSID
        
        ori r12, r0, NVME_ADMINRD_BASE0
        swi r12, r11, ASQ_PRP10
        
        ori r12, r0, NVME_ADMINRD_BASE1
        swi r12, r11, ASQ_PRP11

        swi r0, r11, ASQ_INSERT       
   
        /* identify controller results: post these to status registers or use sislite NVMe command? */
        /*    23:4  Serial Number */
        /*   63:24  Model Number */
        /*   71:64  Firmware revision */
        /*   75:73  IEEE OUI */
        /*      77  Max Data Transfer Size */
        /*          controller id */
        /*     512  submission queue entry size max/min - SQES (max should be >= 6, min=6) */
        /*     513  completion queue entry size max/min - CQES (max should  be >= 4, min=4) */
        /* 519:516  number of namespaces */
        /* misc other stuff - power state, etc */

        /* save opcode & param for override */
        ori  r3, r0, 0x06   /* opcode */
        or   r4, r0, r6     /* param  */
        bri admin_cpl_poll  /* wait for completion */

/******************************************************************************/      

admin_passthru:
/* issue NVMe Identify commands to Admin Queue */
/* payload data is returned to internal admin buffer */
        
        /* r5 = command id
         * r6 = opcode
         * r7 = NSID  (namespace id)
         * r8 = DW10
         * r9 = DW11
         */
        
        /* 
         * as long as there's only 1 admin command outstanding
         * the queue cannot be full
         */

        /* clear entry */
        ori r11, r0, IO_BASE        
        swi r0, r11, ASQ_CLEAR0
        swi r0, r11, ASQ_CLEAR1
        swi r0, r11, ASQ_CLEAR2
        swi r0, r11, ASQ_CLEAR3
        
        /* opcode = CMD[7:0]                        */
        /* cmd id = CMD[31:16]                      */
        /* PRP1 = host buffer (4K returned)         */

        bslli r12, r12, 16      /* move r5=cmd id 31:16 */
        or    r12, r12, r6      /* opcode */
        swi r12, r11, ASQ_CMD
       
        swi r8, r11, ASQ_DW10
        swi r9, r11, ASQ_DW11
        swi r7, r11, ASQ_NSID

       /* { zero[63:52], ENUM_ADDR_SISL, sntl_ioq_req_cmdid[cid_width-1:0], zero[3:0], zero[27:0] }; */
        
        ori r12, r0, NVME_SISL_BASE0
        swi r12, r11, ASQ_PRP10
        
        andi r12, r5, 0xFFFF /* put cmdid in bits 47:32 of address */
        ori  r12, r12, NVME_SISL_BASE1
        swi r12, r11, ASQ_PRP11

        swi r0, r11, ASQ_INSERT
        
        bri admin_cpl_poll2  /* wait for completion */          
        
/******************************************************************************/      
admin_set_features: 

        /* r5 = command id
         * r6 = feature id
         *      0x07 = number of I/O queues
         * r7 = NSID
         * r8 = parameter
         *
         * namespace 0 is used
         */
        
        /*
         * as long as there's only 1 admin command outstanding
         * the queue cannot be full
         */
        
        /* clear entry */
        ori r11, r0, IO_BASE        
        swi r0, r11, ASQ_CLEAR0
        swi r0, r11, ASQ_CLEAR1
        swi r0, r11, ASQ_CLEAR2
        swi r0, r11, ASQ_CLEAR3
        
        /* opcode = CMD[7:0] = 0x09          */
        /* cmd id = CMD[31:16]               */
        /* PRP1 = don't care - no payload    */
        /* DW10 = feature id                 */
        /* DW11 = parameter                  */
        /* see NVMe 1.1b 5.12                */
        
        bslli r12, r5, 16    /* move r5=cmd id 31:16 */
        ori r12, r12, 0x09    /* opcode */
        swi r12, r11, ASQ_CMD
        swi r7, r11, ASQ_NSID
        
        swi r6, r11, ASQ_DW10
        swi r8, r11, ASQ_DW11
        
        swi r0, r11, ASQ_INSERT        

        /* save opcode & param for override */
        ori  r3, r0, 0x09   /* opcode */
        or   r4, r0, r6     /* param  */
        bri admin_cpl_poll  /* wait for completion */

/******************************************************************************/      
admin_get_features: 

        /* r5 = command id
         * r6 = feature id        
         *           0x07 = number of I/O queues
         * r7 = NSID
         * r8 = select
         */
        
        /* 
         * as long as there's only 1 admin command outstanding
         * the queue cannot be full
         */
        
        /* clear entry */
        ori r11, r0, IO_BASE        
        swi r0, r11, ASQ_CLEAR0
        swi r0, r11, ASQ_CLEAR1
        swi r0, r11, ASQ_CLEAR2
        swi r0, r11, ASQ_CLEAR3
        
        /* opcode = CMD[7:0] = 0x0A          */
        /* cmd id = CMD[31:16]               */
        /* PRP1 = internal buffer            */
        /* DW10 = select & feature id        */
        /* see NVMe 1.1b 5.9                 */

        bslli r12, r5, 16    /* move r5=cmd id 31:16 */
        ori r12, r12, 0x0A    /* opcode */
        swi r12, r11, ASQ_CMD

        swi r7, r11, ASQ_NSID

        bslli r12, r8, 8
        or    r12, r12, r6
        swi   r12, r11, ASQ_DW10

        ori r12, r0, NVME_ADMINRD_BASE0
        swi r12, r11, ASQ_PRP10
        
        ori r12, r0, NVME_ADMINRD_BASE1
        swi r12, r11, ASQ_PRP11
                
        swi r0, r11, ASQ_INSERT        
 
        /* save opcode & param for override */
        ori  r3, r0, 0x0A   /* opcode */
        or   r4, r0, r6     /* param  */
        bri admin_cpl_poll  /* wait for completion */                  
/******************************************************************************/      
admin_get_log: 

        /* r5 = command id
         * r6 = number of dwords
         * r7 = NSID
         * r8 = log page id
         */
        
        /*
         * as long as there's only 1 admin command outstanding
         * the queue cannot be full
         */
        
        /* clear entry */
        ori r11, r0, IO_BASE        
        swi r0, r11, ASQ_CLEAR0
        swi r0, r11, ASQ_CLEAR1
        swi r0, r11, ASQ_CLEAR2
        swi r0, r11, ASQ_CLEAR3
        
        /* opcode = CMD[7:0] = 0x02          */
        /* cmd id = CMD[31:16]               */
        /* PRP1 = internal buffer            */
        /* DW10 = 27:16 number of dwords     */
        /*          7:0 log page id          */
        /* see NVMe 1.1b 5.10                */
        
        bslli r12, r5, 16    /* move r5=cmd id 31:16 */
        ori r12, r12, 0x02    /* opcode */
        swi r12, r11, ASQ_CMD

        bslli r12, r6, 16
        or    r12, r12, r8
        swi   r12, r11, ASQ_DW10

        swi   r7, r11, ASQ_NSID
        
        ori r12, r0, NVME_ADMINRD_BASE0
        swi r12, r11, ASQ_PRP10
        
        ori r12, r0, NVME_ADMINRD_BASE1
        swi r12, r11, ASQ_PRP11                
        
        swi r0, r11, ASQ_INSERT        

        /* save opcode & param for override */
        ori  r3, r0, 0x02   /* opcode */
        or   r4, r0, r8     /* param  */
        bri admin_cpl_poll  /* wait for completion */
        
/******************************************************************************/      
admin_create_icq: 

        /* r5 = command id     
         * r6 = msb base address (PRP10)
         * r7 = lsb base address (PRP11)
         * r8 = queue id
         * r9 = queue entries
         */
        
        /* 
         * as long as there's only 1 admin command outstanding
         * the queue cannot be full
         */

        /* clear entry */
        ori r11, r0, IO_BASE        
        swi r0, r11, ASQ_CLEAR0
        swi r0, r11, ASQ_CLEAR1
        swi r0, r11, ASQ_CLEAR2
        swi r0, r11, ASQ_CLEAR3
        
        /* opcode = CMD[7:0] = 0x05          */
        /* cmd id = CMD[31:16]               */
        /* PRP1 = I/O Queue address          */
        /* DW10 = QUEUE SIZE/QUEUE ID(=1)    */
        /* DW11 = interrupt settings, physically contiguous  */
        /* see NVMe 1.1b 5.4                 */
        
        bslli r12, r5, 16    /* move r5=cmd id 31:16 */
        ori r12, r12, 0x05    /* opcode */
        swi r12, r11, ASQ_CMD

        bslli r12, r9, 16
        or  r12, r12, r8      
        swi r12, r11, ASQ_DW10
        ori r12, r0,  0x01
        swi r12, r11, ASQ_DW11
                
        swi r6, r11, ASQ_PRP10
        swi r7, r11, ASQ_PRP11
        
        swi r0, r11, ASQ_INSERT        

        /* save opcode & param for override */
        ori  r3, r0, 0x05   /* opcode */
        or   r4, r0, r0     /* param  */
        bri admin_cpl_poll  /* wait for completion */          
/******************************************************************************/      
admin_delete_icq: 

        /* r5 = command id     
         * r8 = queue id 
         */
        
        /* clear entry */
        ori r11, r0, IO_BASE        
        swi r0, r11, ASQ_CLEAR0
        swi r0, r11, ASQ_CLEAR1
        swi r0, r11, ASQ_CLEAR2
        swi r0, r11, ASQ_CLEAR3
        
        /* opcode = CMD[7:0] = 0x04          */
        /* cmd id = CMD[31:16]               */       
        /* DW10 = QUEUE ID                   */     
        /* see NVMe 1.1b 5.5                 */
        
        bslli r12, r5, 16    /* move r5=cmd id 31:16 */
        ori r12, r12, 0x04    /* opcode */
        swi r12, r11, ASQ_CMD
        swi  r8, r11, ASQ_DW10
    
        swi r0, r11, ASQ_INSERT        

        /* save opcode & param for override */
        ori  r3, r0, 0x04   /* opcode */
        or   r4, r0, r0     /* param  */
        bri admin_cpl_poll  /* wait for completion */          

/******************************************************************************/      
admin_create_isq: 

        /* r5 = command id     
         * r6 = msb base address (PRP10)
         * r7 = lsb base address (PRP11)
         * r8 = queue id
         * r9 = queue entries
         * r10 = completino queue id
         */
        
        /* 
         * as long as there's only 1 admin command outstanding
         * the queue cannot be full
         */
        
        /* clear entry */
        ori r11, r0, IO_BASE        
        swi r0, r11, ASQ_CLEAR0
        swi r0, r11, ASQ_CLEAR1
        swi r0, r11, ASQ_CLEAR2
        swi r0, r11, ASQ_CLEAR3
                
        /* opcode = CMD[7:0] = 0x01          */
        /* cmd id = CMD[31:16]               */
        /* PRP1 = I/O Queue address          */
        /* DW10 = QUEUE SIZE/QUEUE ID        */
        /* DW11 = completion queue id, QPRIO, physically contiguous  */
        /* see NVMe 1.1b 5.4                 */
        
        bslli r12, r5, 16    /* move r5=cmd id 31:16 */
        ori r12, r12, 0x01    /* opcode */
        swi r12, r11, ASQ_CMD

        bslli r12, r9, 16
        or  r12, r12, r8      
        swi r12, r11, ASQ_DW10
        bslli r12, r10, 16
        ori r12, r12, 0x01
        swi r12, r11, ASQ_DW11
                
        swi r6, r11, ASQ_PRP10
        swi r7, r11, ASQ_PRP11

        swi  r0, r11, ASQ_INSERT        

        /* save opcode & param for override */
        ori  r3, r0, 0x01   /* opcode */
        or   r4, r0, r0     /* param  */
        bri admin_cpl_poll  /* wait for completion */          
          
/******************************************************************************/      
admin_delete_isq: 

        /* r5 = command id
           r8 = queue id
         */
        
        /* clear entry */
        ori r11, r0, IO_BASE        
        swi r0, r11, ASQ_CLEAR0
        swi r0, r11, ASQ_CLEAR1
        swi r0, r11, ASQ_CLEAR2
        swi r0, r11, ASQ_CLEAR3
        
        /* opcode = CMD[7:0] = 0x00          */
        /* cmd id = CMD[31:16]               */       
        /* DW10 = QUEUE ID(=1)               */     
        /* see NVMe 1.1b 5.6                 */
        
        bslli r12, r5, 16    /* move r5=cmd id 31:16 */
        ori r12, r12, 0x00    /* opcode */
        swi r12, r11, ASQ_CMD
        swi  r8, r11, ASQ_DW10       
        swi  r0, r11, ASQ_INSERT        

        /* save opcode & param for override */
        ori  r3, r0, 0x00   /* opcode */
        or   r4, r0, r0     /* param  */
        bri admin_cpl_poll  /* wait for completion */          

        /******************************************************************************/      
admin_deallocate: 

        /* r5 = command id     
         * r6 = number of ranges
         * r7 = NSID
         */

        /* clear entry */
        /* add UCIOQ_OFFSET to use ISQ0 instead of admin queue */
        ori r11, r0, IO_BASE        
        swi r0, r11, UCIOQ_OFFSET+ASQ_CLEAR0
        swi r0, r11, UCIOQ_OFFSET+ASQ_CLEAR1
        swi r0, r11, UCIOQ_OFFSET+ASQ_CLEAR2
        swi r0, r11, UCIOQ_OFFSET+ASQ_CLEAR3
        
        /* opcode = CMD[7:0] = 0x09 = dataset management  */
        /* cmd id = CMD[31:16]               */
        
        bslli r12, r5, 16    /* move r5=cmd id 31:16 */
        #ifdef SIM
        /* sim model crashes with deallocate command */
        ori r12, r12, 0x01    /* opcode */
        #else
        ori r12, r12, 0x09    /* opcode */
        #endif
        swi r12, r11, UCIOQ_OFFSET+ASQ_CMD

        swi   r7, r11, UCIOQ_OFFSET+ASQ_NSID
        
        swi r6, r11, UCIOQ_OFFSET+ASQ_DW10
        ori r12, r0, 0x04  /* bit 2 = deallocate */
        swi r12, r11, UCIOQ_OFFSET+ASQ_DW11

        ori r12, r0, NVME_ADMINWR_BASE0
        swi r12, r11, UCIOQ_OFFSET+ASQ_PRP10
        
        ori r12, r0, NVME_ADMINWR_BASE1
        swi r12, r11, UCIOQ_OFFSET+ASQ_PRP11              
       
        swi r0, r11, UCIOQ_OFFSET+ASQ_INSERT        

        /* save opcode & param for override */
        ori  r3, r0, 0x09   /* opcode */
        or   r4, r0, r0     /* param  */
        bri admin_cpl_poll  /* wait for completion */          
/******************************************************************************/      
admin_abort_io: 

        /* r5 = command id in the I/O queue
           r6 - SQ ID 
         */
        
        /* clear entry */
        ori r11, r0, IO_BASE        
        swi r0, r11, ASQ_CLEAR0
        swi r0, r11, ASQ_CLEAR1
        swi r0, r11, ASQ_CLEAR2
        swi r0, r11, ASQ_CLEAR3
        
        /* opcode = CMD[7:0] = 0x00          */
        /* cmd id = CMD[31:16]               */       
        /* DW10 = 31:16 = I/O CID.  15:0 = QUEUE ID */      
        /* see NVMe 1.1b 5.1                 */
        
        bslli r12, r5, 16          /* move r5=cmd id 31:16 */
        andi  r12, r12, 0x0FFF0000 /* use 12b of I/O command id for admin command id */
        ori r12, r12, 0x08         /* opcode */
        swi r12, r11, ASQ_CMD

        bslli r12, r5, 16
        /* SQ queue id = r6 */
        andi   r3, r6, 0xFF
        or    r12, r12, r3
        swi   r12, r11, ASQ_DW10       
        swi    r0, r11, ASQ_INSERT        

        /* save opcode & param for override */
        ori  r3, r0, 0x08   /* opcode */
        or   r4, r0, r0     /* param  */
        bri admin_cpl_poll  /* wait for completion */          
/******************************************************************************/      
/* poll for completion of admin command                                       */
/* ends with a return from subroutine                                         */
admin_cpl_poll:
     
        lwi   r7, r0, IO_GPI1

        andi r12, r7, GPI_INIT_DONE
        beqi r12,     pcie_link_down        /* PCIe link went down - wait for link up and reinit */

        andi r12, r7, GPI_ACQ_CQ0_EMPTY    /* wait for completion queue to have something */
        beqi r12,     admin_cpl_poll_done
        
        andi r12, r7, GPI_ACQ_CQ1_EMPTY    /* wait for completion queue to have something */
        beqi r12,     admin_cpl_poll_done

        bri admin_cpl_poll
        
admin_cpl_poll_done:
        /* check if this command has error inject/override */
        /* r3 = opcode */
        /* r4 = param  */
        or     r12,  r0, r0
        bslli   r6,  r4, 8
        or      r6,  r6, r3  /* r6 = <param><opcode> */
admin_cpl_override_start:              
        lwi     r3, r12, override_table
        andi    r4,  r3, 0xff
        beqi    r4,      admin_cpl_override_next  /* not enabled? */
        bsrli   r4,  r3, 8        
        andi    r4,  r4, 0xffff                   /* param & opcode match value */
        xor     r4,  r4, r6        
        bnei    r4,      admin_cpl_override_next  /* no match */             
        /* override is active */
        lwi     r3, r12, override_table+4  /* offset */
        add     r3,  r3, r11
        lwi     r4,  r3, SNTL_ADQ_BUFFER   /* r4 = dword being overridden */
        lwi     r5, r12, override_table+8
        and     r4,  r4, r5                /* AND - mask */
        lwi     r5, r12, override_table+12
        or      r4,  r4, r5                /* OR - override */
        swi     r4,  r3, SNTL_ADQ_BUFFER        
        
admin_cpl_override_next:
        addi   r12, r12, 16  /* 16 bytes per override entry */
        addi    r5, r12, -(ADMIN_OVERRIDE_ENTRIES*ADMIN_OVERRIDE_BYTES)
        blti    r5,      admin_cpl_override_start        
                
admin_cpl_override_done:        
        andi r12, r7, GPI_ACQ_CQ1_EMPTY
        beqi r12, admin_cpl_cq1

        lwi r5, r11, ACQ_ENTRY     /* r5=completion DW0 */
        lwi r6, r11, ACQ_ENTRY+0xC /* r6=status|P|command id */
        swi r0, r11, ACQ_REMOVE
        
        bsrli r3, r6, 17      /* r3 = status field of dw3 */
        rtsd r15, 8
        nop

admin_cpl_cq1:  /* completion queue 1 is for SQ1 owned by microcode */        
        lwi r5, r11, UCIOQ_OFFSET+ACQ_ENTRY     /* r5=completion DW0 */
        lwi r6, r11, UCIOQ_OFFSET+ACQ_ENTRY+0xC /* r6=status|P|command id */
        swi r0, r11, UCIOQ_OFFSET+ACQ_REMOVE
        
        bsrli r3, r6, 17      /* r3 = status field of dw3 */
        rtsd r15, 8
        nop        

/******************************************************************************/      
/* poll for completion of passthru command                                    */
/* ends with a return from subroutine                                         */

admin_cpl_poll2:
       
        lwi r12, r0, IO_GPI1

        andi r3, r12, GPI_INIT_DONE
        beqi r3, pcie_link_down        /* PCIe link went down - wait for link up and reinit */

        andi r12, r12, GPI_ACQ_CQ0_EMPTY  /* wait for completion queue to have something */
        bnei r12, admin_cpl_poll2

        lwi r5, r11, ACQ_ENTRY     /* r5=completion DW0 */
        lwi r6, r11, ACQ_ENTRY+0xC /* r6=status|P|command id */
        swi r0, r11, ACQ_REMOVE

        swi r5, r11, SNTL_STATUS1  /* for passthru, return DW0 of completion in sense data */

        
admin_cpl_poll2_done:
        rtsd r15, 8
        nop


/******************************************************************************/        

/******************************************************************************/
load_rom:         
        ori  r11, r0, IO_BASE
        lwi   r3, r11, REGS_FC_DBGDISP        
        bsrli r5, r3, 24    /* move bits 31:24 to byte 0*/
        andi  r5, r5, 0x7F  /* ignore valid */
        xori  r6, r5, 0x55  /* array select=0x55 load microcode */
        beqi  r6, load_rom_wr_ucode
        xori  r6, r5, 0x01  /* array select=0x01 write admin override */
        beqi  r6, load_rom_wr_override
        xori  r6, r5, 0x02  /* array select=0x02 read admin override */
        beqi  r6, load_rom_rd_override
        xori  r6, r5, 0x56  /* array select=0x56 read microcode */
        beqi  r6, load_rom_rd_ucode
        
        rtsd r15, 8
        nop
        
load_rom_wr_override:
        andi  r12,  r3, 0x0FFFC  /* word offset */
        addi   r4, r12, -(ADMIN_OVERRIDE_ENTRIES*ADMIN_OVERRIDE_BYTES)
        bgei   r4,      load_rom_exit
        lwi    r4, r11, REGS_FC_DBGDATA
        swi    r4, r12, override_table
        bri    load_rom_exit

load_rom_rd_override:
        andi  r12,  r3, 0x0FFFC  /* word offset */
        addi   r4, r12, -(ADMIN_OVERRIDE_ENTRIES*ADMIN_OVERRIDE_BYTES)
        bgei   r4,      load_rom_exit
        lwi    r4, r12, override_table
        swi    r4, r11, REGS_FC_DBGDATA
        bri    load_rom_exit

load_rom_rd_ucode:
        andi r12, r3, 0x0FFFC  /* word address */
        lw    r4, r0, r12
        swi   r4, r11, REGS_FC_DBGDATA
        bri   load_rom_exit
        
load_rom_exit:       
        andi  r12, r3, 0x7FFFFFFF /* clear valid */
        swi   r12, r11, REGS_FC_DBGDISP      
        rtsd r15, 8
        nop
        
/******************************************************************************/               
        .section ".ldrom","ax"        
        /* get address & data from mmio regs, write to program memory */
        /* this is at a fixed location so it can overwrite itself */
        /* array select = 0x55 - load microcode */
        /* if loading microcode, only way to exit is reset or nvme port link down */        
load_rom_wr_ucode:
        lwi   r3, r11, REGS_FC_DBGDISP        
        bsrli r5, r3, 24    /* move bits 31:24 to byte 0*/
        xori  r6, r5, (0x80 | 0x55)  /* valid bit and array select=0x55 (ucode) */
        beqi r6, load_rom_ucode_1  /* valid=1 so write the next word */
        xori r6, r5, 0x55
        beqi r6, load_rom_wr_ucode   /* wait for valid */
        
        /* exit load_rom loop when array select!=0x55 */
        /* wait for pcie link down then re-init */
load_rom_ucode_exit:
        lwi r12, r0, IO_GPI1        
        andi r3, r12, GPI_INIT_DONE
        bnei r3, load_rom_ucode_exit 
        bri pcie_init        

load_rom_ucode_1:             
        andi r12,  r3, 0x0FFFC  /* word address */
        lwi   r4, r11, REGS_FC_DBGDATA
        sw    r4,  r0, r12
        andi r12,  r3, 0x7FFFFFFF /* clear valid */
        swi  r12, r11, REGS_FC_DBGDISP
        bri  load_rom_wr_ucode

        
/******************************************************************************/
        .data
        .balign 4
/* current scrub offset */
scrub_pointer:
        .byte 0,0,0,0
        
/* keep ucode status for copying to GPIO */
status_data:    
        .byte 0,0,0,0
login_retry_count:
        .byte 0,0,0,0
        
/* save IEEE oui from id controller */
        .balign 4
data_ieee_oui:
        .byte 0,0,0,0
                   
        .balign 4        
t10_vendor_id_string:
      /*.ascii "NVMe    " */
        .ascii "IBM     "

        .balign 4
inquiry_template:
        .ascii "0123_4567_89AB_CDEF_0123_4567_89AB_CDEF."


override_table: 
/* NVMe Admin data override for debug */
/* 4 dwords per override 
 * 16 overrides 
 * byte 0:      enable
 * byte 1:      opcode match
 * byte 2:      param  mask  (DW10 byte 0 AND mask)
 * byte 3:      param  match (DW10 byte 0 XOR mask)
 * bytes 4-7:   offset into data structure
 * bytes 8-11:  data mask      (AND value)
 * bytes 12-15: data override  (OR value)
 */
        .balign 4
        .space (ADMIN_OVERRIDE_ENTRIES*ADMIN_OVERRIDE_BYTES), 0


/* last used address - end of data scrub */
        .balign 4
end_scrub:
        .byte 0,0,0,0
