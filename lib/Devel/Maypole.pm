package Devel::Maypole;

use warnings;
use strict;
use Carp();

use Maypole::Config;
use File::Temp;
use File::Slurp;
use File::Copy::Recursive;
use Path::Class();
use Data::Dumper;
use DBI;    
use Sysadm::Install();

use base qw/ Exporter /;
use vars qw/ @EXPORT_OK %EXPORT_TAGS /;
@EXPORT_OK = qw/ database application install_templates /;
%EXPORT_TAGS = ( test    => [ qw/ database application / ],
                 install => [ qw/ install_templates /],
                 );

our $VERSION = '0.1';

# these have to stick around until the script exits, at which point, they 
# will be automatically unlinked
my ( $APP_FILE, $DB_FILE );

=head1 NAME

Devel::Maypole - support utilities for developing the Maypole stack

=head1 SYNOPSIS

    # In a test script:
    
    use Test::More tests => 42;
    
    use Devel::Maypole qw/:test/;
    
    my ( $database, $application );
    
    BEGIN { 
    
        $ENV{MAYPOLE_CONFIG}    = 'config/beerdb.simple.yaml';
        $ENV{MAYPOLE_TEMPLATES} = 't/templates';
    
        $database = database( ddl  => 'sql/ddl/beerdb.simple.sql',
                              data => 'sql/data/beerdb.simple.sql',
                              );
        
        $application = application( plugins => [ qw( Config::YAML AutoUntaint Relationship ) ],
                                    );    
    }
    
    use Test::WWW::Mechanize::Maypole $application, $database;
    
    # ----- BEGIN TESTING -----
    
    # frontpage
    {   
    
        my $mech = Test::WWW::Mechanize::Maypole->new;
        $mech->get_ok("http://localhost/beerdb/");
        
        $mech->content_contains( 'This is the frontpage' );
        
        is($mech->ct, "text/html");
        is($mech->status, 200);
    }
    
    
    # --------------------------------------
    # In an installation script:
    
    use Maypole::Devel qw/:install/;
    
    # optionally suppress interactive questions:
    # $ENV{MAYPOLE_TEMPLATES_INSTALL_PREFIX} = '/usr/local/maypole';
    
    install_templates( 'Maypole::Plugin::Foo', 'distribution-templates-dir/set1', 'set1' );
            
=head1 DESCRIPTION

Builds a database and a simple application driver, ready to use in test scripts for Maypole 
plugins and components.
    
=head1 EXPORTS

Nothing is exported by default. You can import individual functions, or groups, using these 
tags:

    tag         functions
    --------------------------------
    :test       database application
    :install    install_templates    

=head1 TESTING UTILITIES

=over 4

=item database

Builds and populates an SQLite database in a temporary file, and returns a DBI connection 
string to the database. 

Suitable SQL files are included in the distribution to build a reasonably complex 
version of the beer database.

Returns a DBI connection string.

Options:

=over 4

=item ddl

Name of the SQL DDL (schema) file to use. A couple of suitable files are included at C<sql/ddl/beerdb.default.sql> 
and C<sql/ddl/beerdb.simple.sql> in this distribution. 

=item data

Name of the SQL data file to use. Suitable files are included at C<sql/data/beerdb.default.sql> 
and C<sql/data/beerdb.simple.sql> in this distribution. 

=item unlink 

Set false to not unlink the generated database file. Default true (unlink when script exits).

=back

=cut

