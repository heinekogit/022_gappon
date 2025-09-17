use strict;
use warnings;
use utf8;
use open ':std', ':encoding(UTF-8)';
use Text::CSV;
use File::Basename;
use File::Spec;

# ImageMagick のパス（必要に応じて調整）
my $magick_path = '"C:\\Program Files\\ImageMagick-7.1.2-Q16\\magick.exe"';
(my $check_path = $magick_path) =~ s/^"(.*)"$/$1/;
die "[ERROR] ImageMagick exe file not found: $check_path\n" unless -e $check_path;

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
            if ($line =~ /<meta\s+name=["']viewport["']\s+content=["']width=(\d+),\s*height=(\d+)["']/) {
                my ($vw, $vh) = ($1, $2);
                if ($vw != $target_width || $vh != $target_height) {
                    $line =~ s/width=\d+/width=$target_width/;
                    $line =~ s/height=\d+/height=$target_height/;
                    $changed = 1;
                    print "[info] viewport modified: $xhtml_path\n";
                }
            }

            if ($line =~ /<image[^>]+xlink:href=["']([^"']+)["']/) {
                my $rel_path = $1;
                $image_path = File::Spec->catfile($base_dir, $prefix, 'item', 'image', basename($rel_path));
                print "[DEBUG] image path: $image_path\n";
            }

            push @new_lines, $line;
        }

        if ($changed) {
            open my $out, '>:encoding(UTF-8)', $xhtml_path or warn "[warn] fail write input: $xhtml_path\n";
            print $out @new_lines;
            close $out;
        }

        if (defined $image_path && -e $image_path) {
            my $identify_cmd = qq{$magick_path identify -format "%w %h" "$image_path"};
            my $size_str = `$identify_cmd`;
            my ($w, $h) = split(/\s+/, $size_str);

            if (defined $w && defined $h && ($w != $target_width || $h != $target_height)) {
                print "[info] リサイズ: $image_path ($w x $h → $target_width x $target_height)\n";
                my $resize_cmd = qq{$magick_path "$image_path" -resize ${target_width}x${target_height}! "$image_path"};
                system($resize_cmd) == 0 or warn "[warn] fail to resize: $image_path\n";
            }
        } elsif (defined $image_path) {
            warn "[ERROR] image file not found: $image_path\n";
        }
    }
    closedir($dh);
}
