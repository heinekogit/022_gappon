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
    my $im_width  = $row->[30] // 1600;
    my $im_height = $row->[31] // 2560;
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
                # 既存の本文ページ
                if ($file =~ /^(p)-(\d{4})\.xhtml$/) {
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
                # p-cover.xhtmlも同様に処理（大文字小文字無視・不可視文字除去）
                elsif (lc($file) =~ /^p-?cover\.xhtml$/) {
                    print "[info] material p-cover.xhtml in use: $file\n";
                    my $from = File::Spec->catfile($xhtml_dir, $file);
                    my $to_name = "p-${prefix}cover.xhtml";
                    my $to = File::Spec->catfile($out_xhtml_dir, $to_name);
                    open my $in,  "<:utf8", $from or die "Can't open $from: $!";
                    my @lines = <$in>;
                    close $in;
                    for (@lines) {
                        s/(image-)cover(\.jpg)/$1${prefix}cover$2/g;
                    }
                    open my $out, ">:utf8", $to or die "Can't write $to: $!";
                    print $out @lines;
                    close $out;
                }
            }
            closedir($dh);
        }

        my ($img_ref, $xhtml_ref, $spine_ref) = extract_opf_tags($source_opf, $prefix);

        my $id_cover_template = File::Spec->catfile($template_dir, 'p-id_0000.xhtml');
        my $cover_image_name  = "image-${prefix}cover.jpg";
        my $cover_image_src   = File::Spec->catfile($image_dir, 'cover.jpg');
        my $cover_image_dest  = File::Spec->catfile($out_image_dir, $cover_image_name);
        my $cover_xhtml_name  = "p-${prefix}cover.xhtml";
        my $cover_xhtml_path  = File::Spec->catfile($out_xhtml_dir, $cover_xhtml_name);

        if (-e $cover_image_src && -e $id_cover_template) {
            copy($cover_image_src, $cover_image_dest) or warn "[失敗] cover.jpg コピー: $cover_image_src → $cover_image_dest\n";

            open my $in,  '<:utf8', $id_cover_template or die "Can't open $id_cover_template: $!\n";
            my @id_lines = <$in>;
            close $in;
            for (@id_lines) {
                s/●タイトル名●/$title/g;
                s/●横サイズ●/$im_width/g;
                s/●縦サイズ●/$im_height/g;
                s/image-●ID●cover\.jpg/$cover_image_name/g;
            }
            open my $out, '>:utf8', $cover_xhtml_path or die "Can't write $cover_xhtml_path: $!\n";
            print $out @id_lines;
            close $out;

            unshift @$img_ref, qq|<item id="image-${prefix}cover" href="image/$cover_image_name" media-type="image/jpeg"/>\n|;
            unshift @$xhtml_ref, qq|<item id="p-${prefix}cover" href="xhtml/$cover_xhtml_name" media-type="application/xhtml+xml" properties="svg"/>\n|;
            unshift @$spine_ref, qq|<itemref linear="yes" idref="p-${prefix}cover" properties="page-spread-left"/>\n|;
        } else {
            warn "[alert] cover or template missing: $cover_image_src / $id_cover_template\n";
        }

        # ↓ この下に白ページの末尾挿入処理を追加します（次パートで提示）

        # === 白ページ挿入処理（末尾が右ページだった場合） ===
        if (@$spine_ref && $spine_ref->[-1] =~ /page-spread-right/) {
            # image-white.jpg → image-${prefix}9999.jpg にリネームしてコピー
            my $white_img_src = File::Spec->catfile($template_dir, 'image-white.jpg');
            my $white_img_dst = File::Spec->catfile($out_image_dir, "image-${prefix}9999.jpg");
            if (-e $white_img_src) {
                copy($white_img_src, $white_img_dst)
                    or warn "[白画像コピー失敗] $white_img_src → $white_img_dst\n";
            } else {
                warn "[白画像見つからず] $white_img_src\n";
            }

            my $white_xhtml_template = File::Spec->catfile($template_dir, 'p-white_0000.xhtml');
            my $white_xhtml_name = "p-${prefix}9999.xhtml";
            my $white_xhtml_path = File::Spec->catfile($out_xhtml_dir, $white_xhtml_name);

            if (-e $white_xhtml_template) {
                open my $in,  '<:utf8', $white_xhtml_template or die "Can't open $white_xhtml_template: $!";
                my @white_lines = <$in>;
                close $in;
                for (@white_lines) {
                    s/●タイトル名●/$title/g;
                    s/●横サイズ●/$im_width/g;
                    s/●縦サイズ●/$im_height/g;
                    s/image-white\.jpg/image-${prefix}9999.jpg/g;      #画像は固定名で参照
                }
                open my $out, '>:utf8', $white_xhtml_path or die "Can't write $white_xhtml_path: $!";
                print $out @white_lines;
                close $out;
            } else {
                warn "[白ページテンプレート見つからず] $white_xhtml_template\n";
            }

            push @$img_ref, qq|<item id="image-${prefix}9999" href="image/image-${prefix}9999.jpg" media-type="image/jpeg"/>\n|;
            push @$xhtml_ref, qq|<item id="p-${prefix}9999" href="xhtml/p-${prefix}9999.xhtml" media-type="application/xhtml+xml" properties="svg"/>\n|;
            push @$spine_ref, qq|<itemref linear="yes" idref="p-${prefix}9999" properties="page-spread-left"/>\n|;
        }

        # image-white.jpg のOPFタグ追加（ここだけでOK）
        # push @$img_ref, qq|<item id="image-white" href="image/image-white.jpg" media-type="image/jpeg"/>\n|;

        # === 結果を合本データに格納 ===
        push @{ $combined_data{$combined_name}{image} }, @$img_ref;
        push @{ $combined_data{$combined_name}{xhtml} }, @$xhtml_ref;
        push @{ $combined_data{$combined_name}{spine} }, @$spine_ref;
        print "[debug] $combined_name material plus: img=", scalar(@$img_ref), ", xhtml=", scalar(@$xhtml_ref), ", spine=", scalar(@$spine_ref), "\n";
    }


    elsif ($type eq '合本') {
        print "[debug] gappon operation start: $combined_name\n";
        my $combined_dir = File::Spec->catdir($combined_root, $combined_name);
        my $output_opf   = File::Spec->catfile($combined_dir, 'item', 'standard.opf');

        unless (-d $combined_dir) {
            make_path($combined_dir) or die "[warn] target folder make error: $combined_dir\n";
            print "target folder made: $combined_dir\n";
        }

        my $full_copy_dir = File::Spec->catdir($template_dir, 'full_copy');
        my $result = dircopy($full_copy_dir, $combined_dir);
        if ($result) {
            print "template copy: $full_copy_dir to $combined_dir\n";
        } else {
            warn "[warn] template copy error: $full_copy_dir to $combined_dir\n";
        }

        my ($img_ref, $xhtml_ref, $spine_ref) = (
            $combined_data{$combined_name}{image} || [],
            $combined_data{$combined_name}{xhtml} || [],
            $combined_data{$combined_name}{spine} || []
        );

        print "[debug] OPF update: $output_opf\n";
        update_opf_template($row, $output_opf, $img_ref, $xhtml_ref, $spine_ref);
        print "[debug] OPF update complete\n";

        my $new_title = $row->[2];
        my $nav_file = File::Spec->catfile($combined_dir, 'item', 'navigation-documents.xhtml');
        if (-e $nav_file) {
            _replace_title_in_file($nav_file, $new_title);
        } else {
            warn "[alart] navigation-documents.xhtml no exist: $nav_file\n";
        }

        my $xhtml_dir = File::Spec->catdir($combined_dir, 'item', 'xhtml');
        if (-d $xhtml_dir) {
            opendir(my $dx, $xhtml_dir) or die "Can't open xhtml dir: $xhtml_dir\n";
            while (my $xf = readdir($dx)) {
                next unless $xf =~ /\.xhtml$/;
                my $xhtml_file = File::Spec->catfile($xhtml_dir, $xf);
                _replace_title_in_file($xhtml_file, $new_title);
            }
            closedir($dx);
        }

        for my $fname (qw(p-cover.xhtml p-colophon.xhtml p-endcard.xhtml)) {
            my $file = File::Spec->catfile($combined_dir, 'item', 'xhtml', $fname);
            if (-e $file) {
                _replace_title_in_file($file, $new_title);
            } else {
                warn "[alert] $fname not found: $file\n";
            }
        }

        # 先頭カバー生成
        my $cover_template = File::Spec->catfile($template_dir, 'p-id_0000.xhtml');
        my $cover_image_name = "image-cover.jpg";
        my $cover_image_src  = File::Spec->catfile($template_dir, 'cover.jpg');
        my $cover_image_dest = File::Spec->catfile($combined_dir, 'item', 'image', $cover_image_name);
        my $cover_xhtml_name = "p-cover.xhtml";
        my $cover_xhtml_path = File::Spec->catfile($combined_dir, 'item', 'xhtml', $cover_xhtml_name);

        if (-e $cover_image_src && -e $cover_template) {
            print "[debug] gappon cover create: $cover_image_src, $cover_template\n";
            copy($cover_image_src, $cover_image_dest) or warn "[失敗] cover.jpg コピー: $cover_image_src → $cover_image_dest\n";
            open my $in,  '<:utf8', $cover_template or die "Can't open $cover_template: $!\n";
            my @id_lines = <$in>;
            close $in;
            my $title = $row->[2];
            my $im_width  = $row->[30] // 1600;
            my $im_height = $row->[31] // 2560;
            for (@id_lines) {
                s/●タイトル名●/$title/g;
                s/●横サイズ●/$im_width/g;
                s/●縦サイズ●/$im_height/g;
                s/image-●ID●cover\.jpg/$cover_image_name/g;
            }
            open my $out, '>:utf8', $cover_xhtml_path or die "Can't write $cover_xhtml_path: $!\n";
            print $out @id_lines;
            close $out;
            print "[debug] gappon cover create success: $cover_xhtml_path\n";
        } else {
            warn "[alert] gappon cover create failure: $cover_image_src / $cover_template\n";
        }

        # 合本カバーのOPFタグを先頭に追加
        unshift @$img_ref, qq|<item id="image-cover" href="image/image-cover.jpg" media-type="image/jpeg"/>\n|;
        unshift @$xhtml_ref, qq|<item id="p-cover" href="xhtml/p-cover.xhtml" media-type="application/xhtml+xml" properties="svg"/>\n|;
        unshift @$spine_ref, qq|<itemref linear="yes" idref="p-cover" properties="page-spread-left"/>\n|;
    }

}

