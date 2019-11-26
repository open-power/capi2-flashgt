
Xilinx vivado project for FlashGT+  (2017.4)

To create the vivado project:

./flashgtp_prj.tcl &

Due to tight timing in the PSL IP and afu logic, it typically takes multiple runs to close timing.  The project includes scripts that adjust timing constraints based on the implementation name (ie: impl_1, impl_2).

