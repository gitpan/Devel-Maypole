#!/usr/bin/perl
use strict;
use warnings;

use Test::More tests => 5;
use Test::Exception;
use Test::File;

use File::Temp();
use Path::Class();

use Devel::Maypole qw/:install/;

my $tempdir = File::Temp::tempdir( CLEANUP => 1 );

$ENV{MAYPOLE_TEMPLATES_INSTALL_PREFIX} = $tempdir;

lives_ok { install_templates( 'Devel::Maypole', 't/templates', 'test' ) } 'survived installing test templates';

my $dest_dir = Path::Class::Dir->new( '', map { split '/', $_ } $tempdir, 'Devel/Maypole/test/custom' );

my $source_dir = Path::Class::Dir->new( 't/templates/custom' );

while ( my $file = $source_dir->next ) 
{
    next unless -f $file;
    next if $file =~ /^\./;
    
    my $dest_file = $dest_dir->file( $file->basename );

    file_exists_ok( $dest_file );
}

