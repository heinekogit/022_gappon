use strict;
use warnings;
use utf8;
use open ':std', ':encoding(UTF-8)';
use Text::CSV;
use File::Basename;
use File::Spec;
use Cwd 'abs_path';

# ImageMagick のパスを明示（必要に応じて調整）
my $magick_path = '"C:\\Program Files\\ImageMagick-7.1.2-Q16\\magick.exe"';
(my $check_path = $magick_path) =~ s/^"(.*)"$/$1/;
unless (-e $check_path) {
    die "[ERROR] ImageMagick exe file not found: $check_path\n";
}

my ($target_width, $target_height) = (1600, 2560);
my $csv_file = '02_assemble/shosi.csv';
my $base_dir = '02_assemble';

my $csv = Text::CSV->new({ binary => 1, auto_diag => 1 });
open my $fh, "<:encoding(UTF-8)", $csv_file or die "CSV cant open: $csv_file\n";

# BOM除去
my $first_line = <$fh>;
$first_line =~ s/^\x{FEFF}//;
seek($fh, 0, 0);

while (my $row = $csv->getline($fh)) {
    next unless @$row >= 6;
    my ($g_id, $title, $prefix, $combined_name, $type) = @$row[1..5];
    next unless $type eq '素材';

    my $xhtml_dir = File::Spec->catdir($base_dir, $prefix, 'item', 'xhtml');
    next unless -d $xhtml_dir;

    opendir(my $dh, $xhtml_dir) or next;
    while (my $file = readdir($dh)) {
        next unless $file =~ /\.xhtml$/i;
        my $xhtml_path = File::Spec->catfile($xhtml_dir, $file);

        open my $in, '<:encoding(UTF-8)', $xhtml_path or do {
            warn "[warn] cant open file: $xhtml_path\n";
            next;
        };
        my @lines = <$in>;
        close $in;

        my $changed = 0;
        my $image_path;
        my @new_lines;

        foreach my $line (@lines) {
            # viewport修正
            if ($line =~ /<meta\s+name=["']viewport["']\s+content=["']width=(\d+),\s*height=(\d+)["']/) {
                my ($vw, $vh) = ($1, $2);
                if ($vw != $target_width || $vh != $target_height) {
                    $line =~ s/width=\d+/width=$target_width/;
                    $line =~ s/height=\d+/height=$target_height/;
                    $changed = 1;
                    print "[info] viewport modified: $xhtml_path\n";
                }
            }

            # svgタグのviewBoxやサイズ修正
            if ($line =~ /<svg[^>]*viewBox=["']0 0 \d+ \d+["'][^>]*>/) {
                $line =~ s/viewBox=["']0 0 \d+ \d+["']/viewBox="0 0 $target_width $target_height"/;
                $line =~ s/width=["']\d+["']/width="$target_width"/;
                $line =~ s/height=["']\d+["']/height="$target_height"/;
                $changed = 1;
                print "[info] svg tag modified: $xhtml_path\n";
            }

            # imageタグのサイズ修正 & 画像パス取得
            if ($line =~ /<image[^>]+xlink:href=["']([^"']+)["'][^>]*>/) {
                my $img_rel = $1;
#                $image_path = File::Spec->catfile($base_dir, $prefix, 'item', $img_rel);
                my $xhtml_dir = File::Spec->catdir($base_dir, $prefix, 'item', 'xhtml');
                $image_path = File::Spec->rel2abs($img_rel, $xhtml_dir);

                $line =~ s/width=["']\d+["']/width="$target_width"/;
                $line =~ s/height=["']\d+["']/height="$target_height"/;
                $changed = 1;
                print "[info] image tag modified: $xhtml_path\n";
            }

            push @new_lines, $line;
        }

        # 書き換え
        if ($changed) {
            open my $out, '>:encoding(UTF-8)', $xhtml_path or warn "[warn] fail write input: $xhtml_path\n";
            print $out @new_lines;
            close $out;
        }

        # 画像リサイズ処理
        if (defined $image_path && -e $image_path) {
            my $identify_cmd = qq{$magick_path identify -format "%w %h" "$image_path"};
            my $size_str = `$identify_cmd`;
            my ($w, $h) = split(/\s+/, $size_str);

            if (defined $w && defined $h && ($w != $target_width || $h != $target_height)) {
                print "[info] resize: $image_path ($w x $h → $target_width x $target_height)\n";
                my $resize_cmd = qq{$magick_path "$image_path" -resize ${target_width}x${target_height}! "$image_path"};
                system($resize_cmd) == 0 or warn "[warn] fail to resize: $image_path\n";
            }
        } elsif (defined $image_path) {
            warn "[ERROR] image file not found: $image_path\n";
        }
    }
    closedir($dh);
}
