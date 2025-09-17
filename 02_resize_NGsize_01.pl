use strict;
use warnings;
use utf8;
use open ':std', ':encoding(UTF-8)';
use File::Spec;
use Image::Magick;
use Encode;

my $base_dir = '02_assemble';
my $log_file = 'check_image_log.txt';

# 読み取り
open my $log_fh, '<:encoding(UTF-8)', $log_file or die "ログファイルが開けません: $log_file\n";
my %targets;

while (<$log_fh>) {
    next unless /^\[([^\]]+)\]\s+(\S+)\s*:\s*(\d+)x(\d+)/;
    my ($prefix, $img_file, $w, $h) = ($1, $2, $3, $4);
    push @{ $targets{$prefix} }, $img_file;
}
close $log_fh;

foreach my $prefix (sort keys %targets) {
    my $image_dir = File::Spec->catdir($base_dir, $prefix, 'item', 'image');
    my $xhtml_dir = File::Spec->catdir($base_dir, $prefix, 'item', 'xhtml');

    foreach my $img_file (@{ $targets{$prefix} }) {
        my $img_path = File::Spec->catfile($image_dir, $img_file);

        # === ImageMagickでリサイズ ===
        my $image = Image::Magick->new;
        my $x = $image->Read($img_path);
        warn "読み込み失敗: $img_path" if $x;
        $image->Resize(geometry => '1600x2560!');
        $image->Write($img_path);
        undef $image;

        print "✔ リサイズ完了: $prefix/$img_file\n";

        # === XHTML 修正 ===
        opendir(my $dh, $xhtml_dir) or next;
        my @xhtmls = grep { /^p-.*cover\.xhtml$/ } readdir($dh);
        closedir($dh);

        foreach my $xhtml_file (@xhtmls) {
            my $xhtml_path = File::Spec->catfile($xhtml_dir, $xhtml_file);
            open my $in, '<:encoding(UTF-8)', $xhtml_path or next;
            my @lines = <$in>;
            close $in;

            my $changed = 0;
            for (@lines) {
                $changed += s/(<meta[^>]+viewport[^>]+content=["'])width=\d+,\s*height=\d+(["'])/${1}width=1600, height=2560$2/;
                $changed += s/(viewBox\s*=\s*["'])0 0 \d+ \d+(["'])/${1}0 0 1600 2560$2/;
                $changed += s/(<image[^>]+width=["']?)\d+(["'])/${1}1600$2/;
                $changed += s/(<image[^>]+height=["']?)\d+(["'])/${1}2560$2/;
            }

            if ($changed) {
                open my $out, '>:encoding(UTF-8)', $xhtml_path or next;
                print $out @lines;
                close $out;
                print "✔ XHTML修正完了: $prefix/$xhtml_file\n";
            }
        }
    }
}
