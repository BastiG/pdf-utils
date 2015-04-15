#!/bin/perl -CA

use strict;
use warnings;
use utf8;
use PDF::API2;
use File::Basename;

###
# Basic checks
# Command line parameter count, input file exists
##

if ($#ARGV != 1)
{
	print "Usage: $0 file.pdf stamp_text\n";
	exit;
}

my $in_file = $ARGV[0];
my $stamp_text = $ARGV[1];;

unless (-e $in_file)
{
	print "File '$in_file' does not exist\n";
	exit;
}

###
# Set output filename file.pdf => file.stamped.pdf
###

binmode(STDOUT, ":utf8");

my ($in_filename, $in_path, $in_suffix) = fileparse($in_file, qr/\.[^.]*/);
my $out_file = $in_path.$in_filename.'.stamped'.$in_suffix;
my $count = 1;
while (-e $out_file)
{
	$out_file = $in_path.$in_filename.'.stamped-'.$count++.$in_suffix;
}

print "Stamping $in_file with '$stamp_text' ... ";

###
# Constants
###

my $bullet = "\x{2022}";
my $font_name = '/usr/share/fonts/TTF/DejaVuSans-Bold.ttf';
my $font_size = 20;
my $print_border = 20;

my $font_offset_y = $font_size / 3;
my $stamp_add = '   '.$bullet.' '.$bullet.' '.$bullet.'   '.$stamp_text;

###
# PDF handling
###

my $pdf = PDF::API2->open($in_file);

# 30% transparency for watermark
my $eg_transparent = $pdf->egstate();
$eg_transparent->transparency(0.7);

my $font = $pdf->ttfont($font_name);

for (my $index = 0; $index < $pdf->pages(); ++$index)
{
	# get page at index
	my $page = $pdf->openpage($index);
	my ($ox, $oy, $width, $height) = $page->get_mediabox();

	# add transparent text
	my $text = $page->text();
	$text->font($font, $font_size);
	$text->egstate($eg_transparent);

	# determine stamp, respecting page width and printer bounds
	my $stamp = $stamp_text;
	while ($text->advancewidth($stamp.$stamp_add) < $width - 2 * $print_border)
	{
		$stamp = $stamp.$stamp_add;
	}

	# print the footer watermark
	$text->translate($width / 2, $font_offset_y + $print_border);
	$text->text_center($stamp);

	# print the header watermark
	$text->translate($width / 2, $height - 20 - $print_border);
	$text->text_center($stamp);
}

print "done.\nSaving as $out_file\n";

# save
$pdf->saveas($out_file);
