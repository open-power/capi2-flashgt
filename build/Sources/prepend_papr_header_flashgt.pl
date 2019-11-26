#! /usr/bin/perl -w

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


use Getopt::Long;
use IO::File;

use strict;
use bigint qw/hex/;

my $binfile;
my $paprfile;
my $optOK = 0;
my $prthelp;

$optOK = GetOptions ( "i=s", \$binfile,
                      "o=s", \$paprfile,
                      "h|help!"   ,  \$prthelp
                    );

if( !($optOK) || ($#ARGV>=0) || !defined($binfile) || !defined($paprfile) ) {
  print <<USAGE;

$0 - prepend PAPR header to FlashGT+ AFU image

Usage: $0 -i flashgtp.160415P1.bin -o 1410000614103306.00000001160415N1

USAGE

  exit -1;
}

my $fsize = -s $binfile;
if( $fsize == 0 ) {
  printf("ERROR: Invalid Input file $binfile\n");
  exit -2;
}

my $fh = IO::File->new($paprfile,"w");
binmode($fh);

build_header($fh, 0x0001,0x10140628, 0x101404DD, $fsize);
$fh->close();

system("cat $binfile >> $paprfile");

my $paprsize = -s $paprfile;
if( $paprsize == ($fsize + 0x80)) {
  exit 0;
} else {
  print "ERROR: Output file $paprfile size mismatch\n";
  exit -3;
}



sub build_header {
  my($fh, $header, $devid1, $devid2, $fsize) = @_;

  # PAPR header - big endian
  #struct download_hdr {
  #    uint16_t   hdr;         // 0x0001
  #    uint16_t   resvd[3];
  #    uint64_t   device_id;   // 0x101404CF101404DDLL
  #    uint32_t   resvd2;
  #    uint32_t   field1;      // 0x80
  #    uint64_t   file_length; //
  #    uint32_t   resvd3[24];
  #};


  my $bv;
  my $hdr;

  $bv = pack("n",0x0001);     # n  == 16b network order (big endian)
  print $fh $bv;
  $bv = pack("n", 0);
  print $fh $bv;
  print $fh $bv;
  print $fh $bv;

  $bv = pack("N",$devid1);    # N  == 32b network order (big endian)
  print $fh $bv;
  $bv = pack("N",$devid2);
  print $fh $bv;
  $bv = pack("N", 0);
  print $fh $bv;
  $bv = pack("N", 0x80);
  print $fh $bv;
  $bv = pack("Q>","$fsize");  # Q>  == 64b big endian
  print $fh $bv;

  $bv = pack("N", 0);
  for (0..23) {
    print $fh $bv;
  }

}

