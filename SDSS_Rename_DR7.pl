#! /usr/bin/perl
use strict;
use warnings;
use PGPLOT;
use Text::CSV;
use Cwd qw(cwd);
#use String::Scanf;
use Statistics::OLS;
use PDL;
use PDL::Graphics2D;
use PDL::Constants qw(PI);
use PDL::Fit::Polynomial qw(fitpoly1d);
$ENV{PGPLOT_FOREGROUND} = "black";
$ENV{PGPLOT_BACKGROUND} = "white";

#This script generates:
#renaming IRAF scripts for SDSS FpC image, atlas files
#renaming shell script for PSFs
#PSF modifying script for IRAF
#wget lists for downloading PSFs and calibration files

#opendir my $fdDir, cwd() or die "Unable to open cwd: $!\n"; #opens current working directory 
#
#my $ins;
#while (my $file = readdir $fdDir)
#	{
#	chomp $file; 
#	next unless $file =~ m/^FVnyu(.+)\.aperture\.csv$/; # read only files that began with m/^cnyu\ and end with .csv$/
#	$ins = $1;
##	print " FVnyu$ins.aperture.csv\n";
#	}

#SDSS_Positions_Size.csv can be any SDSS SQL output that contains name/name/ID, x, y, run#, field#, camcol
#Here, a generic CSV is assumed.
open my $inPositions, '<', "result_DR7.csv" or die "cannot open result_DR7.csv: $!"; 
my $input_positions = Text::CSV->new({'binary'=>1});
$input_positions->column_names($input_positions->getline($inPositions));
my $position_inputs = $input_positions->getline_hr_all($inPositions);

#It may be necessary to change target column names. A global find/replace is best, given the large number of hardcoded entries.
my @nyuID = map {$_->{'col0'}} @{$position_inputs}; #Object ID (nyu#)
my @px = map {$_->{'imgx'}} @{$position_inputs};
my @py = map {$_->{'imgy'}} @{$position_inputs};
my @run = map {$_->{'run'}} @{$position_inputs};
my @rerun = map {$_->{'rerun'}} @{$position_inputs};
my @cam = map {$_->{'camcol'}} @{$position_inputs};
my @field = map {$_->{'field'}} @{$position_inputs};

open my $PSF_CUT, '>', "PSF_DR7.cl" or die "cannot open PSF_DR7: $!"; #PSF cutout
open my $cutouts, '>', "Rename_Atlas_DR7.cl" or die "cannot open Rename_Images.cl: $!"; #IRAF
open my $Objects, '>', "Rename_Objects_DR7.cl" or die "cannot open Rename_Objects.cl: $!"; #IRAF
open my $PSFimages, '>', "Rename_PSF_DR7.sh" or die "cannot open Rename_PSF.sh: $!"; #Not IRAF!
open my $psflist, '>', "sdss-wget-PSF_DR7.lis" or die "cannot open sdss-wget-PSF_DR7.lis: $!"; #wget...
open my $calfiles, '>', "sdss-wget-Calibration_DR7.lis" or die "cannot open sdss-wget-Calibration.lis: $!"; #wget...

my $A = "fpAtlas";
my $Ap = "Atlas";
my $O ="fpC";
my $DR7 = "_DR7";
my $I = "psField";
my $J = "psf";
my $cal ='calibPhotm';
my @band = qw/ u g r i z/; #sloan filters
my $run0;
my $field0;

#example wgets
#wget "http://das.sdss.org/imaging/5071/$_->{'rerun'}/objcs/1/fpAtlas-005071-1-0111.fit"
#wget "http://das.sdss.org/imaging/5071/$_->{'rerun'}/objcs/1/fpObjc-005071-1-0111.fit"
#wget "http://das.sdss.org/imaging/5071/$_->{'rerun'}/objcs/1/psField-005071-1-0111.fit"

#calibPhotom-RUN6-CAMCOL.fits
#photoObj-RUN6-CAMCOL-FIELD4.fits


my $i=0;
for (grep {$_->{'col0'}} @{$position_inputs})
{ 
local $, = ' ';
local $\ = "\n";
foreach my $n (1.. 5) { #iterate over all 5 bands (u, g, r, i, z) Would be better if user-controlled.

#padding 0s
if ($_->{'run'} >= 1000) {
	$run0 = "00";
} elsif ($_->{'run'} >= 100) {
	$run0 = "000";
} elsif ($_->{'run'} >= 10) {
	$run0 = "0000";
} else { #run is 0 - 9
	$run0 = "00000";
}
if ($_->{'field'} >= 100) {
	$field0 = "0";
} elsif ($_->{'field'} >= 10) {
	$field0 = "00";
} else { #field is 0 - 9
	$field0 = "000";
}

	#PSF (multicolored)
	print $PSF_CUT "imcopy psf.$_->{'col0'}$band[$n-1]_DR7.fits[12:42,12:42] cpsf.$_->{'col0'}$band[$n-1]_DR7.fits";
	print $PSF_CUT "imarith cpsf.$_->{'col0'}$band[$n-1]_DR7.fits - 1000 scpsf.$_->{'col0'}$band[$n-1]_DR7.fits";

	#atlas image
	print $cutouts 'imcopy',$A.'-'.$run0.$_->{'run'}.'-'.$_->{'camcol'}.'-'.$field0.$_->{'field'}.'.'.'fit',$_->{'col0'}.'.'.$Ap.$DR7.'.'.'fits';
	print 'imcopy',$A.'-'.$run0.$_->{'run'}.'-'.$_->{'camcol'}.'-'.$field0.$_->{'field'}.'.'.'fit',$_->{'col0'}.'.'.$Ap.$DR7.'.'.'fits';

	#Object frame (multicolored)
	print $Objects 'imcopy',$O.'-'.$run0.$_->{'run'}.'-'.'r'.$_->{'camcol'}.'-'.$field0.$_->{'field'}.'.'.'fit',$_->{'col0'}.$DR7.'.'.'fits';
	print 'imcopy',$O.'-'.$run0.$_->{'run'}.'-'.'r'.$_->{'camcol'}.'-'.$field0.$_->{'field'}.'.'.'fit',$_->{'col0'}.$DR7.'.'.'fits';
	
	#PSF wget list
	print $psflist "http://das.sdss.org/imaging/$_->{'run'}/$_->{'rerun'}/objcs/$_->{'camcol'}/psField-$run0$_->{'run'}-$_->{'camcol'}-$field0$_->{'field'}.fit";
	print "http://das.sdss.org/imaging/$_->{'run'}/$_->{'rerun'}/objcs/$_->{'camcol'}/psField-run0$_->{'run'}-$_->{'camcol'}-$field0$_->{'field'}.fit";
	print $calfiles "http://das.sdss.org/imaging/$_->{'run'}/$_->{'rerun'}/objcs/$_->{'camcol'}/$cal-$run0$_->{'run'}-$_->{'camcol'}.fit";	

	#PSF image (multicolored)
	print $PSFimages 'read_PSF',$I.'-'.$run0.$_->{'run'}.'-'.$_->{'camcol'}.'-'.$field0.$_->{'field'}.'.'.'fit','3',$_->{'imgx'},$_->{'imgy'},$J.'.'.$_->{'col0'}.$DR7.'.'.'fits';
	print 'read_PSF',$I.'-'.$run0.$_->{'run'}.'-'.$_->{'camcol'}.'-'.$field0.$_->{'field'}.'.'.'fit','3',$_->{'imgx'},$_->{'imgy'},$J.'.'.$_->{'col0'}.$DR7.'.'.'fits';
	}
}

print "Files renamed\n";
