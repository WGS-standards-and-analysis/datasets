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
      # trim whitespace on fields
      for(values(%F)){
        next if(!$_);
        $_=~s/^\s+|\s+$//g;
      }

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
        }elsif($$settings{layout} eq 'byformat'){
          $$d{$F{srarun_acc}}{to}=["$$settings{outdir}/reads/$F{strain}_1.fastq.gz","$$settings{outdir}/reads/$F{strain}_2.fastq.gz"];
        }
      }

      # GenBank download command
      if($F{genbankassembly}){
        $$d{$F{genbankassembly}}{download} ="esearch -db assembly -query '$F{genbankassembly} NOT refseq[filter]' | elink -related -target nuccore > $tmpdir/edirect.xml && ";
        $$d{$F{genbankassembly}}{download}.="cat $tmpdir/edirect.xml | efetch -format gbwithparts > $tmpdir/$F{genbankassembly}.gbk && ";
        $$d{$F{genbankassembly}}{download}.="cat $tmpdir/edirect.xml | efetch -format fasta       > $tmpdir/$F{genbankassembly}.fasta";

        $$d{$F{genbankassembly}}{name}=$F{strain} || die "ERROR: $F{genbankassembly} does not have a strain name!";
        $$d{$F{genbankassembly}}{type}="genbank";
        $$d{$F{genbankassembly}}{tempdir}=$tmpdir;

        # Files will be listed as from=>to, and they will have checksums
        $$d{$F{genbankassembly}}{from}=["$tmpdir/$F{genbankassembly}.gbk","$tmpdir/$F{genbankassembly}.fasta"];
        $$d{$F{genbankassembly}}{to}=["$$settings{outdir}/$F{strain}.gbk","$$settings{outdir}/$F{strain}.fasta"];
        $$d{$F{genbankassembly}}{checksum}=[$F{sha256sumassembly},"-"];

        $$d{$F{genbankassembly}}{$_} = $F{$_} for(qw(suggestedreference outbreak datasetname));
        if($$settings{layout} eq 'byrun'){
          $$d{$F{genbankassembly}}{to}=["$$settings{outdir}/$F{strain}.gbk","$$settings{outdir}/$F{strain}.fasta"];
        }elsif($$settings{layout} eq 'byformat'){
          $$d{$F{genbankassembly}}{to}=["$$settings{outdir}/genbank/$F{strain}.gbk","$$settings{outdir}/genbank/$F{strain}.fasta"];
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
      $value||="";            # in case of blank values
      $value=~s/^\s+|\s+$//g; # trim whitespace
      $value=~s/\s+/_/g;      # turn whitespace into underscores
      $$d{$key}=$value;
    }

  }
  close TSV;

  ## Any other misc thing to download
  # Start-up variables
  my $miscTempdir=tempdir("$0XXXXXX",TMPDIR=>1,CLEANUP=>1);
  my $miscBasename=join("__",$$d{organism},$$d{outbreak});
  my $miscPrefix="$miscTempdir/$miscBasename";

  # Tree: currently it is set up like $$d{tree}="http://"
  my $treeUrl=$$d{tree};
  delete($$d{tree});
  $$d{tree}={
    download=>"wget -O $miscPrefix.dnd '$treeUrl'",
    type=>"tree",
    checksum=>["-"],
    from=>["$miscPrefix.dnd"],
    to=>["$$settings{outdir}/$miscBasename.dnd"],
    tempdir=>$miscTempdir,
    name=>"tree",
  };

  # Also load up the dataset information
  $$d{information}={
    download=>"echo -e \"downloadedWith\t$scriptInvocation\" > $miscPrefix.dataset.tsv && cat $tsv >> $miscPrefix.dataset.tsv",
    type=>"spreadsheet",
    checksum=>["-"],
    from=>["$miscPrefix.dataset.tsv"],
    to=>["$$settings{outdir}/$miscBasename.dataset.tsv"],
    tempdir=>$miscTempdir,
    name=>"spreadsheet",
  };

  return $d;
}

