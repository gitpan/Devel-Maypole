use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'Devel::Maypole',
    license             => 'perl',
    dist_author         => 'David Baird <cpan@riverside-cms.co.uk>',
    dist_version_from   => 'lib/Devel/Maypole.pm',
    requires => {
        'Test::More' => 0,
        'Test::File' => 0,
        'Test::Exception' => 0,
        'Maypole::Config' => 0,
        'File::Temp' => 0,
        'File::Slurp' => 0,
        'Data::Dumper' => 0,
        'DBI' => 0,
        'Test::WWW::Mechanize::Maypole' => 0,
        'Sysadm::Install' => 0,
        'File::Copy::Recursive' => 0,
        'Path::Class' => 0,
    },
    add_to_cleanup      => [ 'Devel-Maypole*' ],
    create_makefile_pl  => 'passthrough',
);

$builder->create_build_script();
