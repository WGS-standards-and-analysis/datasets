# datasets
Benchmark datasets for WGS analysis.  See datasets/NOTES.md for more details.

## Downloading a dataset
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

## Creating your own dataset
To create your own dataset and to make it compatible with the existing script(s) here, please follow these instructions.  These instructions are subject to change.

1. Create a new Excel spreadsheet with only one tab. Please delete any extraneous tabs to avoid confusion.
2. The first part describes the dataset.  This is given as a two-column key/value format.  The keys are case-insensitive, but the values are case-sensitive.  The order of rows is unimportant.
  1. Organism.  Usually genus and species, but there is no hard rule at this time.
  2. Outbreak.  This is usually an outbreak code but can be some other descriptor of the dataset.
  3. pmid.  Any publications associated with this dataset should be listed as pubmed IDs.
  4. tree.  This is a URL to the newick-formatted tree.  This tree serves as a guide to future analyses.
  5. source. Where did this dataset come from?
3. Blank row - separates the two parts of the dataset
4. Header row with these names (case-insensitive): biosample_acc, strain, genbankAssembly, SRArun_acc, outbreak, dataSetName, suggestedReference, sha256sumAssembly, sha256sumRead1, sha256sumRead2
4. Accessions to the genomes for download.  Each row represents a genome and must have the following fields.  Use a dash (-) for any missing data.
  1. biosample_acc - The BioSample accession
  2. strain - Its genome name
  3. genbankAssembly - GenBank accession number
  4. SRArun_acc - SRR accession number
  5. outbreak - The name of the outbreak clade.  Usually named after an outbreak code.  If not part of an important clade, the field can be filled in using 'outgroup'
  6. dataSetName - this should be redundant with the outbreak field in the first part of the spreadsheet
  7. suggestedReference - The suggested reference genome for analysis, e.g., SNP analysis.
  8. sha256sumAssembly - A checksum for the GenBank file 
  9. sha256sumRead1 - A checksum for the first read from the SRR accession
  10. sha256sumRead2 - A checksum for the second read from the SRR accession
