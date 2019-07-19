#!/usr/bin/env perl

# Creates a dataset spreadsheet
# 
# Author: Lee Katz <gzu2@cdc.gov>
# WGS standards and analysis group

use strict;
use warnings;
use Getopt::Long;
use Data::Dumper;
use File::Basename qw/fileparse dirname basename/;
use File::Temp qw/tempdir tempfile/;
use File::Spec;
use File::Copy qw/cp mv/;

use Digest::SHA qw/sha256/;

my $scriptInvocation=join(" ",$0,@ARGV);
my $scriptsDir=dirname(File::Spec->rel2abs($0));
local $0=basename $0;
sub logmsg{print STDERR "$0: @_\n";}

exit main();

sub main{
  my $settings={};
  GetOptions($settings,qw(help tempdir=s outdir=s ref|reference=s@ tree=s name=s)) or die $!;
  $$settings{name}||="dataset";
  $$settings{tempdir}||=tempdir(basename($0).".XXXXXX",TMPDIR=>1,CLEANUP=>1);
  logmsg "Temp dir is $$settings{tempdir}";

  my @biosample_acc=@ARGV;
  die usage() if(!@biosample_acc || $$settings{help});

  # Check execs in the path
  for(qw(esearch elink efetch xtract fastq-dump)){
    system("which $_ > /dev/null");
    die if $?;
  }

  my $tsv=createSpreadsheet(\@biosample_acc,$settings);

  print $tsv;

  return 0;
}

sub createSpreadsheet{
  my($biosample_acc,$settings)=@_;

  my $tsvString="";

  $tsvString.=spreadsheetHeader($settings);

  $tsvString.="\n";

  $tsvString.=addSamples($biosample_acc,$settings);

  return $tsvString;
}

sub spreadsheetHeader{
  my($settings)=@_;

  my $header="";
  
  my %header=(
    Organism  =>  "missing",
    Outbreak  =>  "missing",
    pmid      =>  "missing",
    tree      =>  "http://",
    source    =>  "missing",
    dataType  =>  "missing",
  );

  while(my($key,$value)=each(%header)){
    $header.= join("\t",$key,$value)."\n";
  }

  return $header;
}

sub addSamples{
  my($biosample_acc,$settings)=@_;

  my @header=qw(biosample_acc strain genBankAssembly SRArun_acc outbreak dataSetName suggestedReference sha256sumAssembly sha256sumRead1 sha256sumRead2);
  
  my @sample; # array of sample hashes

  for(my $i=0;$i<@$biosample_acc;$i++){
    mkdir "$$settings{tempdir}/$$biosample_acc[$i]";

    # Get biosample esearch result up front, and then parse it
    # with different subroutines
    my $biosampleSearch = biosampleSearch($$biosample_acc[$i],$settings);

    # Need to know about the existence of assemblies before
    # knowing about which are a suggested reference and to
    # determine the checksum
    my ($genBankAssembly, $sha256sumAssembly) = biosampleAssembly($biosampleSearch,$$biosample_acc[$i], $settings);

    # is this a reference genome?
    my $suggestedReference=suggestedReference($genBankAssembly,$$biosample_acc[$i],\@sample,$settings);
    # Need to know the SRA before knowing the checksum
    my($sraDir, $sha256sumRead1, $sha256sumRead2, $SRArun_acc)=biosampleSra($biosampleSearch, $$biosample_acc[$i], $settings);

    my %sam=(
      biosample_acc         => $$biosample_acc[$i],
      strain                => biosampleStrain($$biosample_acc[$i],$settings),
      genBankAssembly       => $genBankAssembly, # accession
      SRArun_acc            => $SRArun_acc,
      outbreak              => biosampleOutbreak($$biosample_acc[$i],$settings),
      dataSetName           => $$settings{name},
      suggestedReference    => "FALSE",
      sha256sumAssembly     => $sha256sumAssembly,
      sha256sumRead1        => $sha256sumRead1,
      sha256sumRead2        => $sha256sumRead2,
    );
    push(@sample,\%sam);
  }

  my $samples=join("\t",@header)."\n";
  for my $s(@sample){
    for(my $i=0;$i<@header;$i++){
      $samples .= $$s{$header[$i]} ."\t";
    }
    $samples =~ s/\t$/\n/;
  }

  return $samples;
}

sub biosampleSearch{
  my($biosample_acc,$settings)=@_;

  my $esearchCommand="esearch -db biosample -query '$biosample_acc\[accn\]'";
  my $search=`$esearchCommand`; die if $?;
  chomp($search);
  return $search;
}

sub biosampleAssembly{
  my($biosampleSearch, $biosample_acc, $settings)=@_;

  my $assemblySearch = `echo '$biosampleSearch' | elink -target assembly 2>/dev/null`;
  my $assemblyId = `echo '$assemblySearch' | esummary 2>/dev/null | xtract -pattern DocumentSummary -element LastMajorReleaseAccession`;
  die if $?;
  chomp($assemblyId);
  if(! $assemblyId){
    return ("missing", "missing");
  }
  my $filename = "$$settings{tempdir}/$biosample_acc/assembly.fasta";
  system("echo '$assemblySearch' | elink -target nuccore -name assembly_nuccore_insdc 2>/dev/null | efetch -format fasta > $filename 2>/dev/null");
  return($assemblyId, checksum($filename));
}