sub downloadEverything{
  my($d,$settings)=@_;

  # Read each entry one at a time.  Each entry is a hash
  # consisting of: type, name, download, tempdir.
  while(my($key,$value)=each(%$d)){
    # Skip blank values
    next if($key eq "" || $key=~/^(\-|NA|N\/A)$/);

    # Only download entries which are hash values and which have a download command
    next if(ref($value) ne "HASH" || !defined($$value{download}));

    # Get some local variables to make it more readable downstream
    my($type,$name,$download,$tempdir)=($$value{type},$$value{name},$$value{download},$$value{tempdir});
    #logmsg "DEBUG"; next if(!defined($type) || $type ne 'tree');
    if($$settings{only}){
      next if(!defined($type));
      next if($type ne $$settings{only});
    }

    # Skip this download if the target files exist
    my $numFiles=scalar(@{$$value{from}});
    my $i_can_skip=1; # true until proven false
    for(my $i=0;$i<$numFiles;$i++){
      my $to=$$value{to}[$i];
      my $checksum=$$value{checksum}[$i] || "";

      # I cannot skip this download if:
      #   1) The file doesn't exist yet OR
      #   2) The checksum doesn't match
      $i_can_skip=0 if(!-e $to || (defined($checksum) && sha256sum($to) ne $checksum));
    }
    if($i_can_skip){
      logmsg "I found the files for $name/$type and so I can skip this download";
    }

    # Perform the download unless given permission to skip it
    #logmsg "DEBUG"; $i_can_skip=1;
    if(!$i_can_skip){
      logmsg "Downloading $name/$type to $tempdir";
      logmsg "    $download" if($$settings{verbose});
      system($download);
      die "ERROR downloading with command\n  $download" if $?;
    }
      
    # Move the files according to how the download entry states.
    for(my $i=0;$i<$numFiles;$i++){
      my($from,$to,$checksum)=($$value{from}[$i],$$value{to}[$i],$$value{checksum}[$i]);
      $checksum||="";

      if(!$i_can_skip){
        logmsg "$from => $to  ($checksum)";
        mkdir(dirname($to)) if(!-d dirname($to));
        system("mv -v $from $to") if(!$i_can_skip);
        die "ERROR moving $from to $to" if $?;
      }

      # See if the file downloaded.  Produce a warning if:
      #   1) checksum is present AND
      #   2) checksum is not the same as in the spreadsheet
      my $calculatedChecksum=sha256sum($to);
      # Checksum is not present if the cell is blank, has a dash, or has N/A or NA
      if(!defined($checksum) || $checksum=~/^\-+|NA|N\/A$/i){
        logmsg "WARNING: checksum was not defined for $to";
      } elsif ($calculatedChecksum ne $checksum){
        logmsg "WARNING: the checksum for the file and the checksum listed in the spreadsheet don't match!\n  spreadsheet: $checksum\n  $to: $calculatedChecksum";
      }

      # Perform any kind of post-processing after the file arrives.
      postProcessFile($to,$type,$value,$settings);
    }

    # Post-process whatever is requested on a set of files
    postProcessFileSet($value,$settings);
  }

  # I can't think of any useful return value at this time.
  return 1;
}

# Perform any kind of post processing after a file has landed
# in the destination directory.
sub postProcessFile{
  my($file,$type,$fileInfo,$settings)=@_;
  ## Any kind of special processing, after the download.

  ## Fastq file post-processing
  if($type eq 'sra'){
    # Create fasta files if requested
    if($$settings{fasta}){
      my $fasta=dirname($file)."/".basename($file,qw(.fastq.gz)).".fasta";
      fastqToFasta($file,$fasta,$settings) if(!-e $fasta);
    }
  }

  ## GenBank file post processing
  elsif($type eq 'genbank'){
    #my $fasta=dirname($file)."/".basename($file,qw(.gbk .gb)).".fasta";
    #genbankToFasta($file,$fasta,$settings) if(!-e $fasta);
  }
}

sub postProcessFileSet{
  my($fileInfo,$settings)=@_;
  ## SRA files
  #    1. shuffle reads
  if($$fileInfo{type} eq 'sra'){
    my $shuffled=dirname($$fileInfo{to}[0])."/".basename($$fileInfo{to}[0],qw(_1.fastq.gz)).".shuffled.fastq.gz";
    # Shuffle the reads if the user wants it and if the shuffled file isn't already there
    if($$settings{shuffled} && !-e $shuffled){
      shuffleFastqGz($$fileInfo{to}[0],$$fileInfo{to}[1],$shuffled,$settings);
    }
  } 
  ## Genbank files
  #    Nothing to do right now that can't be done under postProcessFile()
  elsif($$fileInfo{type} eq 'genbank'){
    
  }
}

########################
## utility subroutines
########################

# Convert a genbank to a fasta file
sub genbankToFasta{
  my($genbank,$fasta,$settings)=@_;
  die "Deprecated";
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

# Shuffle two fastq.gz files
sub shuffleFastqGz{
  my($file1,$file2,$shuffled,$settings)=@_;
  my ($tmpFh,$tmpfile)=tempfile("XXXXXX",TMPDIR=>1,CLEANUP=>1,SUFFIX=>".fastq");
  logmsg "Shuffling $file1 and $file2 into $tmpfile, and then moving to $shuffled";
  open(R1,"gunzip -c $file1 | ") or die "ERROR: could not open $file1 for reading: $!";
  open(R2,"gunzip -c $file2 | ") or die "ERROR: could not open $file2 for reading: $!";
  while(my $line=<R1>){
    # Print read 1
    print $tmpFh $line;
    for(1..3){
      $line=<R1>;
      print $tmpFh $line;
    }
    # Print read 2
    for(1..4){
      $line=<R2>;
      print $tmpFh $line;
    }
  }
  close R1; close R2;
  close $tmpFh; # close it only after being totally done with it
  
  # Gzip into the correct file and then remove the tmpfile
  system("gzip -v $tmpfile && mv -v $tmpfile.gz $shuffled");
  die "ERROR: could not gzip $tmpfile into $shuffled" if $?;
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

