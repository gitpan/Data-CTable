#!/usr/bin/perl
## Emacs: -*- tab-width: 4; -*-

sub Usage
{
	return << "END";
Usage:

$0 ZipCode [StartHourFromNow] [StartDayFromNow]

getweather is a utility that uses LWP::Simple and Data::CTable to
convert a local weather report from weather.com into a text-based
tabular report.

The URL it gets its data from is something like this:

http://www.weather.com/weather/hourbyhour/94062?dayNumber=1&hour=0

ZipCode is the required US zip code to ask about (e.g. 94062)

The other parameters don't seem to be working with anything but their
default values for now, so you might not be able to use them:

StartHourFromNow is how many hours in future to begin table (default 0).

StartDayFromNow is how many days in future to begin table (default 1).

Program output should look something like this:

 +-----+--------+-------+---------------+------+-------+------+-----+-----------+--------+
 | Day |  Date  | Hour  |   Forecast    | Temp | Feels | Dew  | Hum |   Wind    | Precip |
 +-----+--------+-------+---------------+------+-------+------+-----+-----------+--------+
 | Wed | Apr 24 | 5 AM  | Foggy         | 46 F | 45 F  | 41 F | 84% | W 3 mph   | 0%     |
 | Wed | Apr 24 | 6 AM  | Foggy         | 47 F | 47 F  | 42 F | 83% | WSW 3 mph | 0%     |
 | Wed | Apr 24 | 7 AM  | Foggy         | 48 F | 48 F  | 42 F | 80% | WSW 3 mph | 0%     |
 | Wed | Apr 24 | 8 AM  | Foggy         | 51 F | 51 F  | 43 F | 74% | SW 3 mph  | 0%     |
 | Wed | Apr 24 | 9 AM  | Partly Cloudy | 54 F | 54 F  | 43 F | 67% | SW 3 mph  | 0%     |
 | Wed | Apr 24 | 10 AM | Partly Cloudy | 58 F | 58 F  | 44 F | 60% | WSW 4 mph | 0%     |
 | Wed | Apr 24 | 11 AM | Partly Cloudy | 61 F | N/A   | 44 F | 53% | W 5 mph   | 0%     |
 | Wed | Apr 24 | 12 PM | Partly Cloudy | 64 F | N/A   | 44 F | 48% | W 6 mph   | 0%     |
 +-----+--------+-------+---------------+------+-------+------+-----+-----------+--------+

This program makes a few assumptions about the HTML code generated by
weather.com.  Changes in the output there could make the program stop working.

This tool is part of the Data::CTable distribution.

Copyright (c) 1995-2002 Chris Thorman.  All rights reserved.  

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

See Data::CTable home page for further info:

	http://christhorman.com/projects/perl/Data-CTable/

END
;
}

use strict;

use LWP::Simple	 qw(get $ua);
use Data::CTable qw(min max);

## Data::CTable does not require Data::ShowTable, but its out() method
## does, so we opt to fail here rather than just get a warning from
## $t->out().

use Data::ShowTable;	

## Get command-line args and defaults.
my ($Zip, $Hours, $Days) = @ARGV;
int($Zip)		> 0 or die &Usage();
$Zip			= sprintf("%05d", $Zip);
$Hours			= int($Hours);	$Hours ||= 0;
$Days			= int($Days);	$Days  ||= 1;

## Be IE.
$ua->{agent}	= "Mozilla/4.0 (compatible; MSIE 5.5; Windows 98)";

## Get the data.
my $URL			= "http://www.weather.com/weather/hourbyhour/$Zip?dayNumber=$Days&hour=$Hours";
my $HTML		= get($URL) or die "Failed to get $URL (no network connection?)\n";

## Create a trivial text-only version of the page to display in case
## we can not extract the tabular weather data we want.

my $Clean		= $HTML;
$Clean =~ s/<!--.*?-->/ /gs;
$Clean =~ s/<BR>/\n/gis;
$Clean =~ s/<.*?>/ /gs;
$Clean =~ s/&nbsp;/ /gis;
$Clean =~ s/(\s*\n\s*)+/\n/g;
$Clean =~ s/[ \t]+/ /g;
$Clean =~ s/^[ \t]+//gm;

