use strict;
use warnings;
use utf8;
use open ':std', ':encoding(UTF-8)';
use Text::CSV;
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Spec;
use File::Copy::Recursive qw(dircopy);

binmode STDOUT, ':encoding(UTF-8)';

my $csv_file      = 'shosi.csv';
my $base_dir      = '02_assemble';
my $template_dir  = '00_templates';
my $combined_root = '03_combined';

my $csv = Text::CSV->new({ binary => 1, auto_diag => 1 });
open my $fh, "<:encoding(utf8)", $csv_file or die "Can't open CSV: $!";
my $first_line = <$fh>;
$first_line =~ s/^\x{FEFF}//;  # BOM除去
seek($fh, 0, 0);  # ファイルポインタを先頭に戻す

print "CSV opend operation start\n";

while (my $row = $csv->getline($fh)) {
#    print "CSV reading: " . join(" / ", @$row) . "\n";

    next unless @$row >= 7;

    my $combined_name = $row->[4];  # 5列目：合本フォルダ名
    my $prefix        = $row->[3];  # 4列目：素材prefix
    next unless $combined_name && $prefix;

    print "読み込み行: prefix=[$prefix], 合本名=[$combined_name]\n";

    my $folder_path   = File::Spec->catdir($base_dir, $prefix);
    my $image_dir     = File::Spec->catdir($folder_path, 'item', 'image');
    my $xhtml_dir     = File::Spec->catdir($folder_path, 'item', 'xhtml');

    my $combined_dir  = File::Spec->catdir($combined_root, $combined_name);
    my $out_image_dir = File::Spec->catdir($combined_dir, 'item', 'image');
    my $out_xhtml_dir = File::Spec->catdir($combined_dir, 'item', 'xhtml');

    # --------------------------
    # 合本フォルダの作成＋テンプレートコピー（先にやる）
    # --------------------------
    unless (-d $template_dir) {
        die "[エラー] テンプレートフォルダが見つかりません: $template_dir\n";
    }

    unless (-d $combined_dir) {
        make_path($combined_dir) or die "[エラー] 合本フォルダ作成失敗: $combined_dir\n";
        print "合本フォルダを作成: $combined_dir\n";
    }

    my $result = dircopy($template_dir, $combined_dir);
    if ($result) {
        print "テンプレートをコピー: $template_dir → $combined_dir\n";
    } else {
        warn "[警告] テンプレートのコピーに失敗: $template_dir → $combined_dir\n";
    }

    # --------------------------
    # image のコピー＆リネーム
    # --------------------------
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
    } else {
        warn "[警告] image ディレクトリが存在しません: $image_dir\n";
    }

    # --------------------------
    # xhtml のコピー＆リネーム＋中の画像リンクも変換
    # --------------------------
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
    } else {
        warn "[警告] xhtml ディレクトリが存在しません: $xhtml_dir\n";
    }
}

close $fh;