sub update_opf_template {
    my ($row, $opf_path, $image_items_ref, $xhtml_items_ref, $spine_items_ref) = @_;
    print "[debug] update_opf_template calling: $opf_path\n";
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
        my $kata = $row->[14 + $i * 3] // '';
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

    my $creators_combined = join("\n", @creator_blocks);
    my $image_tags  = join("", @$image_items_ref);
    my $xhtml_tags  = join("", @$xhtml_items_ref);
    my $spine_tags  = join("", @$spine_items_ref);

    for (@lines) {
        s/\x{25CF}タイトル名\x{25CF}/$row->[2]/g;
        s/\x{25CF}タイトル名カタカナ\x{25CF}/$row->[7]/g;
        s/\x{25CF}出版社名\x{25CF}/$row->[9]/g;
        s/\x{25CF}出版社名カタカナ\x{25CF}/$row->[11]/g;
        s/\x{25CF}UUID\x{25CF}/$uuid/g;
        s/\x{25CF}更新日\x{25CF}/$modified/g;
        s/▼著者タグ印字位置▼/$creators_combined/g;
        s/▼画像ファイルタグ印字位置▼/$image_tags/g;
        s/▼xhtmlファイルタグ印字位置▼/$xhtml_tags/g;
        s/▼spineタグ印字位置▼/$spine_tags/g;
    }

    open my $out, '>:utf8', $opf_path or die "Can't write updated OPF: $opf_path\n";
    print $out @lines;
    close $out;
}