# Checksum a file consistently across this script
sub checksum{
  my($file,$settings)=@_;
  my $sha=Digest::SHA->new("sha256");
  die "ERROR: could not checksum file $file because it doesn't exist!" if(!-e $file);
  $sha->addfile($file);
  return $sha->hexdigest;
}

sub suggestedReference{
  my($genBankAssembly,$biosample_acc,$sample,$settings)=@_;

  # It can only be a reference with an assembly, so return
  # false if there is no assembly
  if(!$genBankAssembly){
    return "FALSE";
  }

  # Return true if this sample was actually named to be
  # the reference genome
  if(defined($$settings{ref})){
    if(lc($$settings{ref}) eq lc($biosample_acc)){
      return "TRUE";
    } else {
      return "FALSE";
    }
  }

  # Ok but if no reference is named, then go
  # through all the samples. If anything is already
  # a suggested reference, then this sample should not 
  # be a suggested reference.
  for my $sam(@$sample){
    if($$sam{suggestedReference} eq "TRUE"){
      return "FALSE";
    }
  }

  return "TRUE";
}

# Download the SRA and return the filename.
# The filename should have the SRR in the name itself.
# Or should it be a second item that is returned?
sub biosampleSra{
  my($biosampleSearch, $biosample_acc, $settings)=@_;

  # Retrieve the run with the most spots (ie reads)
  logmsg "Esearch/efetch for $biosample_acc";
  my $esearchCommand="echo '$biosampleSearch' | elink -target sra | efetch -format xml | xtract -pattern EXPERIMENT_PACKAGE -block RUN -element 'RUN\@accession' -element 'RUN\@total_spots'";
  my @accAndSpots=split(/\n/,`$esearchCommand`); 
  die "ERROR with \n  $esearchCommand" if $?;

  # Sort by most number of spots. If the number of spots
  # is equal, then return the latest accession.
  @accAndSpots = sort{
    my($srrA,$spotsA)=split(/\t/,$a);
    my($srrB,$spotsB)=split(/\t/,$b);
    $_//=0 for($spotsA,$spotsB);
    return $srrB cmp $srrA if($spotsA == $spotsB);
    return $spotsA <=> $spotsB;
  } @accAndSpots;

  # Get the SRR and number of spots into their own 
  # variables.
  my($SRR,$numSpots)=split(/\t/, $accAndSpots[0]);
  chomp($SRR);
  $numSpots//=0;
  die "ERROR: could not find the SRR run ID ($SRR) from $biosample_acc. Command was \n  $esearchCommand\n" if(!$SRR);

  # Download
  my $dumpdir="$$settings{tempdir}/$biosample_acc";
  my $finishedFile="$dumpdir/.${SRR}_finished";
  if(-e $finishedFile){
    logmsg "Found $finishedFile. Not downloading again.";
    
    return ($dumpdir, 
            checksum((glob("$dumpdir/*_1.fastq.gz"))[0], $settings),
            checksum((glob("$dumpdir/*_2.fastq.gz"))[0], $settings),
            $SRR,
           );
  }
  logmsg "Fastq-dump for $biosample_acc, $SRR (numSpots: $numSpots)";
  my $seqIdTemplate='@$ac_$sn[_$rn]/$ri';
  my $downloadCommand="fastq-dump --defline-seq '$seqIdTemplate' --defline-qual '+' --split-files -O $dumpdir --gzip $SRR";
  system($downloadCommand);
  die "ERROR with \n  $downloadCommand" if $?;

  # Mark it as finished
  open(my $fh, ">$finishedFile") or die "ERROR: could not write to $finishedFile: $!";
  close $fh;

  my $R1 = (glob("$dumpdir/*_1.fastq.gz"))[0];
  my $R2 = (glob("$dumpdir/*_2.fastq.gz"))[0];
  my $checksum1 = checksum($R1, $settings);
  my $checksum2 = checksum($R2, $settings);

  return ($dumpdir, 
          $checksum1,
          $checksum2,
          $SRR,
         );
}
  
# Get the strain name for a biosample accession
sub biosampleStrain{
  my($biosample_acc,$settings)=@_;
  
  my $esearchCommand="esearch -db biosample -query $biosample_acc | efetch -format xml | xtract -format | grep '<Attribute' | grep harmonized_name=.strain";
  my $line=`$esearchCommand`;
  $line=~/>(.*)</;
  my $strain = $1 || "missing";

  if($strain eq 'missing'){
    logmsg "WARNING: $biosample_acc does not have a strain name";
  }

  return $strain;
}

# Get the outbreak code if it exists
sub biosampleOutbreak{
  my($biosample_acc,$settings)=@_;
  return "missing";
}

sub usage{
  local $0=basename($0);
  "$0: creates a spreadsheet in the datasets format
  Usage: $0 [options] SAMN123456 [SAMN123457...] > dataset.tsv
  --reference  ''  A suggested reference. Multiple reference
                   flags are allowed. If one is not provided,
                   the first assembly found will be the
                   suggested reference.
  --tree       ''  A suggested tree URL.
  --name       ''  The dataset name
  "
}

