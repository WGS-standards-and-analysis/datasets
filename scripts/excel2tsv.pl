#!/usr/bin/env perl


use strict;
no warnings 'utf8';  #hides 'Wide character in print' error


die usage() if(@ARGV<1);
my $file = $ARGV[0];
$file =~ s{\.[^.]+$}{};

if($ARGV[0] =~ /\.xls$/i){
    use Spreadsheet::ParseExcel;

    my $parser = Spreadsheet::ParseExcel -> new();
    my $workbook = $parser -> parse($ARGV[0]);
    if(!defined $workbook){
        die $parser -> error(), ".\n";
    }

    for my $sheet($workbook -> worksheets()){
        my $sheetName = $sheet -> get_name();
        my $filename = ">$file"."_$sheetName.tsv";
        my($row_min,$row_max)=$sheet -> row_range();
        my($col_min,$col_max)=$sheet -> col_range();
        open(OUTFILE,$filename);
        for my $row ($row_min .. $row_max){
            my @values;
            for my $col ($col_min .. $col_max){
                my $cell = $sheet -> get_cell($row, $col);
                if(defined $cell and $cell -> value() ne ''){
                    push @values, $cell -> value();
                }
                else{
                    push @values, "\t";
                }
            }
            $" = "\t";
            print OUTFILE "@values\n";
        }
        close OUTFILE;
    }
    print "XLS converted into TSV\n";
}

elsif($ARGV[0] =~ /\.xlsx$/i){
    use Spreadsheet::XLSX;

    my $workbook = Spreadsheet::XLSX -> new ($ARGV[0]);
    foreach my $sheet (@{$workbook -> {Worksheet}}){
        my $sheetName = $sheet->{Name};
        my $filename = ">$file"."_$sheetName.tsv";
        open(OUTFILE,$filename);
        $sheet -> {MaxRow} ||= $sheet -> {MinRow};    
        foreach my $row ($sheet -> {MinRow} .. $sheet -> {MaxRow}){             
            $sheet -> {MaxCol} ||= $sheet -> {MinCol};                
            foreach my $col ($sheet -> {MinCol} .. $sheet -> {MaxCol}){
                my $cell = $sheet -> {Cells} [$row] [$col];                
                if($cell){
                    print OUTFILE $cell -> {Val}, "\t";
                }
                else{
                    print OUTFILE "\t\t";
                }
            }
            print OUTFILE "\n";
        }
    }
    print "XLSX converted into TSV\n";
}

else{
    print "ERROR: unsupported extension\n";
    print "This script requires a XLS or XLSX extension\n\n";
    usage();
}

sub usage{
"Converts a Microsoft Excel spreadsheet into TSV format.
Output is automatically created in same directory as the input.
Each worksheet is written as a separate file.

usage: $0 <inputfile>
";
}
