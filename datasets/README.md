Introduction to datasets
========================

* All filenames are named after the outbreak in the filename, or its main feature that binds the genomes together
* All datasets are in tab-separated values (TSV) format.  However, many people might create their spreadsheet in Excel format.  If contributing a dataset, please convert to TSV via the Excel "save as..." interface.  Or, on the command line: https://github.com/dilshod/xlsx2csv
* Datasets are a more rigid format which contain information on the dataset itself and also an inline table beginning with a header.

Metadata
--------
* This section is in a two-column key/value format
* Necessary fields: organism, outbreak, pmid, tree, source, dataType

Accessions
----------
* This section shows necessary accessions for acquiring genomes.
* Necessary fields: biosample_acc, strain, genbankAssembly, SRArun_acc, outbreak, dataSetName, suggestedReference, sha256sumAssembly, sha256sumRead1, sha256sumRead2

