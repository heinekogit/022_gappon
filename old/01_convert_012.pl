use strict;
use warnings;
use utf8;
use open ':std', ':encoding(UTF-8)';
use Text::CSV;
use File::Copy;
use File::Path qw(make_path);
use File::Spec;

my $csv_file = 'shosi.csv';
my $base_dir = '02_assemble';

my $csv = Text::CSV->new({ binary => 1, auto_diag => 1 });
open my $fh, "<:encoding(utf8)", $csv_file or die "Can't open CSV: $!";

while (my $row = $csv->getline($fh)) {
    next unless @$row >= 6;
    my $prefix = $row->[6];
    next unless $prefix;

    my $folder_path = File::Spec->catdir($base_dir, $prefix);
    unless (-d $folder_path) {
        warn "[警告] フォルダが見つかりません: $folder_path\n";
        next;
    }

    my $image_dir = File::Spec->catdir($folder_path, 'item', 'image');
#      print "image_dir: $image_dir\n";

    my $xhtml_dir = File::Spec->catdir($folder_path, 'item', 'xhtml');



    # --------------------------
    # image ファイルのリネーム
    # --------------------------
    if (-d $image_dir) {
    opendir(my $dh, $image_dir) or die "Can't open $image_dir: $!";
    my @files = readdir($dh);
    closedir($dh);

#    print "=== ファイル一覧 ($image_dir) ===\n";
#    foreach my $file (@files) {
#        print "見つかったファイル: [$file]\n";
    }

    foreach my $file (@files) {
        next unless $file =~ /^(image)-(\d{4})\.jpg$/;
        my $from = File::Spec->catfile($image_dir, $file);
        my $to   = File::Spec->catfile($image_dir, "$1-$prefix$2.jpg");

#        print "Renaming $from → $to\n";
        rename($from, $to) or warn "[失敗] rename: $from → $to\n";
    }
} else {
    warn "[警告] image ディレクトリが存在しません: $image_dir\n";
}

    # --------------------------
    # xhtml ファイルのリネーム＆内容変換
    # --------------------------
    if (-d $xhtml_dir) {
        opendir(my $dh, $xhtml_dir) or die "Can't open $xhtml_dir: $!";
        foreach my $file (readdir($dh)) {
            next unless $file =~ /^(p)-(\d{4})\.xhtml$/;
            my $from = File::Spec->catfile($xhtml_dir, $file);
            my $to   = File::Spec->catfile($xhtml_dir, "$1-$prefix$2.xhtml");

            open my $in,  "<:utf8", $from or die "Can't open $from: $!";
            my @lines = <$in>;
            close $in;

            # <img src="image-0001.jpg"> → image-k0001.jpg に変換
            for (@lines) {
                s/(image-)(\d{4})(\.jpg)/$1 . $prefix . $2 . $3/e;
            }

            open my $out, ">:utf8", $to or die "Can't write $to: $!";
            print $out @lines;
            close $out;

            unlink $from or warn "[警告] 元のXHTML削除失敗: $from\n";
        }
        closedir($dh);
    } else {
        warn "[警告] xhtml ディレクトリが存在しません: $xhtml_dir\n";
    }

close $fh;
