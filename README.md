# datasets
Benchmark datasets for WGS analysis.  See datasets/NOTES.md for more details.

To run, you need a dataset in tsv format.  Here is the usage statement:

    Reads a standard dataset spreadsheet and downloads its data
      Usage: downloadDataset.pl -o outdir spreadsheet.dataset.tsv
      PARAM        DEFAULT  DESCRIPTION
      --format     tsv      The input format. Default: tsv. No other format
                            is accepted at this time.
      --layout     onedir   onedir   - everything goes into one directory
                            byrun    - each genome run gets its separate directory
                            byformat - fastq files to one dir, assembly to another, etc
      --shuffled   <NONE>   Output the reads as interleaved instead of individual
                            forward and reverse files.
      --fasta      <NONE>   Convert all fastq.gz files to fasta

