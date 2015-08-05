#!/usr/bin/env perl

# run_assembly_readMetrics.pl: puts out metrics for a raw reads file
# Author: Lee Katz <lkatz@cdc.gov>
# Modified for the WGS standards and analysis group

package PipelineRunner;
my ($VERSION) = ('$Id: $' =~ /,v\s+(\d+\S+)/o);

my $settings = {
    appname => 'cgpipeline',
    # these are the subroutines for all read metrics
    metrics=>[qw(avgReadLength totalBases maxReadLength minReadLength avgQuality numReads)],
};

use strict;
no strict "refs";
use FindBin;
use lib "$FindBin::RealBin/../lib";
$ENV{PATH} = "$FindBin::RealBin:".$ENV{PATH};

use Getopt::Long;
use File::Temp ('tempdir');
use File::Path;
use File::Spec;
use File::Copy;
use File::Basename qw/fileparse basename dirname/;
use List::Util qw(min max sum shuffle);
use Data::Dumper;
use Statistics::Descriptive;

use threads;
use Thread::Queue;

my @fastaExt=qw(.fasta .fa .mfa .fas .fna);
my @fastqExt=qw(.fastq .fq .fastq.gz .fq.gz);
my @sffExt=qw(.sff);
my @samExt=qw(.sam .bam);
local $SIG{'__DIE__'} = sub {local $0 = basename $0; my $e = $_[0]; $e =~ s/(at [^\s]+? line \d+\.$)/\nStopped $1/; die("$0: ".(caller(1))[3].": ".$e); };

sub logmsg {local $0 = basename $0; print STDERR "$0: ".(caller(1))[3].": @_\n";}

exit(main());

sub main() {
  #$settings = AKUtils::loadConfig($settings);
  die(usage($settings)) if @ARGV<1;

  my @cmd_options=qw(help fast qual_offset=i minLength=i numcpus=i expectedGenomeSize=s histogram tempdir=s);
  GetOptions($settings, @cmd_options) or die;
  die usage() if($$settings{help});
  die "ERROR: need reads file\n".usage() if(@ARGV<1);
  $$settings{qual_offset}||=33;
  $$settings{numcpus}||=1;
  $$settings{tempdir}||=tempdir("XXXXXX",CLEANUP=>1,TEMPDIR=>1);
  $$settings{bufferSize}||=100000;
  $$settings{minLength}||=1; # minimum length to consider a read for metrics
  # the sample frequency is 100% by default or 1% if "fast"
  $$settings{sampleFrequency} ||= ($$settings{fast})?0.01:1;
  $$settings{qualThreshold} ||= 20; # for calculating the read score

  # Print the header
  print join("\t",qw(File avgReadLength totalBases minReadLength maxReadLength avgQuality numReads PE? coverage readScore medianFragmentLength))."\n";

  # Get metrics for each file. The subroutine in the loop
  # must print values pertaining to the header.
  for my $input_file(@ARGV){
    printReadMetricsFromFile($input_file,$settings);
  }

  return 0;
}

