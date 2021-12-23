#!/bin/perl -w

use strict;

use FindBin qw($Bin);

use XML::Parser;
use Data::Dumper;
use Carp qw<longmess>;
use POSIX;

my ($fix_xml, $out_dir) = @ARGV;
$out_dir ||= "$Bin/..";

my $COMPONENT_ID = 1;

my $parser = XML::Parser->new(Style => "Tree", ErrorContext => 2);

my $data   = $parser->parsefile($fix_xml);

#print Dumper($data);

my $type_map = { STRING     => [ "std::ptrdiff_t", "std::numeric_limits<std::ptrdiff_t>::min()" ],
                 CHAR       => [ "char",           "'\\0'" ],
                 PRICE      => [ "long", "std::numeric_limits<long>::min()" ],
                 SEQNUM     => [ "int",  "std::numeric_limits<int>::min()" ],
                 LENGTH     => [ "int",  "std::numeric_limits<int>::min()" ],
                 AMT        => [ "long", "std::numeric_limits<long>::min()" ],
                 QTY        => [ "long", "std::numeric_limits<long>::min()" ],
                 CURRENCY   => [ "std::ptrdiff_t", "std::numeric_limits<std::ptrdiff_t>::min()" ],
                 MULTIPLEVALUESTRING => [ "std::ptrdiff_t", "std::numeric_limits<std::ptrdiff_t>::min()" ],
                 EXCHANGE   => [ "std::ptrdiff_t", "std::numeric_limits<std::ptrdiff_t>::min()" ],
                 NUMINGROUP => [ "int",  "std::numeric_limits<int>::min()" ],
                 UTCTIMESTAMP => [ "std::ptrdiff_t", "std::numeric_limits<std::ptrdiff_t>::min()"],
                 BOOLEAN    => [ "boolean", "0" ],
                 LOCALMKTDATE => [ "std::ptrdiff_t", "std::numeric_limits<std::ptrdiff_t>::min()" ],
                 INT        => [ "int",  "std::numeric_limits<int>::min()" ],
                 DATA       => [ "std::ptrdiff_t", "std::numeric_limits<std::ptrdiff_t>::min()"  ],
                 FLOAT      => [ "long", "std::numeric_limits<long>::min()" ],
                 PERCENTAGE => [ "long", "std::numeric_limits<long>::min()" ],
                 PRICEOFFSET => [ "long", "std::numeric_limits<long>::min()" ],
                 MONTHYEAR   => [ "std::ptrdiff_t", "std::numeric_limits<std::ptrdiff_t>::min()" ],
                 UTCDATEONLY => [ "std::ptrdiff_t", "std::numeric_limits<std::ptrdiff_t>::min()" ],
                 UTCTIMEONLY => [ "std::ptrdiff_t", "std::numeric_limits<std::ptrdiff_t>::min()" ],
                 COUNTRY     => [ "std::ptrdiff_t", "std::numeric_limits<std::ptrdiff_t>::min()" ],
};

my %TYPE_FMT = ( "std::ptrdiff_t" => "%s",
                 "char"           => "%c",
                 "int"            => "%d",
                 "long"           => "%ld",
                 "boolean"        => "%d",
    );


my $fix_version = get_version($data);

print $fix_version, "\n";

$out_dir .= "/$fix_version";

my $header     = get_header($data);
my $fields     = get_fields($data);
my $messages   = get_messages($data);
my $components = get_components($data);
my $trailer    = get_trailer($data);

$header->{attribute} = {ComponentType => 'field'};
$trailer->{attribute} = {ComponentType => 'field'};

#print Dumper($components);

$components->{MessageHeader} = $header;
$components->{MessageTrailer} = $trailer;
mkdir "$out_dir" unless -d $out_dir;

generate_fields_header($out_dir, $fix_version, $fields, $type_map);
generate_components_header($out_dir, $fix_version, $components, $fields, $type_map);
generate_messages_header($out_dir, $fix_version, $header, $messages, $components, $trailer,
                        $fields, $type_map);

#generate_messages_helper($out_dir, $fix_version, $header, $messages, $components, $trailer, $fields, $type_map);
generate_messages_helper($out_dir, $fix_version, $header, $messages, $components, $fields);

