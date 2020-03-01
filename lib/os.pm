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
use POSIX;

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

    if ($distribution != 'opensuse-tumbleweed') {
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

our sub os_family ($self, $platform) {
    my $os_family;

    given ($platform) {
        when ('linux') {
            $os_family = linux_distribution();
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
    }

    return $os_release;
}

true;