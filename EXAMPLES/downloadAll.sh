#!/bin/bash

NUMCPUS=12

set -e

THISDIR=$(dirname $0)

export PATH="$THISDIR/../scripts:$PATH"

# Print a message to stderr with the script name
function msg(){
  echo "$(basename $0): $@" >&2
}

msg "Looking for dependencies"
for exe in esearch fastq-dump perl make GenFSGopher.pl run_snp_pipeline.sh; do
  which $exe
done
# Need perl >= 5.12.0
msg "Testing if perl >= 5.12.0 is in PATH"
perl -e 'use 5.12.0; print "  -OK\n"'

msg "Downloading datasets"
for tsv in $THISDIR/../datasets/*.tsv; do
  name=$(basename $tsv .tsv)
  msg "Downloading $name"
  GenFSGopher.pl --outdir $THISDIR/$name --layout cfsan --numcpus $NUMCPUS $tsv 

  msg "SNP-Pipeline"
  SNP_CONF="$THISDIR/$name/snppipeline.conf"
  copy_snppipeline_data.py configurationFile $THISDIR/$name

  REF=$(ls $THISDIR/$name/reference/*.fasta | head -n 1)
  nice run_snp_pipeline.sh -c $SNP_CONF -s $THISDIR/$name/samples -m soft -o $THISDIR/$name/snp-pipeline $REF

done


# Compare vs original tree?