exit 0;

sub generate_messages_helper {
    my ($dir, $ver, $header, $messages, $components, $fields) = @_;
    {
        my $file_name = "$Bin/../tmp/messages_case_statements.txt";
        open my $file, ">$file_name" or die "ERROR: failed $!";
        foreach my $key (sort keys %$messages) {
            print $file <<EOD;
        case_builder($key);
EOD
        }
        close $file;
    }
    {
        my $file_name = "$Bin/../source/ValidateMessages.hpp";
        open my $file, ">$file_name" or die "ERROR: $file_name - $!";
        print $file <<EOD;
#ifndef __VALIDATE_MESSAGES_HPP__
#define __VALIDATE_MESSAGES_HPP__

#include "../FIX_4_4_0/FixMessages.hpp"

EOD
        foreach my $key (sort keys %$messages) {
            print $file "extern int validate(FIX::Messages::$key & _msg);\n";
        }
        print $file <<EOD;

#endif // __VALIDATE_MESSAGES_HPP__
EOD
        close $file;
    }

}

sub generate_messages_header {
    my ($dir, $ver, $header, $messages, $components, $trailer, $fields, $type_map) = @_;

    my $file_name = "$dir/FixMessages.hpp";
    open my $file, ">$file_name" or die "ERROR: $file_name - $!";

    print $file <<EOD;
#ifndef __FIX_MESSAGES_HPP__
#define __FIX_MESSAGES_HPP__

#include "FixComponents.hpp"
#include "../source/FixPairs.hpp"
#include "../source/FixHelper.hpp"
#include <stdio.h>

namespace FIX { namespace Messages {

EOD

    foreach my $key (sort keys %$messages) {
        process_message($file, $ver, $key, $messages, $components, $fields);
    }

    # build union pointer
    #
    print $file <<EOD;
    union msg_u_t {
EOD

    foreach my $key (sort keys %$messages) {
        print $file <<EOD;
        $key  u_$key;
EOD
    }

    print $file <<EOD;
    };

    template<class T> inline T & getmsg(msg_u_t &);

EOD

    foreach my $key (sort keys %$messages) {
        print $file <<EOD;
    template<> inline $key & getmsg<$key>(msg_u_t & _t) {
        return _t.u_$key;
    }

EOD
    }

    print $file <<EOD;

} } // FIX::Messages

#endif // __FIX_MESSAGES_HPP__
EOD
    close $file;
}


sub generate_components_header {
    my ($dir, $ver, $components, $fields, $type_map) = @_;

    my $file_name = "$dir/FixComponents.hpp";
    open my $file, ">$file_name" or die "ERROR: $file_name - $!";

    print $file <<EOD;
#ifndef __FIX_COMPONENTS_HPP__
#define __FIX_COMPONENTS_HPP__

#include "FixFields.hpp"
#include "../source/FixPairs.hpp"
#include <stdio.h>

namespace FIX { namespace Component {

EOD

    my $status = {};

    #print join " - ", keys %$components;
    foreach my $key ("MessageHeader", (sort grep { !/MessageTrailer/ } keys %$components), "MessageTrailer") {
        #print "$key <<<<<<<\n";
        process_component($file, $ver, $key, $components, $fields, $type_map, $status, {});
    }

        print $file <<EOD;

} } // FIX::Components

#endif // __FIX_COMPONENTS_HPP__
EOD
    close $file;
}

