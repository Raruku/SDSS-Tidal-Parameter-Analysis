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
open my $inPositions, '<', "result_S82.csv" or die "cannot open result_S82.csv: $!"; 
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

open my $PSF_CUT, '>', "PSF_S82.cl" or die "cannot open PSF_S82: $!"; #PSF cutout and subtraction. Run in IRAF after renaming.
open my $cutouts, '>', "Rename_Atlas_S82.cl" or die "cannot open Rename_Images.cl: $!"; #IRAF
open my $Objects, '>', "Rename_Objects_S82.cl" or die "cannot open Rename_Objects.cl: $!"; #IRAF
open my $PSFimages, '>', "Rename_PSF_S82.sh" or die "cannot open Rename_PSF.sh: $!"; #Not IRAF!
open my $psflist, '>', "sdss-wget-PSF_S82.lis" or die "cannot open sdss-wget-PSF_S82.lis: $!"; #wget...
#~ open my $calfiles, '>', "sdss-wget-Calibration_S82.lis" or die "cannot open sdss-wget-Calibration.lis: $!"; #wget...
#~ open my $ObjectW, '>', "sdss-wget-Objects_S82.lis" or die "cannot open sdss-wget-Objects_S82.lis: $!"; #hack to deal with the wget that's autogenerated being wrong.

my $A = "fpAtlas";
my $Ap = "Atlas";
my $O ="fpC";
my $S82 = "_S82";
my $I = "psField";
my $J = "psf";
my $cal ='calibPhotm';
my @band = qw/ u g r i z/; # will work best if 1-indexed. Especially for the PSF

#example wgets
#wget "http://das.sdss.org/imaging/5071/$_->{'rerun'}/objcs/1/fpAtlas-005071-1-0111.fit"
#wget "http://das.sdss.org/imaging/5071/$_->{'rerun'}/objcs/1/fpObjc-005071-1-0111.fit"
#wget "http://das.sdss.org/imaging/5071/$_->{'rerun'}/objcs/1/psField-005071-1-0111.fit"

#calibPhotom-RUN6-CAMCOL.fits
#photoObj-RUN6-CAMCOL-FIELD4.fits

#my $i=0;
my $run0;
my $field0;
for (grep {$_->{'col0'}} @{$position_inputs})
{ 
	local $, = ' ';
	local $\ = "\n";

	#spacing and sizing is hard. This will fail in interesting ways if the naming changes.
	if ($_->{'run'} == 106) {
		$run0 = 100006;
	} else { #run == 206
		$run0 = 200006;
	}

	if (($_->{'field'} < 1000) && ($_->{'field'} >= 100)) { #3 digit field, so 1x 0 for padding
		$field0 = '0';
	} elsif ($_->{'field'} >= 10) { #2 digit field, so 2x padding
		$field0 = '00';
	} elsif ($_->{'field'} < 10) { #1 digit field needs 3x 0 padding
		$field0 = '000';
	} else {
		$field0 = ''; #4 digit fields need no 0s for padding. Also default-ish.
	}
	#example:
	#run 3704, rerun 301, camcol 3, field 91
	#http://data.sdss3.org/sas/dr9/boss/photoObj/frames/301/3704/3/frame-g-003704-3-0091.fits.bz2
	foreach my $n (1.. 5) { #iterate over all 5 bands (u, g, r, i, z) Would be better if user-controlled.
		#PSF cutout and subtraction
		print $PSF_CUT "imcopy psf.$_->{'col0'}$band[$n-1]_S82.fits[12:42,12:42] cpsf.$_->{'col0'}$band[$n-1]_S82.fits";
		print $PSF_CUT "imarith cpsf.$_->{'col0'}$band[$n-1]_S82.fits - 1000 scpsf.$_->{'col0'}$band[$n-1]_S82.fits";

		#Object frame
		print $Objects 'imcopy',$O.'-'.$run0.'-'.$band[$n-1].$_->{'camcol'}.'-'.$field0.$_->{'field'}.'.'.'fit',$_->{'col0'}.$S82.'.'.'fits'; #Rename
		print 'imcopy',$O.'-'.$run0.'-'.$band[$n-1].$_->{'camcol'}.'-'.$field0.$_->{'field'}.'.'.'fit',$_->{'col0'}.$S82.'.'.'fits';
		print $Objects 'imarith',$_->{'col0'}.$S82.'.'.'fits','+ 1000',$_->{'col0'}.$S82.'.'.'fits'; #adding back light sky background to make comparable with DR7.
		print 'imarith',$_->{'col0'}.$S82.'.'.'fits','+ 1000',$_->{'col0'}.$S82.'.'.'fits';

		#PSF wget list
		print $psflist "http://das.sdss.org/imaging/$run0/$_->{'rerun'}/objcs/$_->{'camcol'}/$I-$run0-$_->{'camcol'}-$field0$_->{'field'}.fit";
		print "http://das.sdss.org/imaging/$run0/$_->{'rerun'}/objcs/$_->{'camcol'}/$I-$run0-$_->{'camcol'}-$field0$_->{'field'}.fit";

		#PSF image
		print $PSFimages 'read_PSF',$I.'-'.$run0.'-'.$_->{'camcol'}.'-'.$field0.$_->{'field'}.'.'.'fit',$n,$_->{'imgx'},$_->{'imgy'},$J.'.'.$_->{'col0'}.$band[$n-1].$S82.'.'.'fits';
		print 'read_PSF',$I.'-'.$run0.'-'.$_->{'camcol'}.'-'.$field0.$_->{'field'}.'.'.'fit',$n,$_->{'imgx'},$_->{'imgy'},$J.'.'.$_->{'col0'}.$band[$n-1].$S82.'.'.'fits';
	}
}

print "Files renamed\n";
