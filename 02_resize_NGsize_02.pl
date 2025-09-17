use strict;
use warnings;
use utf8;
use open ':std', ':encoding(UTF-8)';
use File::Find;
use File::Basename;
use File::Spec;

# ImageMagick のパスを明示
my $magick_path = '"C:\\Program Files\\ImageMagick-7.1.2-Q16\\magick.exe"';

# パスからダブルクォートを除去してファイルの存在チェック
(my $check_path = $magick_path) =~ s/^"(.*)"$/$1/;

unless (-e $check_path) {
    die "[ERROR] ImageMagick exe file not found: $check_path\n";
}

# 基準サイズ
my ($target_width, $target_height) = (1600, 2560);

# ベースディレクトリ
my $base_dir = '02_assemble';

# XHTML ファイルを格納しているサブフォルダの相対パス（画像もこの中にある前提）
find(\&process_file, $base_dir);

sub process_file {
    return unless /\.xhtml$/i;
    my $xhtml_path = $File::Find::name;

    # XHTML内容を読み込む
    open my $in, '<:encoding(UTF-8)', $xhtml_path or do {
        warn "[warn] cant open file: $xhtml_path\n";
        return;
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
            $image_path = File::Spec->catfile(dirname($xhtml_path), $1);
        }

        push @new_lines, $line;
    }

    # XHTMLのviewportを書き換え
    if ($changed) {
        open my $out, '>:encoding(UTF-8)', $xhtml_path or die "fail write input: $xhtml_path\n";
        print $out @new_lines;
        close $out;
    }

# 画像のリサイズ（元画像が存在し、サイズが異なる場合のみ）
if (defined $image_path && -e $image_path) {
    # `magick identify` を使って画像サイズを取得
    my $identify_cmd = qq{$magick_path identify -format "%w %h" "$image_path"};
    my $size_str = `$identify_cmd`;
    my ($w, $h) = split(/\s+/, $size_str);

    if (defined $w && defined $h && ($w != $target_width || $h != $target_height)) {
        print "[info] リサイズ: $image_path ($w x $h → $target_width x $target_height)\n";
        my $resize_cmd = qq{$magick_path "$image_path" -resize ${target_width}x${target_height}! "$image_path"};
        print "[DEBUG] exec: $resize_cmd\n";  # ← デバッグ出力追加
        system($resize_cmd) == 0 or warn "[warn] fail write input: $image_path\n";
    }
}

}