sub process_component {
    my ($file, $ver, $key, $components, $fields, $type_map, $status, $recursion) = @_;

    return if exists $status->{$key};
    if (exists $recursion->{$key}) {
        die "Recursion detected .... $key " . Dumper($recursion);
    }
    $recursion->{$key} = scalar keys %$recursion;

    foreach my $sub_key (get_sub_components($key, $components)) {
        process_component($file, $ver, $sub_key, $components, $fields, $type_map,
                          $status, $recursion);
    }

    my @define_fields = ();
    my @define_group_fields = ();
    print $file "    class $key {\n\n";
    print $file "        static const int component_id = ", $COMPONENT_ID++, ";\n\n";
    print $file "    public: // TODO Remove it and provide getter/setters\n";
    print $file "        char * _buffer;\n\n";

    my @components = ();

    #print Dumper($components);
    #print Dumper($components->{$key});

    if ($components->{$key}{attribute}{ComponentType} eq 'field') {
        for my $field (get_class_fields($key, $components)) {
            if (exists $components->{$field}) {
                printf $file "        %-40s %s;\n", $field,
                  "_\l$field";
                push @define_fields, "case_${field}_field_ids";
                push @define_fields, "case_${field}_group_field_ids"
                  if $components->{$field}{attribute}{ComponentType} eq 'group';
                push @components, $field;
            } else {
                printf $file "        %-40s %s;\n", "FIX::Field::${field}::Type",
                  "_\l$field";
                push @define_fields, "case FIX::Field::${field}::field_id";
            }
        }
    } elsif ($components->{$key}{attribute}{ComponentType} eq 'group') {
        print $file "        class Group {\n";
        #print "$key <<<" , keys %{$components->{$key}}, ">>>>>\n";
        #print Dumper($components->{$key});
        #exit 0;
        for my $field (get_class_fields($key, $components)) {
            #print "     $field <<<\n";
            if (exists $components->{$field}) {
                printf $file "            %-40s %s;\n", $field,
                  "_\l$field";
                push @define_group_fields, "case_${field}_field_ids";
                push @define_group_fields, "case_${field}_group_field_ids"
                  if $components->{$field}{attribute}{ComponentType} eq 'group';
            } else {
                printf $file "            %-40s %s;\n", "FIX::Field::${field}::Type",
                  "_\l$field";
                push @define_group_fields, "case FIX::Field::${field}::field_id";
            }
        }
        my $cfield = $components->{$key}{attribute}{CounterField};
        print $file "        };\n\n";
        print $file "        int     _\l$cfield;\n";
        print $file "        Group ** _group;\n";
        push @define_fields, "case FIX::Field::${cfield}::field_id";
    } else {
        die;
    }
    my $j = "\\\n    ";
    print $file "#define  case_${key}_field_ids $j", join(":$j", @define_fields), "\n\n";
    if (@define_group_fields) {
        print $file "#define  case_${key}_group_field_ids $j",
          join(":$j", @define_group_fields), "\n\n";
    }

    print $file <<EOD;
    public:

        void init(char * buf) {
            _buffer = buf;
EOD
    if ($components->{$key}{attribute}{ComponentType} eq 'field') {
        for my $field (get_class_fields($key, $components)) {
            if (exists $components->{$field}) {
                printf $file "            _\l$field.init(buf);\n";
            } else {
                my $type = $type_map->{$fields->{$field}{type}}[0];
                my $setv = $type =~ /char\s*\*/ ? "" : " = FIX::Field::${field}::NO_VAL";
                printf $file "            %-40s %s;\n", "_\l$field", "$setv";
            }
        }
    } else {
        my $field = $components->{$key}{attribute}{CounterField};
        my $type = $type_map->{$fields->{$field}{type}}[0];
        my $setv = $type =~ /char\s*\*/ ? "" : " = FIX::Field::${field}::NO_VAL";
        printf $file "            %-40s %s;\n", "_\l$field", "$setv";
    }
    print $file <<EOD;
        }

        int push(FIX::Pairs::key_type key, const FIX::Pairs::val_type val) {
            switch (key) {
EOD
    if ($components->{$key}{attribute}{ComponentType} eq 'group') {
        my $cfield = $components->{$key}{attribute}{CounterField};
        print $file <<EOD;
            case FIX::Field::${cfield}::field_id:
                _\l$cfield = FIX::get<FIX::Field::${cfield}::Type>(val);
               break;
EOD
          for my $field (get_class_fields($key, $components)) {
              # TO DO
          }
    } else {
        for my $field (get_class_fields($key, $components)) {
            if (exists $components->{$field}) {
                my $g = $components->{$field}{attribute}{ComponentType} eq 'group'
                  ? "\n            case_${field}_group_field_ids:" : "";
                print $file <<EOD;
            case_${field}_field_ids:$g
                _\l$field.push(key, val);
                break;
EOD
            } else {
                print $file <<EOD;
            case FIX::Field::${field}::field_id:
                _\l$field = FIX::get<FIX::Field::${field}::Type>(val);
                break;
EOD
            }
        }
    }

    print $file <<EOD;
            }
            return 0;
        }
EOD
    print $file <<EOD;
        void show() {
            printf("BEGIN: $key\\n");
EOD

    if ($components->{$key}{attribute}{ComponentType} eq 'field') {
        for my $field (get_class_fields($key, $components)) {
            if (exists $components->{$field}) {
                print $file <<EOD;
                _\l$field.show();
EOD
            } else {
                my $type = $type_map->{$fields->{$field}{type}}[0];
                my $fmt  = $TYPE_FMT{$type} || die "Missing fmt for $type";
                my $val  = $fmt ne '%s' ? "_\l$field" : "_buffer + _\l$field";
                my ($xfmt, $vals) = $type ne 'long'
                  ? ("%-30s[%4d] = $fmt", join(", ", "FIX::Field::${field}::field_id", $val))
                  : ("%-30s[%4d] = $fmt/%ld",
                     join(", ", "FIX::Field::${field}::field_id", "($val >> 4)", "($val & 0b111)"));
                print $file <<EOD;
            if (FIX::Field::${field}::isSet(_\l$field))
                printf("    $xfmt\\n", "$field", $vals);
EOD
            }
        }
    } else {
        my $cfield = $components->{$key}{attribute}{CounterField};
        my $type = $type_map->{$fields->{$cfield}{type}}[0];
        my $fmt  = $TYPE_FMT{$type} || die "Missing fmt for $type";
        my $val  = $fmt ne '%s' ? "_\l$cfield" : "_buffer + _\l$cfield";
        my ($xfmt, $vals) = $type ne 'long'
          ? ("%-30s[%4d] = $fmt", join(", ", "FIX::Field::${cfield}::field_id", $val))
                  : ("%-30s[%4d] = $fmt/%ld",
                     join(", ", "FIX::Field::${cfield}::field_id", "($val >> 4)", "($val & 0b111)"));
        print $file <<EOD;
            if (FIX::Field::${cfield}::isSet(_\l$cfield))
                printf("    $xfmt\\n", "$cfield", $vals);
EOD
    }

    print $file <<EOD;
            printf("END: $key\\n---\\n");
        }
EOD

    print $file <<EOD;
        int encode(char * buffer) {

            int offset = 0;
EOD
    if ($components->{$key}{attribute}{ComponentType} eq 'field') {
        for my $field (get_class_fields($key, $components)) {
            if (exists $components->{$field}) {
                print $file <<EOD;
            offset += _\l$field.encode(buffer + offset);
EOD
            } else {
                my $type = $type_map->{$fields->{$field}{type}}[0];
                my $fmt  = $TYPE_FMT{$type} || die "Missing fmt for $type";
                my $val  = $fmt ne '%s' ? "_\l$field" : "_buffer + _\l$field";
                print $file <<EOD;
            if (FIX::Field::${field}::isSet(_\l$field))
                offset += sprintf(buffer + offset, "%d=$fmt\\001",
                    FIX::Field::${field}::field_id, $val);
EOD
            }
        }
    } else {
        my $cfield = $components->{$key}{attribute}{CounterField};
        my $type = $type_map->{$fields->{$cfield}{type}}[0];
        my $fmt  = $TYPE_FMT{$type} || die "Missing fmt for $type";
        my $val  = $fmt ne '%s' ? "_\l$cfield" : "_buffer + _\l$cfield";
        print $file <<EOD;
            if (FIX::Field::${cfield}::isSet(_\l$cfield))
                offset += sprintf(buffer + offset, "%d=$fmt\\001",
                    FIX::Field::${cfield}::field_id, $val);
EOD
    }

    print $file <<EOD;
            return offset;
        }
EOD

    print $file "    };\n\n";
    $status->{$key} = 1;
}

