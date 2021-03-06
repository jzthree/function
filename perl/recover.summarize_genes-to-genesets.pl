#!/usr/bin/perl

# ================================================
# Name : summarize_genes-to-genesets.pl
# Purpose : Summarize gene-scores to geneset-scores
# Created : 01-05-2014
# Last Modified : Thu 08 Jan 2015 11:33:52 AM EST
# Author(s) : Arjun Krishnan
# ================================================

use strict;
use warnings;
use Getopt::Long;
use Pod::Usage;
use List::Util qw(shuffle);


my ($help, $itab, $igmt, $otab);
my $irand = 100000; my $iming = 5; my $imaxg = 100;
#my $irand = 100000; my $iming = 5; my $imaxg = 2000;
pod2usage( -exitstatus => 2, -verbose => 2 ) if (@ARGV==0);
GetOptions(  'help' => \$help,
           'itab=s' => \$itab,
           'igmt=s' => \$igmt,
          'iming=i' => \$iming,
          'imaxg=i' => \$imaxg,
          'irand=i' => \$irand,
           'otab=s' => \$otab   ) or pod2usage( -exitstatus => 2, -verbose => 2 );
pod2usage( -exitstatus => 2, -verbose => 2 ) if ($help);

# (my $otab = $itab) =~ s/\.txt$/\.$igmt/g;
# $otab =~ s/\.gmt$/\.summary\.txt/g;


my %gene_score = ();
open TAB, "$itab" or die "Can't open $itab!";
while (<TAB>) {
    if($_ =~ /^#/) { next; }
    chomp($_); my @p = split '\t', $_;
    if($p[1] eq 'NA') { next; }
    $gene_score{$p[0]} = $p[1]; }
close TAB;

my @gene_scores = values %gene_score;


my %gs_desc = my %gs_size = ();
my %size_gs = my %gs_score = ();
open GMT, "$igmt" or die "Can't open $igmt!";
while (<GMT>) {
    if($_ =~ /^#/) { next; }
    chomp($_); my @p = split '\t', $_;
    my $gs = shift @p;
    $p[0] =~ s/ \([0-9]*\)$//g; $gs_desc{$gs} = shift @p;

    my %genes = ();
    foreach my $g (@p) {
        unless(exists $gene_score{$g}) { next; }
        #$gs_genes{$gs}{$g}++; }
        $genes{$g}++; }

    #my $size = scalar keys %gs_genes;
    my $size = scalar keys %genes;
    if(($size < $iming) or ($size > $imaxg)) { next; }

    $gs_size{$gs} = $size;
    $size_gs{$size}{$gs}++;

    $gs_score{$gs} = 0; my $n = 0;
    foreach my $g (keys %genes) {
        $n++;
        $gs_score{$gs} += (($gene_score{$g} - $gs_score{$gs}) / $n); } }
close GMT;


my %gs_pval = ();
foreach my $size (sort {$a <=> $b} keys %size_gs) {
    my %pval = emp_dist(\@gene_scores, \%gs_score, $size_gs{$size}, $size);

    foreach my $gs (keys %pval) {
        $gs_pval{$gs} = $pval{$gs}; } }


my %gs_qval = get_esfdr(\%gs_pval);
open OUT, ">$otab";
print OUT "#gs\tdesc\tsize\tmean.score\tpvalue\tneglog.qvalue\n";
foreach my $gs (sort {$gs_qval{$b} <=> $gs_qval{$a}} keys %gs_qval) {
    print OUT "$gs\t$gs_desc{$gs}\t$gs_size{$gs}\t$gs_score{$gs}\t";
    printf OUT "%.6g\t%.6f\n", $gs_pval{$gs}, $gs_qval{$gs}; }
close OUT;




# Get P-values based on empirical distribution
sub emp_dist {
    my $scores = shift;
    my $gsscore = shift;
    my $gsref = shift;
    my $size = shift;

    my %remain_gs = %{$gsref};

    my %exc = my %pvalue = ();
    foreach my $gs (keys %remain_gs) {
        $exc{$gs} = 1; $pvalue{$gs} = 1/$irand; }

    # print "$size genes; ", scalar keys %remain_gs, " genesets \n";
    for(my $r=1; $r<$irand; $r++) {
        # unless($r % 100) { print "\t$r ...\n"; }

        my @shuf_idx = shuffle(0..$#{$scores});
        my @pick_idx = @shuf_idx[ 0 .. ($size-1) ];
        my @rands = @{$scores}[ @pick_idx ];
        
        my $rmean = 0;
        for(my $s=0; $s<$size; $s++) {
            $rmean += (($rands[$s] - $rmean) / ($s + 1)); }

        foreach my $gs (keys %remain_gs) {
            if(abs($rmean) >= abs($gsscore->{$gs})) {
                $exc{$gs}++; }
            if($r < 10) {
                next; }

            my $pval = ( $exc{$gs} / ($r+1) );

            # if($pval > ( 10 / ($r+1) )) {
            if( $exc{$gs} >  10 ) {
                $pvalue{$gs} = $pval;
                delete $remain_gs{$gs}; } }

        if(scalar keys %remain_gs == 0) { last; } }

    return %pvalue; }


# Performs multiple-hypothesis correction using BH method
sub get_esfdr {
    my $pref = shift;
    
    my $minp = 1; my $ntests = 0;
    foreach (keys %{$pref}) {
        $ntests++;
        if(($pref->{$_} != 0) 
                and ($pref->{$_} < $minp)) {
            $minp = $pref->{$_}; } }

    my %esfdr = (); my $rank = $ntests;
    my $prev_qval = my $curr_qval = 1;

    foreach (sort {$pref->{$b} <=> $pref->{$a}} keys %{$pref}) {
        my $pvalue = $pref->{$_};

        if($pvalue == 0) {
            $curr_qval = ($minp * $ntests) / ($rank * 10); }
        else {
            $curr_qval = ($pvalue * $ntests) / $rank; }

        my $qvalue = 1;
        if($prev_qval < $curr_qval) {
            $qvalue = $prev_qval; }
        else {
            $qvalue = $curr_qval;
            $prev_qval = $curr_qval; }

        $esfdr{$_} = (-1)*log($qvalue)/log(10);
        if($esfdr{$_} < 0) { $esfdr{$_} = 0; }

        $rank--; }

    return %esfdr; }