sub extract_opf_tags {
    my ($opf_file, $prefix) = @_;
    my (@image, @xhtml, @spine);

    open my $in, '<:utf8', $opf_file or die "Can't open OPF: $opf_file\n";
    while (my $line = <$in>) {
        if ($line =~ m{<item[^>]+href="(?:[^"]*/)?image-(\d{4})\.jpg"}i) {
            my $num = $1;
            my $id  = "image-$prefix$num";
            my $href = "image/image-$prefix$num.jpg";
            push @image, qq|<item id=\"$id\" href=\"$href\" media-type=\"image/jpeg\"/>\n|;
        }
        elsif ($line =~ m{<item[^>]+href="(?:[^"]*/)?p-(\d{4})\.xhtml"}i) {
            my $num = $1;
            my $id  = "p-$prefix$num";
            my $href = "xhtml/p-$prefix$num.xhtml";
            push @xhtml, qq|<item id=\"$id\" href=\"$href\" media-type=\"application/xhtml+xml\" properties="svg"/>\n|;
        }
        elsif ($line =~ m{<itemref[^>]+idref="p-(\d{4})"}i) {
            my $num = $1;
            my $idref = "p-$prefix$num";
            my $spread = ($num % 2 == 1) ? 'page-spread-right' : 'page-spread-left';
            push @spine, qq|<itemref linear=\"yes\" idref=\"$idref\" properties=\"$spread\"/>\n|;
        }
    }
    close $in;

    return (\@image, \@xhtml, \@spine);
}


sub _replace_title_in_file {
    my ($file, $new_title) = @_;
    open my $in,  '<:utf8', $file or die "Can't open $file: $!\n";
    my @lines = <$in>;
    close $in;
    for (@lines) {
        s{<title>.*?</title>}{<title>$new_title</title>}g;
    }
    open my $out, '>:utf8', $file or die "Can't write $file: $!\n";
    print $out @lines;
    close $out;
}


