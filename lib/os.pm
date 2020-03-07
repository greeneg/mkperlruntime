package os;

use strict;
use warnings;
use English;
use utf8;

use feature qw(
    lexical_subs
    say
    signatures
    switch
);
no warnings 'experimental::lexical_subs';
no warnings 'experimental::signatures';
no warnings 'experimental::smartmatch';

use boolean;
use Data::Dumper;
use POSIX;
use JSON::PP qw(decode_json);

sub new ($class) {
    my $self = {};
    bless $self, $class;

    return $self;
}

my sub linux_distribution {
    my $distribution = undef;

    if (-f '/etc/os-release') {
        # parse the os-release file for the distribution
        open(my $os_release, '/etc/os-release') or
          die "Cannot open '/etc/os-release' for read: $!\n";
        foreach my $line (readline $os_release) {
            next if $line !~ m/^CPE_NAME.*/;
            chomp ($line);
            $line =~ s/^CPE_NAME\=//;
            $line =~ s/"//g;
            (undef, undef, $distribution, undef, undef) = split(/:/, $line);
        }
        close $os_release;
    }

    return $distribution;
}

my sub linux_distribution_id {
    my $distribution_id = undef;

    if (-f '/etc/os-release') {
        # parse the os-release file for the distribution
        open(my $fh, '/etc/os-release') or
          die "Cannot open '/etc/os-release' for read: $!\n";
        foreach my $line (readline $fh) {
            next if $line !~ m/^ID\=.*/;
            chomp ($line);
            $line =~ s/^ID\=//;
            $line =~ s/"//g;
            $distribution_id = $line;
        }
        close $fh;
    }

    return $distribution_id;
}

my sub distribution_release {
    my $release = undef;

    my $distribution = linux_distribution_id();

    if ($distribution ne 'opensuse-tumbleweed') {
        if (-f '/etc/os-release') {
            open(my $fh, '/etc/os-release') or
              die "Cannot open '/etc/os-release' for read: $!\n";
            foreach my $line (readline $fh) {
                next if $line !~ m/^VERSION_ID.*/;
                chomp $line;
                $line =~ s/^VERSION_ID\=//;
                $line =~ s/"//g;
                $release = $line;
            }
            close $fh;
        }
    } else {
        $release = 'tumbleweed';
    }

    return $release;
}

our sub os_platform {
    my ($os_platform, undef, undef, undef, undef) = POSIX::uname();

    return lc($os_platform);
}

our sub os_platform_release {
    my (undef, undef, $os_platform_release, undef, undef) = POSIX::uname();

    return $os_platform_release;
}

our sub os_platform_arch {
    my (undef, undef, undef, undef, $os_platform_arch) = POSIX::uname();

    return $os_platform_arch;
}

our sub macos_codename ($self, $platform) {
    my $os_code_name = undef;
    my $os_major_release = macos_release($self, $platform);
    given ($os_major_release) {
        when ('10.0') {
            $os_code_name = 'Cheetah';
        }
        when ('10.1') {
            $os_code_name = 'Puma';
        }
        when ('10.2') {
            $os_code_name = 'Jaguar';
        }
        when ('10.3') {
            $os_code_name = 'Panther';
        }
        when ('10.4') {
            $os_code_name = 'Tiger';
        }
        when ('10.5') {
            $os_code_name = 'Leopard';
        }
        when ('10.6') {
            $os_code_name = 'Snow Leopard';
        }
        when ('10.7') {
            $os_code_name = 'Lion';
        }
        when ('10.8') {
            $os_code_name = 'Mountain Lion';
        }
        when ('10.9') {
            $os_code_name = 'Mavericks';
        }
        when ('10.10') {
            $os_code_name = 'Yosemite';
        }
        when ('10.11') {
            $os_code_name = 'El Capitan';
        }
        when ('10.12') {
            $os_code_name = 'Sierra';
        }
        when ('10.13') {
            $os_code_name = 'High Sierra';
        }
        when ('10.14') {
            $os_code_name = 'Mojave';
        }
        when ('10.15') {
            $os_code_name = 'Catalina';
        }
    }

    return $os_code_name;
}

our sub macos_release ($self, $platform) {
    my $system_profile = qx|/usr/sbin/system_profiler SPSoftwareDataType -json|;

    my $os_profile_json = decode_json $system_profile;
    my $os_profile = shift @{$os_profile_json->{'SPSoftwareDataType'}};
    my $os_version = %{$os_profile}{'os_version'};

    my $os_code_name = undef;
    my (undef, $os_release, undef) = split(/\s+/, $os_version);
    # drop the patch version
    my ($major, $minor, undef) = split(/\./, $os_release);
    my $os_major_release = "$major.$minor";

    return $os_major_release;
}

our sub os_family ($self, $platform) {
    my $os_family;

    given ($platform) {
        when ('linux') {
            $os_family = linux_distribution();
        }
        when ('darwin') {
            $os_family = macos_codename($self, $platform);
        }
    }

    return $os_family;
}

our sub os_release ($self, $platform) {
    my $os_release;

    given ($platform) {
        when ('linux') {
            $os_release = distribution_release();
        }
        when ('darwin') {
            $os_release = macos_release($self, $platform);
        }
    }

    return $os_release;
}

true;
