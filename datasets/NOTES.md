Introduction to datasets
========================

* All filenames are named after the outbreak in the filename, or its main feature that binds the genomes together
* All datasets are in Excel format but must be converted to tsv before they are used.  For example, using Excel to convert to tsv or using this script from github: https://github.com/dilshod/xlsx2csv
* Datasets are a more rigid format which contain information on the dataset itself and also an inline table beginning with a header.

Metadata
--------
* This section is in a two-column key/value format
* Necessary fields: organism, outbreak, pmid, tree, source, dataType

Accessions
----------
* This section shows necessary accessions for acquiring genomes.
* Necessary fields: biosample_acc, strain, genbankAssembly, SRArun_acc, outbreak, dataSetName, suggestedReference, sha256sumAssembly, sha256sumRead1, sha256sumRead2

