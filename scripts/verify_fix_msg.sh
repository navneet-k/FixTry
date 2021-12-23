#!/bin/bash

DIR=$(dirname $0)

$DIR/parse_fix_file.pl -s -S -F $@ > /tmp/x1

#perl -ne 's/.*\[(\s*\d+)\](\s*=.*)/$1$2/ && print'> /tmp/x2

$DIR/ParseFixStream <($DIR/parse_fix_file.pl -s -S $@) \
    | perl -ne '
      /.*\[(\s*(\d+))\]((\s*=\s*)(.*))/ && do {
         $X{$2} = "$1$3";
         if ($2 eq 44) {
             my ($n, $f) = split "/", $5;
             my $x = sprintf("%.${f}f", $n/10**$f);
             $X{$2} = "$1$4$x";
         }
         if ($2 eq 10) {
            for my $k (sort {$a<=>$b} keys %X) {
                print "$X{$k}\n";
            }
            %X=();
         }
      }
    '> /tmp/x2

vimdiff /tmp/x1 /tmp/x2

exit 0;