# main subroutine to print the metrics from a raw reads file
sub printReadMetricsFromFile{
  my($file,$settings)=@_;
  my($basename,$dirname,$ext)=fileparse($file,(@fastaExt,@fastqExt, @sffExt, @samExt));
  # start the queue and threads
  my $Q=Thread::Queue->new();
  my @thr;
  $thr[$_]=threads->new(\&readMetrics,$Q,$settings) for(0..$$settings{numcpus}-1);

  # Put the reads into the queue in different ways depending on the format.
  my $numEntries=0;
  if(grep(/$ext/,@fastqExt)){
    $numEntries=readFastq($file,$Q,$settings);
  } elsif(grep(/$ext/,@fastaExt)) {
    $numEntries=readFasta($file,$Q,$settings);
  } elsif(grep(/$ext/,@sffExt)){
    $numEntries=readSff($file,$Q,$settings);
  } elsif(grep(/$ext/,@samExt)) {
    $numEntries=readSam($file,$Q,$settings);
  } else {
    die "Could not understand filetype $ext";
  }

  # Avoid zero-read errors
  if($numEntries<1){
    logmsg "WARNING: there were no reads in $file. Moving on...\n";
    next;
  }

  # Combine the threads
  my %count=(minReadLength=>1e999); # need a min length to avoid a bug later
  $Q->enqueue(undef) for(@thr);
  for(@thr){
    my $c=$_->join;
    $count{numBases}+=$$c{numBases};
    $count{numReads}+=$$c{numReads};
    $count{qualSum} +=$$c{qualSum};
    $count{maxReadLength}=max($$c{maxReadLength},$count{maxReadLength});
    $count{minReadLength}=min($$c{minReadLength},$count{minReadLength});
    push(@{$count{tlen}},@{$$c{tlen}});
    push(@{$count{readLength}},@{$$c{readLength}});
    push(@{$count{readQuality}},@{$$c{readQuality}});
  }

  # extrapolate the counts to the total number of reads if --fast
  my $fractionReadsRead=$count{numReads}/$numEntries;
  $count{numReads}=$numEntries;
  $count{extrapolatedNumBases}=int($count{numBases}/$fractionReadsRead);
  $count{extrapolatedNumReads}=int($count{numReads}*$fractionReadsRead);

  # derive some more values
  my $avgQual=round($count{qualSum}/$count{numBases});
  $count{avgReadLength}=round($count{numBases}/$count{extrapolatedNumReads});
  #my $isPE=(AKUtils::is_fastqPE($file))?"yes":"no";
  my $isPE='.';
  my $medianFragLen='.';
  if(grep(/$ext/,@samExt)){
    # Bam files are PE if they have at least some fragment sizes.
    # See if tlen is present so that it can be calculated.
    my $isPE=(@{$count{tlen}} > 10)?"yes":"no"; 
    if($isPE eq 'yes'){
      my $tlenStats=Statistics::Descriptive::Full->new;
      $tlenStats->add_data(@{$count{tlen}});
      my $tlen25=$tlenStats->percentile(25);
      my $tlen50=$tlenStats->percentile(50);
      my $tlen75=$tlenStats->percentile(75);
      $medianFragLen="$tlen50\[$tlen25,$tlen75]";
    }
  }

  # coverage is bases divided by the genome size
  $count{coverage}=($$settings{expectedGenomeSize})?round($count{extrapolatedNumBases}/$$settings{expectedGenomeSize}):'.';

  # calculate a read score
  my $readScore=readScore(\%count,$settings);

  # Print the metrics for this read set
  print join("\t",$file,$count{avgReadLength},$count{extrapolatedNumBases},$count{minReadLength},$count{maxReadLength},$avgQual,$count{numReads},$isPE,$count{coverage},$readScore,$medianFragLen)."\n";

  printHistogram($count{readLength},$fractionReadsRead,$settings) if($$settings{histogram});

  return \%count;
}

sub readScore{
  my($count,$settings)=@_;

  # Three dimensions to the read score: quality, read length, coverage

  my @hqReads=();
  my $qualThreshold=$$settings{qualThreshold} || 10;
  # Quality: disregard low-qual reads
  my $numReads=scalar(@{ $$count{readLength} });
  my $hqBases=0;
  my $extrapolatingReps=1;
     $extrapolatingReps=100 if($$settings{fast});
  for(my $i=0;$i<$numReads;$i++){
    next if($$count{readQuality} < $qualThreshold);
    # If 99% of the reads were not considered earlier, then they need to be counted now.
    for(my $j=0;$j<$extrapolatingReps;$j++){
      push(@hqReads,$$count{readLength}[$i]);
      $hqBases+=$$count{readLength}[$i];
    }
  }

  # Coverage
  my $coverage=1;
     $coverage=$hqBases/$$settings{expectedGenomeSize} if($$settings{expectedGenomeSize});

  # Read length:
  # Read advantage is how many bases over 100 the read set is
  $$count{readAdvantage}=$$count{avgReadLength}-100;
  $$count{readAdvantage}=1 if($$count{readAdvantage}<1);

  # The score is coverage * readAdvantage
  my $score=round($coverage * $$count{readAdvantage});
  return $score;
}

sub printHistogram{
  my($data,$coefficient,$settings)=@_;
  my @data=map(int($_/100)*100,@$data);
  my $numData=@data;
  my %count;
  for(@data){
    $count{$_}++;
  }
  #$sum=int($sum / $coefficient);
  #print Dumper \%count;die;
  for my $datum(sort {$a<=>$b} keys(%count)){
    print join("\t",$datum,$count{$datum},round($count{$datum}/$numData))."\n";
  }
  print join("\t","total",$numData,'.')."\n";
  return \%count;
}

