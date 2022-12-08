#!/usr/bin/perl
use strict;
use JSON;
use FileHandle;
use Divide;

my $output_dir = "dns";
my $output_file_head = "dns";
my $output_file_ext  = "json";

if(defined $ARGV[0]){
    $output_dir = $ARGV[0];
}

my $d = new Divide($output_dir, $output_file_head, $output_file_ext);
$d->{yyyymmdd}=1;

sub print_entry{
    my ($time, $src, $dst, $name, $addr, $id, $type, $vlan, $netid) =@_;
    my $fh = $d->get_filehandle_by_vlan($vlan, $time, $netid);

    my %data =(
	time=>$time,
	src=>$src,
	dst=>$dst,
	name=>$name,
	a=>$addr,
	id=>$id,
	type=>$type
	);
    my $data = encode_json(\%data);
    print $fh "$data\n";
    
}

$|=1;
my $line;
while(defined ($_ = <STDIN>)){
    my $data = decode_json($_);

    if(defined $data){
	if($data->{'qr'} == 1){
	    my $src  = $data->{'src'}->{'ip'};
	    my $dst  = $data->{'dst'}->{'ip'};
	    my $a = undef;
	    if((exists $data->{'answer'}) && ($#{$data->{'answer'}}>=0)){
		my $answer = $data->{'answer'};
		my $name = $data->{'query'}->[0]->{'name'};
		foreach my $entry (@$answer){
		    if($entry->{type} eq 'A'){
			my $time = time;
			print_entry($time, $src, $dst, $name, $entry->{a}, $data->{'id'}, "answer", $data->{vlan}, $data->{netid});
		    }
		}
	    }
	    else{
		my $name;
		if(exists $data->{'answer'}){
		    $name = $data->{'query'}->[0]->{'name'};
		}
		my $time = time;
		print_entry($time, $src, $dst, $name, undef, $data->{'id'}, "answer", $data->{vlan});
	    }
	}
	else{
	    if((exists $data->{'query'}) && ($#{$data->{'query'}}>=0)){
		my $query = $data->{'query'};
		my $src  = $data->{'src'}->{'ip'};
		my $dst  = $data->{'dst'}->{'ip'};
		my $name = $query->[0]->{'name'};
		foreach my $entry (@$query){
		    if($entry->{type} eq 'A'){
			my $time = time;
			print_entry($time, $src, $dst, $name, undef, $data->{'id'}, "query", $data->{vlan}, $data->{netid});
		    }
		}
	    }
	}
    }
}

__END__
