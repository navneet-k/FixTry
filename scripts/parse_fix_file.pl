#!/bin/perl -w

use strict;

my (@opts, $only, $stream, $mtype, $skip_multi_line, $field_wise);

while(@ARGV) {
    my $a = shift @ARGV;
    if ($a =~ /^-(\S+)/) {
        if ($1 eq 'm') {
            $only = shift @ARGV;
        } elsif ($1 eq 't') {
            $mtype = shift @ARGV;
        } elsif ($1 eq 's') {
            $stream = 1;
        } elsif ($1 eq 'S') {
            $skip_multi_line = 1;
        } elsif ($1 eq 'F') {
            $field_wise = 1;
        } else {
            die "unsupported opt(-$1)";
        }
    } else {
        push @opts, $a;
    }
}

@ARGV = @opts;

my $data = join "", <>;

my $M = chr(13);
$data =~ s/$M//sg;

#print "$data";
my $A = chr(1);

my @msg = ($data =~ /\b(8=.*?${A}10=\d+${A})/sg);

if (defined $mtype) {
    @msg = grep { /\b35=($mtype)${A}/ } @msg;
}

if (defined $skip_multi_line) {
    @msg = grep { !/\n/s } @msg;
}

@msg = @msg[ defined $only ? eval("($only)") : 0..$#msg];

for(my $i = 0; $i <= $#msg; $i++) {
    if ($field_wise) {
        my %data = ($msg[$i] =~ /(\d+)=([^$A]*)/g);
        foreach my $k (sort { $a <=> $b } keys %data) {
            printf "%4d = %s\n", $k, $data{$k};
        }
        # my @data = ($msg[$i] =~ /(\d+)=([^$A]*)/g);
        # for(my $i = 0; $i < $#data; $i+=2) {
        #     printf "%4d = %s\n", $data[$i], $data[$i + 1];
        # }
    } else {
        print $stream ? $msg[$i] : "$msg[$i]\n";
    }
}

exit 0;
