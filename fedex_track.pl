
use strict;
use warnings;

use DateTime;
use File::Copy;
use File::Spec::Functions;
use LWP::UserAgent;
use XML::Simple;
use JSON;

#https://www.fedex.com/trackingCal/track?action=trackpackages&data={"TrackPackagesRequest"%3A{"appType"%3A"wtrk"%2C"uniqueKey"%3A""%2C"processingParameters"%3A{"anonymousTransaction"%3Atrue%2C"clientId"%3A"WTRK"%2C"returnDetailedErrors"%3Atrue%2C"returnLocalizedDateTime"%3Afalse}%2C"trackingInfoList"%3A[{"trackNumberInfo"%3A{"trackingNumber"%3A"
my $fq = q(https://www.fedex.com/trackingCal/track?action=trackpackages&data={%22TrackPackagesRequest%22%3A{%22appType%22%3A%22wtrk%22%2C%22uniqueKey%22%3A%22%22%2C%22processingParameters%22%3A{%22anonymousTransaction%22%3Atrue%2C%22clientId%22%3A%22WTRK%22%2C%22returnDetailedErrors%22%3Atrue%2C%22returnLocalizedDateTime%22%3Afalse}%2C%22trackingInfoList%22%3A[{%22trackNumberInfo%22%3A{%22trackingNumber%22%3A%22);

#"%2C"trackingQualifier"%3A""%2C"trackingCarrier"%3A""}}]}}&format=json&locale=en_US&version=99
my $lq = q(%22%2C%22trackingQualifier%22%3A%22%22%2C%22trackingCarrier%22%3A%22%22}}]}}&format=json&locale=en_US&version=99);

my $checking_dir = catdir('z:','checkshipped');
#my $checking_dir = catdir('c:', 'backup', 'Need to ship', 'checkshipped');
my $checked_dir  = catdir($checking_dir,'checked');

my $current = time;
my @shipped;
my @late;
my %params = ();

my $last = 0;
my %files = get_sorted_files($checking_dir);

foreach my $key (sort{$files{$b} <=> $files{$a}} keys %files) {
    last if ($current - $files{$key} > 14*24*3600);	
	next if ($key !~ m/\d+\-.*/);	
	
	my $tracking_id = $key;
	$tracking_id =~ s/(\d+)\-.*/$1/;
	next if (length $tracking_id != 12);
	
	my $created = DateTime->from_epoch( epoch => $files{$key}, time_zone => 'America/New_York' );
	my $today =  DateTime->from_epoch( epoch => $current, time_zone => 'America/New_York' );	
	my $c_week = ($created->day_of_week()<6) ? $created->week_number() : $created->week_number()+1;
	my $c_day = ($created->day_of_week()<6) ? $created->day_of_week() : 1;
	my $t_day = ($today->day_of_week()<6) ? $today->day_of_week() : 5;
	my $diff = ($today->week_number()-$c_week)*5+($t_day-$c_day);
	
	$params{$tracking_id} = {'fname'=>$key, 'diff'=>$diff};
	if (scalar(keys %params) >= 25) {
		track(\%params); 
		%params = ();		
	}
		
    print "$tracking_id\t", scalar localtime($files{$key}), "\n";	
}

track(\%params) if (scalar(keys %params));

if (scalar @shipped) {
	foreach my $fname (@shipped) {
		move(catfile($checking_dir, $fname), catfile($checked_dir, $fname));
	}
}

if (scalar @late) {
  my $result = File::Spec->catfile('c:','NeedShip','A','FEDEX_NOT_SHIPPED.txt');
  open(my $fh, '>', $result) or die "cannot open < $result: $!";
  for my $late_name (@late) {
    print $fh "$late_name\n";
  }  
  
  for my $late_id (@late) {
    $late_id =~ s/(\d+)\-.*/$1/;
    print $fh "$late_id\n";
  }
  close($fh);
}

sub track {
	my $params = shift; #'580545115065243'; #'580545115062334';
	my $json = JSON->new->allow_nonref;	
	
	my @trackingInfos = ();
	foreach my $key (keys %$params) {
		push(@trackingInfos, {
			'trackNumberInfo' => {
                'trackingNumber' => $key,
                'trackingQualifier' => '',
                'trackingCarrier' => ''
            }
		});
	}
			
	my $ua = LWP::UserAgent->new();
	my $response = $ua->post('https://www.fedex.com/trackingCal/track', {
      'data' => $json->encode({
        'TrackPackagesRequest' => {
            'appType' => 'wtrk',
            'uniqueKey' => '',
            'processingParameters' => {
                'anonymousTransaction' => 'true',
                'clientId' => 'WTRK',
                'returnDetailedErrors' => 'true',
                'returnLocalizedDateTime' => 'false'
            },
            'trackingInfoList' => [@trackingInfos]
        }
      }),
      'action' => 'trackpackages',
      'locale' => 'en_US',
      'format' => 'json',
      'version' => 99
    });	
			
	if ($response->is_success) {	
		my $data = $json->decode($response->content);
		foreach my $tracking (@{$data->{'TrackPackagesResponse'}->{'packageList'}}) {
		    my $id = $tracking->{'trackingNbr'};
			#$params->{$id}->{'shipped'} = ($tracking->{'trackingQualifier'} eq '') ? 0 : 1;
			$params->{$id}->{'shipped'} = ($tracking->{'keyStatus'} eq 'Label created') ? 0 : 1;
			if ($params->{$id}->{'shipped'}) {
				push @shipped, $params->{$id}->{'fname'};
			} elsif ($params->{$id}->{'diff'} >= 3) {
				push @late, $params->{$id}->{'fname'};
			}
		}
		my $t=1;
	}		
}
		
sub hash_walk {
    my ($hash, $key_list) = @_;
    while (my ($k, $v) = each %$hash) {
        # Keep track of the hierarchy of keys, in case
        # our callback needs it.
        push @$key_list, $k;

		if ($k eq 'PackageCount' && ref($v) eq 'SCALAR') {
			return $v;
		}
        elsif (ref($v) eq 'HASH') {
            # Recurse. BUG what if its an array of HASH
            return hash_walk($v, $key_list);
        }        

        pop @$key_list;
    }
	
	return -1;
}

#map  { "$path/$_" }
sub get_sorted_files {
   my $path = shift;
   opendir my($dir), $path or die "can't opendir $path: $!";
   my %hash = map {$_ => (stat("$path/$_"))[9]}           
           grep { m/.*/i }
           readdir $dir;
   closedir $dir;
   return %hash;
}