sub database
{
    my %args = @_;
    
    my $ddl  = $args{ddl}  || die 'need a DDL file';
    my $data = $args{data} || die 'need a data file';
    my $unlink  = defined $args{unlink} ? $args{unlink} : 1;
    
    $DB_FILE = File::Temp->new( TEMPLATE => 'MaypoleTestDB_XXXXX',
                                SUFFIX   => '.db',
                                UNLINK   => $unlink,
                                );
                                
    $DB_FILE->close; # or SQLite thinks it's locked

    my $driver = 'SQLite';
    
    eval { require DBD::SQLite } or do {
        warn "Error loading DBD::SQLite, trying DBD::SQLite2\n";
        eval {require DBD::SQLite2} ? $driver = 'SQLite2'
            : die "DBD::SQLite2 is not installed";
    };
    
    my $connect = "dbi:$driver:dbname=$DB_FILE";
    
    my $dbh = DBI->connect( $connect );
    
    my $ddl_sql  = read_file( $ddl );
    my $data_sql = read_file( $data );
    
    my $sql = $ddl_sql.';'.$data_sql;

    foreach my $statement ( split /;/, $sql ) 
    {
        $statement =~ s/\#.*$//mg;           # strip # comments
        $statement =~ s/auto_increment//g;
        next unless $statement =~ /\S/;
        eval { $dbh->do($statement) };
        die "$@: $statement" if $@;
    }
    
    return $connect;                                    
}


=item application

Builds a simple Maypole driver in a temporary file in the current directory. 

Returns the package name of the application, which will be C<MaypoleTestApp_XXXXX> 
where C<XXXXX> are random characters.

Options:

=over 4

=item plugins

Arrayref of plugin names, just as you would supply to C<use Maypole::Application>.

See C<Custom driver code> below.

=item config

Hashref of Maypole options, or a Maypole::Config object. See C<Configuration> below.

=item unlink 

Set false to not unlink the generated application file. Default true (unlink when script exits).

=back

=cut

sub application
{
    my ( %args ) = @_;
    
    my @plugins = @{ $args{plugins} || [] };
    my $config  = $args{config} || {};
    my $unlink  = defined $args{unlink} ? $args{unlink} : 1;

    $APP_FILE = File::Temp->new( TEMPLATE => 'MaypoleTestApp_XXXXX',
                                 SUFFIX   => '.pm',
                                 UNLINK   => $unlink,
                                 );
                                 
    my $filename = $APP_FILE->filename;
    
    ( my $package = $filename ) =~ s/\..+$//;
    
    if ( ref $config eq 'HASH' )
    {
        $config = Maypole::Config->new( %$config );
    }
    
    my $cfg_str = Data::Dumper->Dump( [$config], ['$config'] );
    
    my $plugins = @plugins ? "qw( @plugins )" : '';
    
    my $app_code = _application_template();
    
    $app_code =~ s/__APP_NAME__/$package/;
    $app_code =~ s/__PLUGINS__/$plugins/;
    $app_code =~ s/__CONFIG__/$cfg_str/;
    
    print $APP_FILE $app_code;
    
    $APP_FILE->close; # or else it can't be read later 
    
    return $package;
}

sub _application_template
{
return <<'';
package __APP_NAME__;
use strict;
use warnings;
use Maypole::Application __PLUGINS__;
my $config;
eval q~__CONFIG__~;
die $@ if $@;
__PACKAGE__->config( $config );
__PACKAGE__->setup;
1;

}

=back

=head2 Configuration

You can build up configuration data in your test script, either as a hashref or 
as a L<Maypole::Config> object, and supply that as the C<config> parameter to 
C<application()>. 

Alternatively, include L<Maypole::Plugin::Config::YAML> in the list of plugins, 
and set C<$ENV{MAYPOLE_CONFIG}> to the path to a config file. See the  
L<Maypole::Plugin::Config::YAML> docs for details.

This distribution includes a couple of canned config files, in the C<config> subdirectory. 

    $ENV{MAYPOLE_CONFIG} = 'path/to/config/beerdb.simple.yaml'; 
    $ENV{MAYPOLE_CONFIG} = 'path/to/config/beerdb.default.yaml'; 
    
You can considerably simplify your config by including L<Maypole::Plugin::AutoUntaint> 
in the list of plugins - the supplied config files assume this.

The supplied configs also assume L<Maypole::Plugin::Relationship> is included in the 
plugins. 

=head2 Custom driver code

If you need to add custom code to the application, you could put the code in 
a plugin, and supply the name of the plugin to C<plugins>.    
    
Alternatively, C<eval> code in your test script, e.g. from C<01.simple.t>:

    # For testing classmetadata
    eval <<CODE;
        sub $application\::Beer::classdata: Exported {};
        sub $application\::Beer::list_columns  { return qw/score name price style brewery url/};
    CODE

    die $@ if $@;
    
