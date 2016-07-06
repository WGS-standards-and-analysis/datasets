#!/usr/bin/env perl
# Author: Chris Gulvik
# Modified by: Lee Katz <lkatz@cdc.gov>


use strict;
use warnings;
#no warnings 'utf8';  #hides 'Wide character in print' error
use autodie;
use File::Basename qw/basename fileparse/;
use Getopt::Long;

use FindBin qw/$RealBin/;
use lib "$RealBin/../lib/perl5";
use Spreadsheet::ParseExcel;
use Spreadsheet::XLSX;

my @supportedExt=qw(.xlsx .xls);
local $0=basename $0;
sub logmsg{print STDERR "$0: @_\n"}

exit main();

sub main{
  my $settings={};
  GetOptions($settings,qw(help firstsheet sheetnum=i sep|separator=s)) or die $!;
  $$settings{sheetnum}=1 if($$settings{firstsheet});
  $$settings{sep}||="\t";
  die usage() if(@ARGV<1 || $$settings{help});

  my $file = $ARGV[0];
  die "ERROR: not found: $file" if(!-e $file);
  my($name,$dir,$ext)=fileparse($file,@supportedExt);

  my $sheetCounter=0;
  if($ext =~ /\.xls$/i){

      my $parser = Spreadsheet::ParseExcel -> new();
      my $workbook = $parser -> parse($ARGV[0]);
      if(!defined $workbook){
          die $parser -> error(), ".\n";
      }

      for my $sheet($workbook -> worksheets()){
          $sheetCounter++;
          if($$settings{sheetnum} && $sheetCounter!=$$settings{sheetnum}){
            next;
          }
          my $sheetName = $sheet -> get_name();
          my($row_min,$row_max)=$sheet -> row_range();
          my($col_min,$col_max)=$sheet -> col_range();
          for my $row ($row_min .. $row_max){
              my @values;
              for my $col ($col_min .. $col_max){
                  my $cell = $sheet -> get_cell($row, $col);
                  if(defined $cell and $cell -> value() ne ''){
                      push @values, $cell -> value();
                  }
                  else{
                      push @values, $$settings{sep};
                  }
              }
              print join($$settings{sep},@values)."\n";
          }
      }
      logmsg "XLS converted into TSV";
  }

  elsif($ext =~ /\.xlsx$/i){

      my $workbook = Spreadsheet::XLSX -> new ($ARGV[0]);
      foreach my $sheet (@{$workbook -> {Worksheet}}){
          $sheetCounter++;
          if($$settings{sheetnum} && $sheetCounter!=$$settings{sheetnum}){
            next;
          }
          my $sheetName = $sheet->{Name};
          $sheet -> {MaxRow} ||= $sheet -> {MinRow};    
          foreach my $row ($sheet -> {MinRow} .. $sheet -> {MaxRow}){             
              $sheet -> {MaxCol} ||= $sheet -> {MinCol};                
              foreach my $col ($sheet -> {MinCol} .. $sheet -> {MaxCol}){
                  my $cell = $sheet -> {Cells} [$row] [$col];                
                  if($cell){
                      print $cell -> {Val}, $$settings{sep};
                  }
                  else{
                      print $$settings{sep};
                  }
              }
              print "\n";
          }
      }
      logmsg "XLSX converted into TSV";
  }

  else{
      logmsg "ERROR: unsupported extension in $file\n".
             "This script requires a XLS or XLSX extension\n".
             usage();
  }

  return 0;
}

sub usage{
"$0: Converts a Microsoft Excel spreadsheet into TSV format.
Output is automatically created in same directory as the input.
Each worksheet is written as a separate file.

usage: $0 input.xls[x] > out.tsv
--firstsheet        Print only the first sheet of a workbook.
                    Synonym for --sheetnum=1
--sheetnum    ''    Print only this sheet number (one-based)
--separator   '\\t'  By default, tab-delimited output, but any
                    string can be specified.
";
}
