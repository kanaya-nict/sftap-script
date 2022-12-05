#!/usr/bin/env perl
use strict;
use IO::Socket::UNIX;
use JSON;
use MIME::Base64 qw(encode_base64);
use Divide;

my $name = "/tmp/sf-tap/udp/syslog";
my $output_dir = "syslog";
my $output_file_head = "syslog";
my $output_file_ext  = "json";

sub parse_header{
    my ($line) = @_;
    chop $line;
    my %data = split(/[\,\=]/, $line);

    my $res;

    if($data{from} == 2 ){
	$res = {
	    src=>$data{ip2},
	    dst=>$data{ip1},
	    len=>$data{len}
	};
    } else {
	$res = {
	    src=>$data{ip1},
	    dst=>$data{ip2},
	    len=>$data{len}
	};
    };
    $res->{vlan} = $data{vlan};
    
    return $res;
}


sub parse_body{
    my ($data, $line) = @_;
    $data->{body} = $line;
    
    $line=~ s/^\<(\d+)\>(\w+\s+\w+\s+\w+\:\w+\:\w+)\s+([^\s]+)\s+([a-zA-Z]+)//;
    $data->{pri}  = $1;
    $data->{date} = $2;
    $data->{host} = $3;
    $data->{tag}  = $4;
}


if(defined $ARGV[0]){
    $output_dir = $ARGV[0];
}
my $d = new Divide($output_dir, $output_file_head, $output_file_ext);

my $s = IO::Socket::UNIX->new(Type=>SOCK_STREAM(), Peer=>$name);

if(!defined $s){
    $s = *STDIN;
}

my $line;

while(defined ($line = $s->getline())){
    my $data;
    if(defined ($data = parse_header($line))){
	$data->{time} = time;
	my $res; my $body;
	$res = $s->read($body, $data->{len});
	parse_body($data, $body);
	if(exists $data->{src}){
	    my $fh = $d->get_filehandle_by_vlan($data->{vlan}, $data->{time});
	    if(defined $fh){
		print $fh encode_json($data), "\n";
	    }
	}
	print encode_json($data), "\n";
    }
}

    