sub process_message {
    my ($file, $ver, $key, $messages, $components, $fields, $base) = @_;

    if ($base) {
        $base = ": public $base ";
    } else {
        $base = "/* : public FixMessage */";
    }

    print $file "    class $key ${base}\{\n\n";
    print $file "    public: // TODO Remove it and provide getter/setters\n";
    print $file "        char * _buffer;\n";

    my %supported_fields = ();
    my @xcomponents = ();
    for my $field (get_class_fields($key, $messages)) {
        if (exists $components->{$field}) {
            printf $file "        %-40s %s;\n", "FIX::Component::$field",
              "_\l$field";
            push @xcomponents, $field;
            my @components = ($field);
            while (@components) {
                my $comp = shift @components;
                foreach my $cfield (get_class_fields($comp, $components)) {
                    if (exists $components->{$cfield}) {
                        push @components, $cfield;
                    } else {
                        $supported_fields{$cfield} = $fields->{$cfield};
                    }
                }
            }
        } else {
            $supported_fields{$field} = $fields->{$field};
            printf $file "        %-40s %s;\n", "FIX::Field::${field}::Type",
              "_\l$field";
        }
    }

    my $len = length($messages->{$key}{attribute}{MsgType});
    my $xlen = $len + 1;
    print $file <<EOD;
    public:
        constexpr static char type[$xlen] = "$messages->{$key}{attribute}{MsgType}";
        constexpr static int  type_id = msg_type_key_(type, $len);
EOD

    my @fields = get_class_fields($key, $messages);

    my $init_size = 4;
    my $set = ceil(@fields/$init_size);

    foreach my $i (0..$init_size-1) {
        my $fs = $i == 0 ? "" : "_$i";
        print $file <<EOD;
        void init$fs(char * buf) {
            _buffer = buf;
EOD
        for my $field (@fields[$i*$set..($i+1)*$set - 1]) {
            next unless $field;
            if (exists $components->{$field}) {
                printf $file "            _\l$field.init(buf);\n"
            } else {
                my $type = $type_map->{$fields->{$field}{type}}[0];
                my $setv = $type =~ /char\s*\*/ ? "" : " = FIX::Field::${field}::NO_VAL";
                printf $file "            %-40s %s;\n", "_\l$field", "$setv";
            }
        }
        print $file <<EOD;
        }
EOD
    }

    print $file <<EOD;
        int buildFromPairs(FIX::Pairs & pairs) {
            size_t size = pairs.getSize();
            const FIX::Pairs::fix_pair_t * plist = pairs.getPairs();
            for(int i = 0; i < size; i++) {
                FIX::Pairs::key_type key = plist[i].first;
                switch (key) {
EOD

    for my $field (get_class_fields($key, $messages)) {
        if (exists $components->{$field}) {
            print $file <<EOD;
                case_${field}_field_ids:
                    _\l$field.push(key, plist[i].second);
                    break;
EOD
        } else {
            print $file <<EOD;
                case FIX::Field::${field}::field_id:
                    _\l$field = FIX::get<FIX::Field::${field}::Type>(plist[i].second);
                    break;
EOD
        }
    }
    print $file <<EOD;
                }
            }
            return 0;
        }
EOD

    print $file <<EOD;
        void show() {
            printf("BEGIN: $key\\n");
EOD

    for my $field (get_class_fields($key, $messages)) {
        if (exists $components->{$field}) {
            print $file <<EOD;
            _\l$field.show();
EOD
        } else {
            my $type = $type_map->{$fields->{$field}{type}}[0];
            my $fmt  = $TYPE_FMT{$type} || die "Missing fmt for $type";
            my $val  = $fmt ne '%s' ? "_\l$field" : "_buffer + _\l$field";

            my ($xfmt, $vals) = $type ne 'long'
              ? ("%-30s[%4d] = $fmt", join(", ", "FIX::Field::${field}::field_id", $val))
              : ("%-30s[%4d] = $fmt/%ld", join(", ", "FIX::Field::${field}::field_id", "($val >> 4)", "($val & 0b111)"));
            print $file <<EOD;
            if (FIX::Field::${field}::isSet(_\l$field))
                printf("    $xfmt\\n", "$field", $vals);
EOD
        }
    }
    print $file <<EOD;
            printf("END: $key\\n---\\n");
        }
EOD

    print $file <<EOD;
        char * encode(char * buffer) {

            int offset = 0;
EOD

    for my $field (get_class_fields($key, $messages)) {
        if (exists $components->{$field}) {
            print $file <<EOD;
            offset += _\l$field.encode(buffer + offset);
EOD
        } else {
            my $type = $type_map->{$fields->{$field}{type}}[0];
            my $fmt  = $TYPE_FMT{$type} || die "Missing fmt for $type";
            my $val  = $fmt ne '%s' ? "_\l$field" : "_buffer + _\l$field";
            print $file <<EOD;
            if (FIX::Field::${field}::isSet(_\l$field))
                offset += sprintf(buffer + offset, "%d=$fmt\\001",
                                  FIX::Field::${field}::field_id, $val);
EOD
        }
    }
    print $file <<EOD;
            return buffer;
        }
EOD

    print $file "    };\n\n";
}