=head1 INSTALLATION SUPPORT

=over 4

=item install_templates( $for, $from, [ $to ] )

Installs a set of templates. 

This function is intended to be called from a command line script, such as a C<Makefile.PL> 
or C<Build.PL> script. It will ask the user to confirm install locations, unless 
C<$ENV{MAYPOLE_TEMPLATES_INSTALL_PREFIX}> is defined, in which case that location will be used 
as the root of the install location.

On Unix-like systems, the default install root is C</usr/local/maypole/templates>. 
On Windows, C<C:/Program Files/Maypole/templates>. 

C<$for> should be the name of a package. This will be converted into a subdirectory, e.g. C<Maypole::Plugin::Foo> 
becomes C<plugin/foo>. 

C<$from> is the relative path to the templates directory in your distribution, e.g. C<templates>. 

C<$to> is an optional subdirectory to install to. So if you say 

    install_templates( 'Maypole::Plugin::Foo', 'templates/set1', 'set1' )
    
the templates will be installed in C</usr/local/maypole/templates/plugin/foo/set1>.

=cut

sub install_templates
{
    my ( $for, $from, $to ) = @_;
    
    Sysadm::Install->import( qw/:all/ );
    
    $for  || die 'need a package name for installing templates';
    $from ||= ''; # unlikely
    $to   ||= ''; # unwise
    
    # stolen from TT Makefile.PL
    my ($WIN32, $FLAVOUR, $PREFIX, $IMAGES, $MAKE, @alt_prefixes);
    if ($^O eq 'MSWin32')   # any others also?
    {  
        $WIN32   = 1;
        $PREFIX  = 'C:/Program Files/Maypole';
        @alt_prefixes = ( 'C:/Program Files/Maypole2', 'C:/Program Files/Perl/Maypole', 
                            'C:/Program Files/Perl/Maypole2' );
    }
    else 
    {
        $WIN32   = 0;
        $PREFIX  = '/usr/local/maypole';
        @alt_prefixes = ( '/usr/local/maypole2', '/usr/lib/maypole', '/usr/lib/maypole2',
                          '/usr/local/lib/maypole','/usr/local/lib/maypole2', 
                          '/home/maypole', '/home/maypole2', 
                          '/usr/www/maypole', '/usr/www/maypole2', 
                          '/usr/local/www/maypole', '/usr/local/www/maypole2', 
                          );
    }
    
    $_ .= '/templates' for ( $PREFIX, @alt_prefixes );
    
    my $prefix = $ENV{MAYPOLE_TEMPLATES_INSTALL_PREFIX};
    
    if ( ! length $prefix )
    {
        my @prefix_opts = ( $PREFIX, @alt_prefixes, 'other', 'do not install templates' );
        
        $prefix = pick( 'Template installation location:', [ @prefix_opts ], 1 ); # default is #1
        
        return if $prefix eq 'do not install templates';
        
        $prefix = ask( 'Template installation location:', $PREFIX ) if $prefix eq 'other';
    }
        
    return unless length $prefix;
    
    $for =~ s|::|/|g;
    
    my $dest = Path::Class::Dir->new( '', map { split '/', $_ } $prefix, $for, $to );
    
    File::Copy::Recursive::dircopy( $from, $dest->stringify ) || Carp::croak "nothing copied: $!";
}

=back

=head1 TODO

Canned tests e.g. run_standard_tests( $application )

Complex schema, with sufficient data for paging. 

Add more template sets. 

Support for other RDBMS's (easy enough to implement, patches welcome).

=head1 AUTHOR

David Baird, C<< <cpan@riverside-cms.co.uk> >>

=head1 BUGS

Please report any bugs or feature requests to
C<bug-maypole-testtools@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Maypole-TestTools>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 ACKNOWLEDGEMENTS

=head1 COPYRIGHT & LICENSE

Copyright 2005 David Baird, All Rights Reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1; # End of Devel::Maypole::Test
