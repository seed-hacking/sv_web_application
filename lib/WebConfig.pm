package WebConfig;

use strict;
use warnings;

use base qw(Exporter);
our @EXPORT = qw ( CSS_PATH TMPL_PATH JS_PATH IMAGES HMTL_PATH CGI_PATH TEMP_PATH TMPL_URL_PATH CFG_PATH );
use Tracer;
use FIG_Config;

1;

#******************************************************************************
#* GLOBAL CONFIGURATION
#******************************************************************************

#
# File system path configurations.
#
use constant TMPL_PATH  => "$FIG_Config::templates/";
use constant TMPL_URL_PATH  => "./Html/";
sub CFG_PATH () {
    if ($ENV{KB_TOP})
    {
	"$ENV{KB_TOP}/lib/WebApplication/";
    }
    else
    {
	"$FIG_Config::fig_disk/config/WebApplication/";
    }
}
				    
#use constant CFG_PATH   => "$FIG_Config::fig_disk/config/WebApplication/";
use constant TEMP_PATH  => $FIG_Config::temp;
#
# URL path configurations.
#
use constant CGI_PATH   => "$FIG_Config::cgi_url/";
use constant CSS_PATH   => "$FIG_Config::cgi_url/Html/";
use constant JS_PATH    => "$FIG_Config::cgi_url/Html/";
use constant IMAGES     => "$FIG_Config::cgi_url/Html/";
use constant HTML_PATH  => "$FIG_Config::cgi_url/Html/";

#
# Database settings
#
our $DBNAME = 'WebAppBackend';
our $DBHOST = 'localhost';
our $DBUSER = 'root';
our $DBPWD  = '';
our $DBPORT = undef;
our $NODB   = $FIG_Config::noWebAppDB;
#
# Default values for the web application
#
our $APPLICATION_NAME = 'WebApplication';
our $APPLICATION_URL  = 'http://bioseed.mcs.anl.gov/';
our $ADMIN_EMAIL = 'paczian@mcs.anl.gov';

#
# Login dependencies are used to grant login rights
# to web applications a backend depends on. 
# rf. to User->grant_login_right
#
our $LOGIN_DEPENDENCIES = { 'RAST'       => [ 'SeedViewer', 'MGRAST', 'PRAST' ],
			    'SeedViewer' => [ 'RAST', 'MGRAST', 'PRAST' ],
			    'MGRAST'     => [ 'RAST', 'SeedViewer', 'PRAST' ],
			    'PRAST'      => [ 'RAST', 'SeedViewer', 'MGRAST' ] };


#
# Load the WEbApplication config file so we can
# have a deployment set the defaults
#

import_local_config("WebApplication");

#
# Method to import local configurations 
# from config/WebApplication/BackendName.cfg
#
sub import_local_config {
  my $application = shift;
  if (ref($application)) {
    $application = $application->backend->name();
  }
  no strict;
  {
    my $local = CFG_PATH.$application.'.cfg';
    unless ($return = do $local) {
      if ($@) {
        Warn("Couldn't parse $local: $@") if T(0);
      } elsif (! defined $return) {
        Warn("Couldn't do $local.") if T(1);
      } elsif (! $return) {
        Warn("Couldn't run $local.") if T(1);
      }
    }
  }
}

1;
