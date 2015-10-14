#!/bin/bash

# Use LibreOffice to convert from xlsx

if [ $# -eq 0 ]; then
  echo "Usage: $0 in.xlsx out.tsv";
  exit 1;
fi;

IN=$1
OUT=$2

ssconvert --export-type="Gnumeric_stf:stf_assistant" --export-options="eol=unix separator='	'" "$IN" "$OUT"
if [ $? -gt 0 ]; then 
  echo "ERROR with ssconvert program. Do you have LibreOffice installed?";
  exit 1;
fi;
