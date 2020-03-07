package pkglib;

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
use Term::ANSIColor;

my $distro;
my $pkgmgr;

my %os_pkgmgr = (
    'opensuse' => 'zypper',
    'Catalina' => 'MacPorts'
);

my %pkg_map = (
    'opensuse' => {
        'base'      => {
            'core'  => [
                'patterns-devel-base-devel_basis',
                'patterns-devel-C-C++-devel_C_C++'
            ]
        }
    },
    'Catalina'      => {
        'base'      => {
            'core'  => [
                'bison',
                'db48',
                'gdbm',
                'openssl',
                'pth',
                'zlib'
            ]
        }
    }
);

sub new ($class, $distribution) {
    my $self = {};
    bless $self, $class;

    $distro = $distribution;

    print color('bold cyan');
    say STDOUT "Using '$os_pkgmgr{$distribution}' to install packages";
    print color('reset');

    return $self;
}

my sub check_if_installed ($pkg_name) {
    system("rpm -q $pkg_name 2>&1 >/dev/null");
    if ($? != 0) {
        return false;
    } else {
        return true;
    }
}

my sub zypper_install ($pkg_name) {
    if (check_if_installed($pkg_name) == false) {
        system('sudo', '/usr/bin/zypper', '--no-refresh', '--verbose', 'install', '-y', '--recommends', $pkg_name);
        if ($? != 0) {
            print color('bold white on_red');
            return false;
            print color('reset');
        }
    } else {
        print color('green');
        say "already installed";
        print color('reset');
    }
}

my sub check_if_port_installed ($pkg_name) {
    system("/opt/local/bin/port -q installed $pkg_name | grep -q active");
    if ($? != 0) {
        return false;
    } else {
        return true;
    }
}

my sub ports_install ($pkg_name) {
    if (check_if_port_installed($pkg_name) == false) {
        system('sudo', '/opt/local/bin/port', 'install', $pkg_name);
        if ($? != 0) {
            return false;
        }
    } else {
        print color('green');
        say 'already installed';
        print color('reset');
        return true;
    }
}

our sub install_pkgs ($self, $os, $class, $subclass) {
    my $pkgs = $pkg_map{$os}{$class}{$subclass};

    foreach my $pkg (@{$pkgs}) {
        print color('white');
        print STDOUT "Installing $pkg: ";
        print color('reset');
        given ($os_pkgmgr{$os}) {
            when ('zypper') {
                zypper_install($pkg);
            }
            when ('MacPorts') {
                ports_install($pkg);
            }
        }
    }
}

true;