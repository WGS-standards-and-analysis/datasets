#!/bin/bash

function logmsg(){
  print $1 >&2
}

READS=$1

IS_GZIP=$(file $READS| grep gzip)

if [ "$IS_GZIP" == "" ]; then
  CAT="cat"
else
  CAT="zcat"
fi

# 1. cat the file to perl
# 2. keep only the seq and qual
# 3. sort
# 4. sha256sum
# 5. remove any whitespace and the dash from the sha256sum stdin printout
CHECKSUM=$($CAT $READS |\
            perl -e 'while(<>){$seq=<>; <>; $qual=<>; print "$seq$qual";}' |\
            sort | sha256sum |\
            perl -lane 's/^\s+|\s+$//; s/\s+.*$//; print;'
          );

echo -e "$READS\t$CHECKSUM";
