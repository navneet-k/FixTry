#!/bin/perl -w

use strict;

my (@opts, $only, $stream, $mtype, $skip_multi_line, $field_wise, $do_cksum);

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
        } elsif ($1 eq 'C') {
            $do_cksum = 1;
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
    if ($do_cksum) {
        calc_cksum($msg[$i]);
    } elsif ($field_wise) {
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

sub calc_cksum {
    my ($msg) = @_;

    die "failed <<$msg>>"unless $msg =~ /^((8=.*?${A}9=(\d+)${A}).*${A})(10=(.*)${A})/s;
    my ($m, $h, $l, $t10, $t) = ($1, $2, $3, $4, $5);
    print join "\n", $m, $h, $l, $t, "";
    print "$msg\n";

    my $num = 0;
    for my $c (unpack "C*", $m) {
        #print "<$c> - " . chr($c) . "\n";
        $num += $c;
    }

    my $xlen = length($msg);
    my $hlen = length($h);
    my $t10len = length($t10);
    my $sum = $num % 256;
    my $len = $xlen - $hlen - $t10len;
    print "checksum status - " . ($sum != $t ? "failed" : "ok") . " len chk - " . ($l eq $len ? "ok" : "failed") . "  - $t/$sum - $l/$len - $xlen - $hlen - $t10len\n";
}