# Reads a Thread::Queue to give metrics but does not derive any metrics, e.g. avg quality
sub readMetrics{
  my($Q,$settings)=@_;
  my $qual_offset=$$settings{qual_offset} || die "Internal error";
  my %count;
  my $minReadLength=1e999;
  my $maxReadLength=0;
  my @length;
  my @readQuality;
  my @tlen; # fragment length
  while(defined(my $tmp=$Q->dequeue)){
    my($seq,$qual,$tlen)=@$tmp;
    # trim and chomp
    $seq =~s/^\s+|\s+$//g;
    $qual=~s/^\s+|\s+$//g;
    my $readLength=length($seq);
    next if($readLength<$$settings{minLength});
    push(@length,$readLength);
    $count{numBases}+=$readLength;
    if($readLength<$minReadLength){
      $minReadLength=$readLength;
    } elsif ($readLength>$maxReadLength){
      $maxReadLength=$readLength;
    }
    $count{numReads}++;

    $tlen||=0;
    push(@tlen,$tlen) if($tlen>0);

    # quality metrics
    my @qual;
    if($qual=~/\s/){ # if it is numbers separated by spaces
      @qual=split /\s+/,$qual;
    } else {         # otherwise, encoded quality
      @qual=map(ord($_)-$qual_offset, split(//,$qual));
    }
    $count{qualSum}+=sum(@qual);
    push(@readQuality,sum(@qual)/@qual);
  }
  $count{minReadLength}=$minReadLength;
  $count{maxReadLength}=$maxReadLength;
  $count{readLength}=\@length;
  $count{tlen}=\@tlen;
  $count{readQuality}=\@readQuality;
  return \%count;
}

sub readFastq{
  my($file,$Q,$settings)=@_;
  my($basename,$dirname,$ext)=fileparse($file,(@fastaExt,@fastqExt, @sffExt));
  my $fp;
  if($ext=~/\.gz/){
    open($fp,"gunzip -c $file |") or die "Could not open $file:$!";
  } else {
    open($fp,$file) or die "Could not open fastq $file:$!";
  }

  # read the first one so that there is definitely going to be at least one read in the results
  my $bufferSize=$$settings{bufferSize};
  <$fp>; my $firstSeq=<$fp>; <$fp>; my $firstQual=<$fp>;
  my @queueBuffer=([$firstSeq,$firstQual]);
  my $numEntries=1;
  while(<$fp>){
    $numEntries++;
    my $seq=<$fp>;
    <$fp>; # burn the "plus" line
    my $qual=<$fp>;
    push(@queueBuffer,[$seq,$qual]) if(rand() <= $$settings{sampleFrequency});
    next if($numEntries % $bufferSize !=0);
    # Don't process the buffer until it is full

    # flush the buffer
    $Q->enqueue(@queueBuffer);
    @queueBuffer=();

    my $pending=$Q->pending;
    # pause if the queue is too full
    while($pending > $bufferSize * 3){
      sleep 1;
      $pending=$Q->pending;
    }
    # Increase the buffer size if the buffer gets emptied too fast.
    if($pending < $bufferSize && $numEntries > $bufferSize){
      $bufferSize*=2; # double the buffer size then
    }
  }
  $Q->enqueue(@queueBuffer);
  close $fp;
  return $numEntries;
}

sub readSff{
  my($file,$Q,$settings)=@_;
  my($basename,$dirname,$ext)=fileparse($file,(@fastaExt,@fastqExt, @sffExt));

  local $/="\n>";
  open(FNA,"sffinfo -s $file | ") or die "Could not open $file:$!";
  open(QUAL,"sffinfo -q $file | ") or die "Could not open $file:$!";
  my @queueBuffer;
  my $bufferSize=$$settings{bufferSize};
  <FNA>; my $firstSeq=<FNA>; <QUAL>; my $firstQual=<QUAL>;
  my @queueBuffer=([$firstSeq,$firstQual]);
  my $numEntries=1;
  while(my $defline=<FNA>){
    $numEntries++;
    <QUAL>; # burn the qual defline because it is the same as the fna
    my $seq=<FNA>;
    my $qual=<QUAL>;
    push(@queueBuffer,[$seq,$qual]);
    next if($numEntries % $bufferSize !=0);
    # Don't process the buffer until it is full

    # flush the buffer
    $Q->enqueue(@queueBuffer);
    @queueBuffer=();
    if($$settings{fast} && $numEntries>$bufferSize){
      while(<FNA>){
        $numEntries++; # count the rest of the reads
      }
      last;
    }
    # pause if the queue is too full
    while($Q->pending > $bufferSize * 3){
      sleep 1;
    }
  }
  $Q->enqueue(@queueBuffer);
  close QUAL; close FNA;

  return $numEntries;
}

sub readFasta{
  my($file,$Q,$settings)=@_;
  my($basename,$dirname,$ext)=fileparse($file,(@fastaExt,@fastqExt, @sffExt));

  local $/="\n>";
  open(FNA,$file) or die "Could not open $file:$!";
  open(QUAL,"$file.qual") or warn "WARNING: Could not open qual $file.qual:$!";
  my @queueBuffer;
  my $numEntries=0;
  my $bufferSize=$$settings{bufferSize};
  while(my $defline=<FNA>){
    $numEntries++;
    <QUAL>; # burn the qual defline because it is the same as the fna
    my $seq=<FNA>;
    my $qual=<QUAL> || "";
    push(@queueBuffer,[$seq,$qual]);
    next if($numEntries % $bufferSize !=0);
    # Don't process the buffer until it is full

    # flush the buffer
    $Q->enqueue(@queueBuffer);
    @queueBuffer=();
    if($$settings{fast} && $numEntries>$bufferSize){
      while(<FNA>){
        $numEntries++; # count the rest of the reads
      }
      last;
    }
    # pause if the queue is too full
    while($Q->pending > $bufferSize * 3){
      sleep 1;
    }
  }
  $Q->enqueue(@queueBuffer);
  close FNA; close QUAL;

  return $numEntries;
}

sub readSam{
  my($file,$Q,$settings)=@_;
  my($basename,$dir,$ext)=fileparse($file,@samExt);
  if($ext=~/sam/){
    open(SAM,$file) or die "ERROR: I could not read $file: $!";
  } elsif($ext=~/bam/){
    open(SAM,"samtools view $file | ") or die "ERROR: I could not use samtools to read $file: $!";
  } else {
    die "ERROR: I do not know how to read the $ext extension in $file";
  }

  my $bufferSize=$$settings{bufferSize};
  my $firstLine=<SAM>;
  my(undef,undef,undef,undef,undef,undef,undef,undef,$firstTlen,$firstSeq,$firstQual)=split /\t/,$firstLine;
  my @queueBuffer=([$firstSeq,$firstQual,$firstTlen]);
  my $numEntries=1;
  while(<SAM>){
    next if(/^@/);
    chomp;
    my($qname,$flag,$rname,$pos,$mapq,$cigar,$rnext,$pnext,$tlen,$seq,$qual)=split /\t/;
    #push(@queueBuffer,[$seq,$qual,$tlen]) if(rand() <= 0.1);
    push(@queueBuffer,[$seq,$qual,$tlen]) if(rand() <= $$settings{sampleFrequency});
    next if(++$numEntries % $bufferSize !=0);
    #print Dumper \@queueBuffer;die;
    
    $Q->enqueue(@queueBuffer);
    @queueBuffer=();

    while($Q->pending > $bufferSize * 3){
      sleep 1;
    }
  }
  $Q->enqueue(@queueBuffer);
  close SAM;
  
  return $numEntries;
}

# Truncate to the hundreds place.
# Yes I understand it's not technically rounding.
sub round{
  my ($num)=(@_);
  my $rounded=int($num*100)/100;
  return sprintf("%.2f",$rounded); # put in zero padding in case it truncates at a zero in the hundreds place
}

sub usage{
  my ($settings)=@_;
  "Prints useful assembly statistics
  Usage: $0 reads.fasta 
         $0 reads.fasta | column -t
    A reads file can be fasta, sff, or fastq
    The quality file for a fasta file reads.fasta is assumed to be reads.fasta.qual
  --fast for fast mode: samples 1% of the reads and extrapolates
  -n 1 to specify the number of cpus (default: all cpus)
  --qual_offset 33
    Set the quality score offset (usually it's 33, so the default is 33)
  --minLength 1
    Set the minimum read length used for calculations
  -e 4000000 expected genome size, in bp
  --hist to generate a histogram of the reads
  "
}
