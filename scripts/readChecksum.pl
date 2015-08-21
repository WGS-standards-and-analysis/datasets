#!/bin/env perl

use strict;
use warnings;
use Getopt::Long;
use File::Temp;
use File::Basename qw/fileparse basename/;

local $0=basename $0;
sub logmsg{print STDERR "$0: @_\n"}
exit main();

sub main{
  my $settings={};
  GetOptions($settings,qw(help checksum=s));
  $$settings{checksum}||="sha256sum";
  die usage() if($$settings{help} || !@ARGV);

  for my $fastq(@ARGV){
    my $checksum=checksum($fastq,$settings);
    print join("\t",$fastq,$checksum)."\n";
  }

  return 0;
}

sub checksum{
  my($fastq,$settings)=@_;
  my $tempdir =File::Temp::tempdir("XXXXXX",TMPDIR=>1,CLEANUP=>1);
  my $unsorted="$tempdir/unsorted.txt";
  my $sorted  ="$tempdir/sorted.txt";

  logmsg "Reading";
  my($name,$dir,$ext)=fileparse($fastq,qw(.fastq.gz .fq.gz .fq .fastq));
  if($ext=~/gz$/){
    open(FASTQ,"gunzip -c $fastq |") or die "ERROR: could not open $fastq for reading with gunzip: $!";
  } else {
    open(FASTQ,"<",$fastq) or die "ERROR: could not open $fastq for reading: $!";
  }
  
  open(UNSORTED,">",$unsorted) or die "ERROR: could not open $unsorted for writing: $!";
  while(<FASTQ>){
    my $seq =<FASTQ>;
             <FASTQ>; # burn the '+' line
    my $qual=<FASTQ>;
    print UNSORTED "$seq$qual";
  }
  close FASTQ;
  close UNSORTED;

  logmsg "Sorting";
  system("sort $unsorted > $sorted");
  die "ERROR: could not sort $unsorted into $sorted: $!" if $?;

  logmsg "Checksum";
  my $checksum=`$$settings{checksum} $sorted`;
  die "ERROR: could not run $$settings{checksum} on $sorted" if $?;
  $checksum=~s/^\s+|\s+$//g;
  $checksum=~s/\s.*$//;

  return $checksum;
}

sub usage{
  "$0: creates a checksum based on a fastq file's sequences and quals
  Usage: $0 file.fastq [file2.fastq ...]
  --checksum  sha256sum  The exec for finding checksum
  "
}
