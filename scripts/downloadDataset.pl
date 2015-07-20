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
use File::Temp qw/tempdir tmpfile/;
use Bio::Perl;

local $0=basename $0;
sub logmsg{print STDERR "$0: @_\n";}

exit main();

sub main{
  my $settings={};
  GetOptions($settings,qw(help outdir=s format=s shuffled! fasta! layout=s));
  die usage() if($$settings{help});
  $$settings{format}||="tsv"; # by default, input format is tsv
  $$settings{seqIdTemplate}||='@$ac_$sn[_$rn]/$ri';
  $$settings{layout}||="onedir";
  $$settings{layout}=lc($$settings{layout});

  # Get the output directory and spreadsheet, and make sure they exist
  $$settings{outdir}||=die "ERROR: need outdir parameter\n".usage();
  mkdir $$settings{outdir} if(!-d $$settings{outdir});
  my $tsv=$ARGV[0] || die "ERROR: need tsv file!\n".usage();
  die "ERROR: cannot find $tsv" if(!-e $tsv);

  # Read the spreadsheet
  my $infoTsv=readTsv($tsv,$settings);

  # Download everything
  downloadEverything($infoTsv,$settings);

  return 0;
}

sub readTsv{
  my($tsv,$settings)=@_;

  # For the fastq-dump command
  my $seqIdTemplate=$$settings{seqIdTemplate};
  
  my $d={}; # download hash
  my $have_reached_biosample=0; # marked true when it starts reading entries
  my @header=(); # defined when we get to the biosample_acc header row
  open(TSV,$tsv) or die "ERROR: could not open $tsv: $!";
  while(<TSV>){
    s/^\s+|\s+$//g; # trim whitespace
    next if(/^$/); # skip blank lines

    ## read the contents
    # Read biosample rows
    if($have_reached_biosample){
      my $tmpdir=tempdir("$0XXXXXX",TMPDIR=>1,CLEANUP=>1);
      # Get an index of each column
      my %F;
      @F{@header}=split(/\t/,$_);

      # SRA download command
      if($F{srarun_acc}){
        $$d{$F{srarun_acc}}{download}="fastq-dump --defline-seq '$seqIdTemplate' --defline-qual '+' --split-files -O $tmpdir --gzip $F{srarun_acc} ";
        $$d{$F{srarun_acc}}{name}=$F{strain} || die "ERROR: $F{srarun_acc} does not have a strain name!";
        $$d{$F{srarun_acc}}{type}="sra";
        $$d{$F{srarun_acc}}{tempdir}=$tmpdir;

        # Files will be listed as from=>to, and they will have checksums
        $$d{$F{srarun_acc}}{from}=["$tmpdir/$F{srarun_acc}_1.fastq.gz", "$tmpdir/$F{srarun_acc}_2.fastq.gz"];
        $$d{$F{srarun_acc}}{to}=["$$settings{outdir}/$F{strain}_1.fastq.gz", "$$settings{outdir}/$F{strain}_2.fastq.gz"];
        $$d{$F{srarun_acc}}{checksum}=[$F{sha256sumread1},$F{sha256sumread2}];
        if($$settings{layout} eq 'byrun'){
          $$d{$F{srarun_acc}}{to}=["$$settings{outdir}/$F{strain}/$F{strain}_1.fastq.gz","$$settings{outdir}/$F{strain}/$F{strain}_2.fastq.gz"];
        }
      }

      # GenBank download command
      if($F{genbankassembly}){
        $$d{$F{genbankassembly}}{download}="efetch -format gbwithparts -db nuccore -id $F{genbankassembly} > $tmpdir/$F{genbankassembly}.gbk";
        $$d{$F{genbankassembly}}{name}=$F{strain} || die "ERROR: $F{genbankassembly} does not have a strain name!";
        $$d{$F{genbankassembly}}{type}="genbank";
        $$d{$F{genbankassembly}}{tempdir}=$tmpdir;

        # Files will be listed as from=>to, and they will have checksums
        $$d{$F{genbankassembly}}{from}=["$tmpdir/$F{genbankassembly}.gbk"];
        $$d{$F{genbankassembly}}{to}=["$$settings{outdir}/$F{strain}.gbk"];
        $$d{$F{genbankassembly}}{checksum}=[$F{sha256sumassembly}];

        $$d{$F{genbankassembly}}{$_} = $F{$_} for(qw(suggestedreference outbreak datasetname));
        if($$settings{layout} eq 'byrun'){
          $$d{$F{genbankassembly}}{to}=["$$settings{outdir}/$F{strain}.gbk"];
        }
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
      $$d{$key}=$value;
    }

  }
  close TSV;

  return $d;
}

sub downloadEverything{
  my($d,$settings)=@_;

  # Read each entry one at a time.  Each entry is a hash
  # consisting of: type, name, download, tempdir.
  while(my($key,$value)=each(%$d)){
    # Only download entries which are hash values
    next if(ref($value) ne "HASH" || !defined($$value{download}));

    # Get some local variables to make it more readable downstream
    my($type,$name,$download,$tempdir)=($$value{type},$$value{name},$$value{download},$$value{tempdir});

    # Skip this download if the target files exist
    my $numFiles=scalar(@{$$value{from}});
    my $i_can_skip=1; # true until proven false
    for(my $i=0;$i<$numFiles;$i++){
      #logmsg join("\t",$$value{to}[$i],sha256sum($$value{to}[$i]),$$value{checksum}[$i]);
      $i_can_skip=0 if(!-e $$value{to}[$i] || sha256sum($$value{to}[$i]) ne $$value{checksum}[$i]);
    }
    if($i_can_skip){
      logmsg "I found the files for $name/$type and so I can skip this download";
    }
    #else { die join(" ",@{$$value{to}}); }  ## DEBUG

    # Perform the download unless given permission to skip it
    if(!$i_can_skip){
      logmsg "Downloading $name/$type to $tempdir";
      system($download);
      die "ERROR downloading with command\n  $download" if $?;
    }
      
    # Move the files according to how the download entry states.
    for(my $i=0;$i<$numFiles;$i++){
      my($from,$to)=($$value{from}[$i],$$value{to}[$i]);

      mkdir(dirname($to)) if(!-d dirname($to));
      system("mv -v $from $to") if(!$i_can_skip);
      die "ERROR moving $from to $to" if $?;

      # Perform any kind of post-processing after the file arrives.
      postProcess($to,$type,$value,$settings);
    }

  }

  # I can't think of any useful return value at this time.
  return 1;
}

# Perform any kind of post processing after a file has landed
# in the destination directory.
sub postProcess{
  my($file,$type,$fileInfo,$settings)=@_;
  ## Any kind of special processing, after the download.

  ## Fastq file post-processing
  if($type eq 'sra'){
    # Create fasta files if requested
    if($$settings{fasta}){
      my $fasta=dirname($file)."/".basename($file,qw(.fastq.gz .fastq)).".fasta";
      fastqToFasta($file,$fasta,$settings) if(!-e $fasta);
    }
  }

  ## GenBank file post processing
  elsif($type eq 'genbank'){
    my $fasta=dirname($file)."/".basename($file,qw(.gbk .gb)).".fasta";
    genbankToFasta($file,$fasta,$settings) if(!-e $fasta);
  }
}

########################
## utility subroutines
########################

# Convert a genbank to a fasta file
sub genbankToFasta{
  my($genbank,$fasta,$settings)=@_;
  logmsg "Also generating $fasta.tmp";
  my $in=Bio::SeqIO->new(-file=>$genbank,-verbose=>-1);
  my $out=Bio::SeqIO->new(-file=>">$fasta.tmp",-format=>"fasta");
  while(my $seq=$in->next_seq){
    $out->write_seq($seq);
  }
  $out->close;
  $in->close; 

  mkdir(dirname($fasta)) if(!-d dirname($fasta));
  system("mv -v $fasta.tmp $fasta"); die if $?;
}

# Convert a fastq to a fasta file
sub fastqToFasta{
  my($fastq,$fasta,$settings)=@_;
  logmsg "Converting $fastq => $fasta.tmp";
  open(FASTQ,"zcat $fastq |") or die "ERROR: could not open $fastq: $!";
  open(FASTA,">","$fasta.tmp") or die "ERROR: could not write to $fasta.tmp: $!";
  my $i=0;
  while(my $line=<FASTQ>){
    $i++;
    my $mod=$i % 4;
    if($mod==1){
      print FASTA ">".substr($line,1);
    } elsif($mod==2){
      print FASTA $line;
    } elsif($mod==3 || $mod==4){
      next;
    }
  }
  close FASTQ;
  close FASTA;

  mkdir(dirname($fasta)) if(!-d dirname($fasta));
  system("mv -v $fasta.tmp $fasta"); die if $?;
}

sub sha256sum{
  my ($file)=@_;
  my $checksum=`sha256sum $file`;
  die "ERROR with checksum for $file" if $?;
  chomp($checksum);
  $checksum=~s/\s+.*$//; # remove the filename
  return $checksum;
}

sub usage{
  "Reads a standard dataset spreadsheet and downloads its data
  Usage: $0 -o outdir spreadsheet.dataset.tsv
  PARAM        DEFAULT  DESCRIPTION
  --format     tsv      The input format. Default: tsv. No other format
                        is accepted at this time.
  --layout     onedir   onedir   - everything goes into one directory
                        byrun    - each genome run gets its separate directory
                        byformat - fastq files to one dir, assembly to another, etc
  --shuffled   <NONE>   Output the reads as interleaved instead of individual
                        forward and reverse files.
  --fasta      <NONE>   Convert all fastq.gz files to fasta
  "
}