sub get_sub_components {
    my ($key, $components) = @_;
    return grep { exists $components->{$_} } get_class_fields($key, $components);
}

sub get_class_fields {
    my ($key, $components) = @_;
    return sort {
        $components->{$key}{$a}{index} <=> $components->{$key}{$b}{index} } grep {
            $_ ne "attribute"
    } keys %{$components->{$key}};
}

sub generate_fields_header {
    my ($dir, $ver, $fields, $type_map) = @_;
    my $file_name = "$dir/FixFields.hpp";
    my %type_fields = ();

    open my $file, ">$file_name" or die "ERROR: $file_name - $!";
    print $file <<EOD;
#ifndef __FIX_FIELDS__
#define __FIX_FIELDS__

#include <limits>

namespace FIX { namespace Field {

    typedef short boolean;
EOD

    #print Dumper($fields);

    foreach my $key (sort {
        $fields->{$a}{number} <=> $fields->{$b}{number} } keys %$fields) {
        my $t = $type_map->{$fields->{$key}{type}};
        die "ERROR: unsupported $fields->{$key}{type}" if !$t;

        my ($size, $ss, $sz) = ("", "", "");
        if ($t->[2]) {
            $size = "\n        const int Size = $t->[2];\n";
            $ss   = "[Size]";
            $sz   = "[0]";
        }
        print $file <<EOD;

    namespace $key {
        const int field_id = $fields->{$key}{number};
        typedef   $t->[0] Type;$size
        const Type  NO_VAL = $t->[1];
        inline bool isUnset(Type t$ss) { return t$sz == NO_VAL; }
        inline bool isSet(Type t$ss) { return !isUnset(t); }
        inline void unset(Type t$ss) { t$sz = NO_VAL; }
    };
EOD
        (my $x = $t->[0]) =~ s/\s+//g;
        my %trans = ( "char*" => "string",
                      "std::ptrdiff_t" => "string");
        my $y = $trans{$x} || $x;
        $type_fields{$y}{$fields->{$key}{number}} = $key;
    }

    foreach my $ty (sort keys %type_fields) {
        print $file "#define case_field_type_$ty  \\\n";
        print $file join": \\\n", map {
            "    case FIX::Field::$type_fields{$ty}{$_}::field_id"
        } sort { $a <=> $b } keys %{$type_fields{$ty}};
        print $file "\n\n";
    }
    print $file <<EOD;
} } // FIX::Fields

#endif //__FIX_FIELDS__
EOD
    close $file;
}

