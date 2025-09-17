use strict;
use warnings;
use utf8;
use open ':std', ':encoding(UTF-8)';
use Text::CSV;
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Spec;
use File::Copy::Recursive qw(dircopy);
use POSIX qw(strftime);
use Data::UUID;

my $csv_file      = 'shosi.csv';
my $base_dir      = '02_assemble';
my $template_dir  = '00_templates';
my $combined_root = '03_combined';

my %combined_data;

my $csv = Text::CSV->new({ binary => 1, auto_diag => 1 });
open my $fh, "<:encoding(utf8)", $csv_file or die "Can't open CSV: $!";
my $first_line = <$fh>;
$first_line =~ s/^\x{FEFF}//;
seek($fh, 0, 0);

print "CSV open operation start\n";

while (my $row = $csv->getline($fh)) {
    next unless @$row >= 7;
    my $g_id          = $row->[1];
    my $title         = $row->[2];
    my $prefix        = $row->[3];
    my $combined_name = $row->[4];
    my $type          = $row->[5];
    next unless $combined_name;

    if ($type eq '素材') {
        my $folder_path   = File::Spec->catdir($base_dir, $prefix);
        my $image_dir     = File::Spec->catdir($folder_path, 'item', 'image');
        my $xhtml_dir     = File::Spec->catdir($folder_path, 'item', 'xhtml');
        my $source_opf    = File::Spec->catfile($folder_path, 'item', 'standard.opf');

        my $combined_dir  = File::Spec->catdir($combined_root, $combined_name);
        my $out_image_dir = File::Spec->catdir($combined_dir, 'item', 'image');
        my $out_xhtml_dir = File::Spec->catdir($combined_dir, 'item', 'xhtml');

        make_path($out_image_dir);
        make_path($out_xhtml_dir);

        if (-d $image_dir) {
            opendir(my $dh, $image_dir) or die "Can't open $image_dir: $!";
            foreach my $file (readdir($dh)) {
                next unless $file =~ /^(image)-(\d{4})\.jpg$/;
                my $from = File::Spec->catfile($image_dir, $file);
                my $to_name = "$1-$prefix$2.jpg";
                my $to = File::Spec->catfile($out_image_dir, $to_name);
                copy($from, $to) or warn "[失敗] 画像コピー: $from → $to\n";
            }
            closedir($dh);
        }

        if (-d $xhtml_dir) {
            opendir(my $dh, $xhtml_dir) or die "Can't open $xhtml_dir: $!";
            foreach my $file (readdir($dh)) {
                next unless $file =~ /^(p)-(\d{4})\.xhtml$/;
                my $from = File::Spec->catfile($xhtml_dir, $file);
                my $to_name = "$1-$prefix$2.xhtml";
                my $to = File::Spec->catfile($out_xhtml_dir, $to_name);
                open my $in,  "<:utf8", $from or die "Can't open $from: $!";
                my @lines = <$in>;
                close $in;
                for (@lines) {
                    s/(image-)(\d{4})(\.jpg)/$1 . $prefix . $2 . $3/e;
                }
                open my $out, ">:utf8", $to or die "Can't write $to: $!";
                print $out @lines;
                close $out;
            }
            closedir($dh);
        }

        my ($img_ref, $xhtml_ref, $spine_ref) = extract_opf_tags($source_opf);
        push @{ $combined_data{$combined_name}{image} }, @$img_ref;
        push @{ $combined_data{$combined_name}{xhtml} }, @$xhtml_ref;
        push @{ $combined_data{$combined_name}{spine} }, @$spine_ref;
    }
    elsif ($type eq '合本') {
        my $combined_dir = File::Spec->catdir($combined_root, $combined_name);
        my $output_opf   = File::Spec->catfile($combined_dir, 'item', 'standard.opf');

        unless (-d $combined_dir) {
            make_path($combined_dir) or die "[warn] target folder make error: $combined_dir\n";
            print "target folder made: $combined_dir\n";
        }

        my $result = dircopy($template_dir, $combined_dir);
        if ($result) {
            print "template copy: $template_dir → $combined_dir\n";
        } else {
            warn "[warn] temlate copy error: $template_dir → $combined_dir\n";
        }

        my ($img_ref, $xhtml_ref, $spine_ref) = (
            $combined_data{$combined_name}{image} || [],
            $combined_data{$combined_name}{xhtml} || [],
            $combined_data{$combined_name}{spine} || []
        );

        update_opf_template($row, $output_opf, $img_ref, $xhtml_ref, $spine_ref);
    }
}

