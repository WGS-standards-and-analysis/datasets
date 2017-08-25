#!/bin/sh

#
# gbk2fas.sed -- Sed script to convert Genbank to Fasta format. Tested
#   with GNU sed 4.1.4 and minised 1.9
#
# (C) 2006 by
#     Markus Goeker (markus.goeker@uni-tuebingen.de)
#
# This program is distributed under the terms of the Gnu Public License V2.
# For further information, see http://www.gnu.org/licenses/gpl.html
#
# If you happen to use this script in a publication, please cite the web
# page at http://www.goeker.org/scripts/
#

exec sed -f - -- "$@" <<'EOF'

/^ *ACCESSION/ {
  s/^ *ACCESSION \+//
  h
}

/^ *ORGANISM/ {
  s/^ *ORGANISM \+/>/
  G
  s/[^-A-Za-z0-9_.]\+/_/g
  s/^_/>/
  p
}

/^ *ORIGIN/,/^ *\/\// {
  /^ \+[0-9]\+ \+/ {
    s/[^A-Za-z]\+//g
    p
  }
}

d

EOF
