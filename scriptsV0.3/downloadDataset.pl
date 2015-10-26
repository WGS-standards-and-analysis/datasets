#!/usr/bin/env perl

# Downloads a test set directory
# 
# Author: Lee Katz <gzu2@cdc.gov>
# WGS standards and analysis group

use strict;
use warnings;
use Getopt::Long;
use Data::Dumper;
use File::Basename qw/fileparse dirname basename/;
use File::Temp qw/tempdir tempfile/;

use ExtUtils::MakeMaker;

my $scriptInvocation="$0 ".join(" ",@ARGV);
local $0=basename $0;
sub logmsg{print STDERR "$0: @_\n";}

exit main();

sub main{
  my $settings={};
  GetOptions($settings,qw(help outdir=s format=s shuffled! fasta! layout=s only=s verbose!));
  die usage() if($$settings{help});
  $$settings{format}||="tsv"; # by default, input format is tsv
  $$settings{seqIdTemplate}||='@$ac_$sn[_$rn]/$ri';
  $$settings{layout}||="onedir";
  $$settings{layout}=lc($$settings{layout});
  $$settings{only}||="";
  $$settings{only}=lc($$settings{only});

  # Get the output directory and spreadsheet, and make sure they exist
  $$settings{outdir}||=die "ERROR: need outdir parameter\n".usage();
  mkdir $$settings{outdir} if(!-d $$settings{outdir});
  my $spreadsheet=$ARGV[0] || die "ERROR: need spreadsheet file!\n".usage();
  die "ERROR: cannot find $spreadsheet" if(!-e $spreadsheet);

  # Read the spreadsheet
  my $infoTsv = {};
  if($$settings{format} eq 'tsv'){
    $infoTsv=tsvToMakeHash($spreadsheet,$settings);
  } else {
    die "ERROR: I do not understand format $$settings{format}";
  }

  writeMakefile($infoTsv,$settings);

  return 0;
}

sub tsvToMakeHash{
  my($tsv,$settings)=@_;

  # Thanks Torsten Seemann for this idea
  my $make_target = '$@';
  my $make_dep = '$<';
  my $make_deps = '$^';
  my $bash_dollar = '$$';

  # For the fastq-dump command
  my $seqIdTemplate=$$settings{seqIdTemplate};
     $seqIdTemplate=~s/\$/\$\$/g;  # compatibility with make
  
  my $make={};                  # Make hash
  my $fileToName={};            # mapping filename to base name
  my $have_reached_biosample=0; # marked true when it starts reading entries
  my @header=();                # defined when we get to the biosample_acc header row
  open(TSV,$tsv) or die "ERROR: could not open $tsv: $!";
  while(<TSV>){
    s/^\s+|\s+$//g; # trim whitespace
    next if(/^$/);  # skip blank lines

    ## read the contents
    # Read biosample rows
    if($have_reached_biosample){
      my $tmpdir=tempdir("$0XXXXXX",TMPDIR=>1,CLEANUP=>1);

      my @F=split(/\t/,$_);
      for(@F){
        next if(!$_);
        s/^['"]+|['"]+//g;  # trim quotes
        s/^\s+|\s+$//g;     # trim whitespace
      }
      # Get an index of each column
      my %F;
      @F{@header}=@F;

      # SRA download command
      if($F{srarun_acc}){
        my $filename1="$F{srarun_acc}_1.fastq.gz";
        my $filename2="$F{srarun_acc}_2.fastq.gz";

        $$make{$filename2}{DEP}=[
          $filename1,
        ];
        $$make{$filename1}{CMD}=[
          "fastq-dump --defline-seq '$seqIdTemplate' --defline-qual '+' --split-files -O . --gzip $F{srarun_acc} ",
          "echo -e \"$F{sha256sumread1}  $filename1\\n$F{sha256sumread2}  $filename2\" | sha256sum --check",
        ];
        $F{strain} || die "ERROR: $F{srarun_acc} does not have a strain name!";
      }

      # GenBank download command
      elsif($F{genbankassembly}){
        my $filename1="$F{genbankassembly}.gbk";
        my $filename2="$F{genbankassembly}.fasta";

        $$make{$filename2}{CMD}=[
            "esearch -db assembly -query '$F{genbankassembly} NOT refseq[filter]' | elink -related -target nuccore | efetch -format fasta > $make_target",
        ];
        $$make{$filename1}{CMD}=[
          "esearch -db assembly -query '$F{genbankassembly} NOT refseq[filter]' | elink -related -target nuccore | efetch -format gbwithparts > $make_target",
          "echo -e \"$F{sha256sumassembly}  $filename1\" | sha256sum --check",
        ];

        $F{strain} || die "ERROR: $F{genbankassembly} does not have a strain name!";
      }

    } elsif(/^biosample_acc/){
      $have_reached_biosample=1;
      @header=split(/\t/,lc($_));
      next;
    }
    # metadata
    else {
      my ($key,$value)=split /\t/;
      $key=lc($key);
      $value||="";            # in case of blank values
      $value=~s/^\s+|\s+$//g; # trim whitespace
      $value=~s/\s+/_/g;      # turn whitespace into underscores
      #$$d{$key}=$value;
      #
      if($key eq 'tree'){
        $$make{"tree.dnd"}={
          CMD=>[
            "wget -O $make_target '$value'",
          ],
        };
      }
    }

  }
  close TSV;
  
  return $make;
}

# Thanks Torsten Seemann for the makefile idea
sub writeMakefile{
  my($m,$settings)=@_;

  # Add on the behavior I want
  $$m{'.DELETE_ON_ERROR'}={};
  $$m{'.PHONY'}{DEP}=['%.fastq.gz', '%.gbk', '%.dnd'];

  my @target=sort{
    #return 1 if($a=~/(^\.)|all/ && $b !~/(^\.)|all/);
    return $a cmp $b;
  } keys(%$m);

  open(MAKEFILE,">makefile") or die "ERROR: could not open makefile for writing: $!";
  for my $target(@target){
    my $properties=$$m{$target};
    $$properties{CMD}||=[];
    $$properties{DEP}||=[];
    print MAKEFILE "$target: ".join(" ",@{$$properties{DEP}})."\n\n";
    for my $cmd(@{ $$properties{CMD} }){
      print MAKEFILE "\t$cmd\n";
    }
  }
}


sub usage{
  "  $0: Reads a standard dataset spreadsheet and downloads its data
  Brought to you by the WGS Standards and Analysis working group
  https://github.com/WGS-standards-and-analysis/datasets

  Usage: $0 -o outdir spreadsheet.dataset.tsv
  PARAM        DEFAULT  DESCRIPTION
  --outdir     <req'd>  The output directory
  --format     tsv      The input format. Default: tsv. No other format
                        is accepted at this time.
  --layout     onedir   onedir   - everything goes into one directory
                        byrun    - each genome run gets its separate directory
                        byformat - fastq files to one dir, assembly to another, etc
  --shuffled   <NONE>   Output the reads as interleaved instead of individual
                        forward and reverse files.
  --fasta      <NONE>   Convert all fastq.gz files to fasta
  --only       <NONE>   Only download this type of data.  Good for debugging.
                        Possible values: tree, genbank, sra
  --verbose    <NODE>   Output more text.  Good for debugging.
  "
}