sub get_components {
    my ($data) = @_;
    my $component = get_node("components", $data->[1]);
    my ($i, $j) = (0, 0);
    my %component = ();
    while (my ($k, $v) = get_key_data($component, $i++)) {
        #print "($k, $v) <<<<<\n";
        next if $k ne 'component';
        my $name = $v->[0]{name};
        my $c = $component{$name} = {};
        my $j = 0;
        while (my ($k, $d) = get_key_data($v, $j++)) {
            next if $k eq "0";
            if ($k eq 'field' || $k eq 'component') {
                die "ERROR: component $name - group and field both defined"
                  if (($c->{attribute}{ComponentType} ||= "field") ne "field");
                @{$c->{$d->[0]{name}}}{qw(index required)}
                  = (++$j, $d->[0]{required} eq 'Y' ? 1 : 0);
            } elsif ($k eq "group") {
                die "ERROR: component - Expecting only single group in $name"
                  if defined $c->{attribute}{ComponentType};
                $c->{attribute}{ComponentType} = "group";
                $c->{attribute}{CounterField} = $d->[0]{name};
                my ($x, $y) = (0, 0);
                while (my ($k, $v) = get_key_data($d, $x++)) {
                    next if $k eq "0";
                    die "ERROR: component $name - expecting field or component in group"
                      unless $k eq 'field' || $k eq 'component';
                    @{$c->{$v->[0]{name}}}{qw(index required)}
                      = (++$y, $v->[0]{required} eq 'Y' ? 1 : 0);
                }
            } else {
                die "ERROR: component $name - invalid tag ($k)";
            }
        }
    }
    return \%component;
}

