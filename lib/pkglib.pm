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
    'opensuse' => 'zypper'
);

my %pkg_map = (
    'opensuse' => {
        'devel'     => {
            'base'  => 'patterns-devel-base-devel_basis',
            'c_cpp' => 'patterns-devel-C-C++-devel_C_C++'
        },
        'audit'     => {
            'devel' => 'audit-devel',
            'main'  => 'audit',
            'lib'   => 'libaudit1'
        },
        'autoconf'  => {
            'main'  => 'autoconf'
        },
        'automake'  => {
            'main'  => 'automake'
        },
        'binutils'  => {
            'devel' => 'binutils-devel',
            'main'  => 'binutils'
        },
        'bison'     => {
            'main'  => 'bison'
        },
        'byacc'     => {
            'main'  => 'byacc'
        },
        'cpp'       => {
            'main'  => 'cpp'
        },
        'flex'      => {
            'main'  => 'flex'
        },
        'gcc'       => {
            'main'  => 'gcc'
        },
        'gdbm'      => {
            'devel' => 'gdbm-devel',
            'main'  => 'libgdbm4'
        },
        'gettext'   => {
            'main'  => 'gettext-runtime',
            'utils' => 'gettext-tools'
        },
        'glibc'     => {
            'devel' => 'glibc-devel',
            'main'  => 'glibc'
        },
        'libnsl'    => {
            'devel' => 'libnsl-devel',
            'main'  => 'libnsl3'
        },
        'libtool'   => {
            'main'  => 'libtool'
        },
        'm4'        => {
            'main'  => 'm4'
        },
        'make'      => {
            'main'  => 'make'
        },
        'makeinfo'  => {
            'main'  => 'makeinfo'
        },
        'ncurses'   => {
            'devel' => 'ncurses-devel',
            'main'  => 'libncurses6'
        },
        'patch'     => {
            'main'  => 'patch'
        },
        'zlib'      => {
            'devel' => 'zlib-devel',
            'main'  => 'libz1'
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

our sub install_pkg ($self, $os, $variant, $pkg) {
    my $pkg_name = $pkg_map{$os}{$pkg}{$variant};

    print color('white');
    print STDOUT "Installing $pkg_name: ";
    print color('reset');
    given ($os_pkgmgr{$os}) {
        when ('zypper') {
            zypper_install($pkg_name);
        }
    }
}

true;