## Find a table on the page that mentions "dewpoint"

my $Tables		= [$HTML =~ m(<TABLE.*?>(.*?)</TABLE>)gsi];
my $Table		= (grep {/dewpoint/i} @$Tables)[0] or die $Clean;

## Clean HTML code in table to remove any JavaScript lossage.
$Table			=~ s(<SCRIPT.*?>(.*?)</SCRIPT>)()gsi;

## Extract row and cell contents.  Some rows will not have all cells.
my $Rows		= [$Table =~ m(<TR.*?>(.*?)</TR>)gsi];
my $Cells		= [map {[m(<TD.*?>(.*?)</TD>)gsi]} @$Rows];

## Count the columns and make up some temporary field names F01, F02,etc.
my $ColCount	= 0; foreach (@$Cells) {$ColCount = max($ColCount, @$_+0)};
my $ColNames	= ['F01'..'F'.sprintf("%02d", $ColCount)];

## Convert the row-oriented data to a column-oriented storage format.
my $Cols		= [map {my $C = $_; [map {$_->[$C]} @$Cells]} (0..$ColCount-1)];

## Instantiate a Data::CTable to hold the data.
my $t			= {}; @$t{@$ColNames} = @$Cols;
my $t			= Data::CTable->new({%$t, _MaxWidth => 35});

## Convert HTML-ish cell contents to text-ish format.
$t->clean(sub {s([\x0D\x0A]+)( )gs});
$t->clean(sub {s(&nbsp;)( )gs});
$t->clean(sub {s(&deg;)(\xB0)gs});	## ISO 8859-1 degree symbol.
$t->clean(sub {s(<BR>)( )gsi});
$t->clean(sub {s(<.*?>)()gs});
$t->clean_ws();

## Truncate table following the "Chance of precipitation" row
$t->select(F01 => sub {/chance/i});
$t->length($t->selection()->[0]+1) if @{$t->selection()};
$t->select_all();

## Remove any rows that are empty in the third column (F03)
$t->select(F03 => sub {!/^$/i});
$t->cull();

## Remove any columns that are empty
my $EmptyCols	= [grep {!grep {length} @{$t->col($_)}} @{$t->fieldlist()}];
foreach (@$EmptyCols) {$t->col_delete($_)};

## Add missing data labels in temporary column F01 for first two data fields.
$t->col('F01')->[0] = "Day";
$t->col('F01')->[1] = "Date";

## "Flip" the table so the labels in F01 become the field names (rows <==> columns)
$t->invert('F01');

## Shorten some field names for a narrower final output.
$t->col_rename('Weather Forecast'	=>	'Forecast');
$t->col_rename('Chance of Precip.'	=>	'Precip');
$t->col_rename('Temperature'		=>	'Temp');
$t->col_rename('Feels Like'			=>	'Feels');
$t->col_rename('Dewpoint'			=>	'Dew');
$t->col_rename('Humidity'			=>	'Hum');

## Modify the field list so a NEW 'Hour' field precedes 'Forecast'.
$t->fieldlist([map {($_ eq 'Forecast' ? (qw(Hour Forecast)) : $_)} @{$t->fieldlist()}]);

## Remove the time info from the Forecast field and insert it into Hour instead.
$t->calc(sub {$main::Hour = ($main::Forecast =~ s{^(.*?[AP]M) }{}i ? $1 : undef)});

## Shorten the verbosity of the Wind field.
my $Dirs    = {qw(WEST W SOUTH S NORTH N EAST E)};
$t->clean(sub {s((\w{4,5}))($Dirs->{uc($1)}||$1)ge  }, [qw(Wind)]);
$t->clean(sub {s(([NSEW]{1,2}) ([NSEW]{1,2}))($1$2)g}, [qw(Wind)]);
$t->clean(sub {s((From the )|( at ))( )gs           }, [qw(Wind)]);

## Remove stubborn leading space remaining in Wind field.
$t->clean_ws();

## Print a nice table in text format (assuming Data::ShowTable is installed)
$t->out();

## Could also do something else with the data here, like write it to a
## file, etc.