sub get_header {
    my ($data) = @_;
    my $header = get_node("header", $data->[1]);
    my ($i, $j) = (0, 0);
    my %header = ();
    while (my ($k, $v) = get_key_data($header, $i++)) {
        next if $k ne 'field';
        @{$header{$v->[0]{name}}}{qw(index required)}
          = (++$j, $v->[0]{required} eq 'Y' ? 1 : 0);
    }
    return \%header;
}

sub get_trailer {
    my ($data) = @_;
    my $trailer = get_node("trailer", $data->[1]);
    my ($i, $j) = (0, 0);
    my %trailer = ();
    while (my ($k, $v) = get_key_data($trailer, $i++)) {
        next if $k ne 'field';
        @{$trailer{$v->[0]{name}}}{qw(index required)}
          = (++$j, $v->[0]{required} eq 'Y' ? 1 : 0);
    }
    return \%trailer;
}

sub get_messages {
    my ($data) = @_;
    my $messages = get_node("messages", $data->[1]);

    my $i = 0;
    my %messages = ();
    while (my ($key, $data) = get_key_data($messages, $i++)) {
        next if $key ne 'message';
        my $att = $data->[0];
        @{$messages{$att->{name}}{attribute}}{qw(MsgCat MsgType)} = @{$att}{qw(msgcat msgtype)};
        my ($j, $l)= (0, 0);
        $messages{$att->{name}}{MessageHeader} = { index => 0, required => 1 };
        while(my ($f, $v) = get_key_data($data, $j++)) {
            next if $f eq '0';
            @{$messages{$att->{name}}{$v->[0]{name}}}{qw(index required)}
              = ( ++$l, $v->[0]{required} eq 'Y' ? 1 : 0);
        }
        $messages{$att->{name}}{MessageTrailer} = { index => 99999, required => 1 };
    }
    return \%messages;
}

sub get_fields {
    my ($data) = @_;
    #print Dumper($data);
    my $fields = get_node("fields", $data->[1]);
    #print Dumper($fields);
    my $i = 0;
    my %fields = ();
    while (my ($key, $data) = get_key_data($fields, $i++)) {
        next if $key ne 'field';
        my ($name, $type, $number) = @{$data->[0]}{qw(name type number)};
        die "Check field $name " . Dumper($data->[0]) . "\n". Dumper($fields{$name})
          if exists $fields{$name};
        @{$fields{$name}}{qw(type number)} = ($type, $number);
        #print "$name, $type, $number\n";
    }
    return \%fields;
}

sub get_node {
    my ($key, $data) = @_;
    my $i = 0;
    while(my ($k, $v) = get_key_data($data, $i++)) {
        return $v if $k eq $key;
    }
    return undef;
}

sub get_version {
    my ($key, $data) = @{$_[0]};
    die "ERROR: expecting 'fix' key" if $key ne 'fix';
    #print $key, "\n", Dumper($data->[0]);
    return join "_", @{$data->[0]}{qw(type major minor servicepack)};
}

sub get_key_data {
    my ($data, $index) = @_;
    return () if $#$data < 2 + $index * 2;
    return ($data->[1 + $index * 2], $data->[2 + $index * 2]);
}