close $fh;

# 修正点
# 1. 著者名のカタカナ取得ミス修正 → "$kata" → "$row->[14 + $i * 3]"
# 2. ▼マーカー（画像・xhtml・spine）への挿入ロジックを修正

sub update_opf_template {
    my ($row, $opf_path, $image_items_ref, $xhtml_items_ref, $spine_items_ref) = @_;
    open my $in, '<:utf8', $opf_path or die "Can't open template OPF: $opf_path\n";
    my @lines = <$in>;
    close $in;

    my $ug = Data::UUID->new;
    my $uuid = $ug->create_str();
    my $modified = strftime("%Y-%m-%dT%H:%M:%SZ", gmtime);

    my @creator_blocks;
    for my $i (0 .. 5) {
        my $name = $row->[12 + $i * 3] // '';
        my $kana = $row->[13 + $i * 3] // '';
        my $kata = $row->[14 + $i * 3] // '';  # 修正された著者カタカナの取得位置
        next unless $name;
        my $idnum = sprintf("%02d", scalar @creator_blocks + 1);
        my $id = "creator$idnum";
        push @creator_blocks, join("\n", (
            qq|<dc:creator id=\"$id\">$name</dc:creator>|,
            qq|<meta scheme=\"marc:relators\" refines=\"#$id\" property=\"role\">aut</meta>|,
            qq|<meta refines=\"#$id\" property=\"file-as\">$kata</meta>|,
            qq|<meta refines=\"#$id\" property=\"display-seq\">$idnum</meta>|
        ));
    }

    for (@lines) {
        s/\x{25CF}タイトル名\x{25CF}/$row->[2]/g;
        s/\x{25CF}タイトル名カタカナ\x{25CF}/$row->[7]/g;
        s/\x{25CF}出版社名\x{25CF}/$row->[9]/g;
        s/\x{25CF}出版社名カタカナ\x{25CF}/$row->[11]/g;
        s/\x{25CF}UUID\x{25CF}/$uuid/g;
        s/\x{25CF}更新日\x{25CF}/$modified/g;
        s/\x{25CF}著者名\x{25CF}/join("\n", @creator_blocks)/e;
        s/\x{25B2}画像ファイルタグ印字位置\x{25B2}/join("", @$image_items_ref)/e;
        s/\x{25B2}xhtmlファイルタグ印字位置\x{25B2}/join("", @$xhtml_items_ref)/e;
        s/\x{25B2}spineタグ印字位置\x{25B2}/join("", @$spine_items_ref)/e;
    }

    open my $out, '>:utf8', $opf_path or die "Can't write updated OPF: $opf_path\n";
    print $out @lines;
    close $out;
}

sub extract_opf_tags {
    my ($opf_file) = @_;
    my (@image, @xhtml, @spine);

    open my $in, '<:utf8', $opf_file or die "Can't open OPF: $opf_file\n";
    while (my $line = <$in>) {
        push @image, $line if $line =~ /<item[^>]+href="image-[^"]+\.jpg"/;
        push @xhtml, $line if $line =~ /<item[^>]+href="p-[^"]+\.xhtml"/;
        push @spine, $line if $line =~ /<itemref[^>]+/;
    }
    close $in;

    return (\@image, \@xhtml, \@spine);
}

