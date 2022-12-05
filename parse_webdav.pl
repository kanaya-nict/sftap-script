#!/usr/bin/env perl
#

use strict;
use Socket;
use IO::Socket;
use IO::Socket::INET;
use IO::Socket::UNIX;
use XML::Simple;
use JSON;
use FileHandle;
use Divide;
use File::Path;

my $yarai_host = 'localhost';
my $yarai_port = 80;
my $sftap_http_sock  = '/tmp/sf-tap/tcp/http';

my $xml = XML::Simple->new;

my $output_dir = "webdav";
my $output_file_head = "webdav";
my $output_file_ext  = "json";
my $output_file_ext2  = "bin";

if(defined $ARGV[0]){
    $output_dir = $ARGV[0];
}

my $d = new Divide($output_dir, $output_file_head, $output_file_ext, $output_file_ext2);

sub parse_data{
    my ($taple) = @_;
    my ($body, $ipaddr) = ($taple->{body}, $taple->{ip1});

#    print STDERR "parse_data, $taple, $ipaddr\n";
    
    if($body =~ s/^PUT\s+(\S+)\s+[^\r\n\f]+[\r\n\f]+//){
	my $uri = $1;
	my $pos = index($body, "\r\n\r\n");
	my $header   = substr($body, 0, $pos+2);
	$header =~ m/Content-Length.\s+(\d+)/;
	my $content_length = $1;


	my $contents = substr($body, $pos+4);

	$taple->{time} =~ m/([\d\.]+)/;
	my $time =$1;
	my ($dirname, $pathname) = $d->get_dirname_by_vlan($taple->{vlan}, $time);
	if(! -d $dirname ){
	    File::Path::make_path($dirname);
	}
	#	    print STDERR "find put $time, $uri, $content_length, $dirname, $pathname\n";
	my $fh = new FileHandle($pathname, "w");
	
	print $fh $contents;
	close $fh;

	my %table;
	$table{ip1}    = $taple->{ip1};
	$table{port1}  = $taple->{port1};
	$table{ip2}    = $taple->{ip2};
	$table{port2}  = $taple->{port2};
	$table{time}   = $time;
	$table{url}    = $uri;
	$table{length} = length($contents);
	$table{path}   = $pathname;
	$table{vlan}   = $taple->{vlan};

	my $json_text = encode_json(\%table);
	my $log_fh = $d->get_filehandle_by_vlan($taple->{vlan}, $time);
	print $log_fh $json_text , "\n";
    }
}

sub parse_header{
    my ($line) = @_;

    my %result = map{split(/\=/, $_)} split(/\,/, $line);

    return \%result;
}



my  $client = IO::Socket::UNIX->new(
    Type=> SOCK_STREAM(),
    Peer=>$sftap_http_sock);
if(!defined $client){
    $client = *STDIN;
}


my %taple_table;

while($_ = $client->getline){
    my $taple;
    if(/^ip/) {
	my $data = parse_header($_);

	if($data->{'event'} eq 'CREATED'){
	    my %table;
	    $table{'ip1'}   = $data->{'ip1'};
	    $table{'ip2'}   = $data->{'ip2'};
	    $table{'port1'} = $data->{'port1'};
	    $table{'port2'} = $data->{'port2'};
	    $table{time}    = $data->{time};
	    $table{vlan}    = $data->{vlan};
	    $table{body} = "";
	    $table{len} = 0;
	    $taple_table{$data->{'ip1'}, $data->{'port1'}, $data->{'ip2'}, $data->{'port2'}, $data->{vlan}}
	    = \%table;
	}
	else {
	    my $taple = $taple_table{$data->{'ip1'}, $data->{'port1'}, $data->{'ip2'}, $data->{'port2'}, $data->{vlan}};
	    if($data->{'event'} eq 'DESTROYED'){
		if(defined $taple){
		    parse_data($taple);
		    delete $taple_table{$data->{'ip1'}, $data->{'port1'}, $data->{'ip2'}, $data->{'port2'}, $data->{vlan}};
		}
	    }
	    elsif($data->{'event'} eq 'DATA'){
		my $len = $data->{len};
		my $res;
		$client->read($res, $len);
		if((defined $taple) and ($data->{'from'} eq 1)){
		    $taple->{body} .= $res;
		    if(($taple->{len} < 3) && 
		       ($taple->{len} + $len > 3)){      ## 最初の４文字がきた時点で判定する
			if($taple->{body} !~ /^PUT\s+/){
			    delete $taple_table{$data->{'ip1'}, $data->{'port1'}, 
						    $data->{'ip2'}, $data->{'port2'}, $data->{vlan}};
			}
		    }
		    $taple->{len}  += $len;
		}
	    }
	    else{
		##
		print "data error$_\n";
	    }
	}
    }
}
