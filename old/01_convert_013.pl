use strict;
use warnings;
use utf8;
use open ':std', ':encoding(UTF-8)';
use Text::CSV;
use File::Copy;
use File::Path qw(make_path);
use File::Spec;
use File::Copy::Recursive qw(dircopy);

my $csv_file  = 'shosi.csv';
my $base_dir  = '02_assemble';
my $template_dir = '00_templates';
my $combined_root = '03_combined';

# CSV読み込み
my $csv = Text::CSV->new({ binary => 1, auto_diag => 1 });
open my $fh, "<:encoding(utf8)", $csv_file or die "Can't open CSV: $!";

while (my $row = $csv->getline($fh)) {
    next unless @$row >= 7;  # 最低7列必要

    my $combined_name = $row->[4];  # 5列目：合本フォルダ名
    my $prefix        = $row->[3];  # 3列目：素材フォルダ名／接頭語
    next unless $combined_name && $prefix;

    my $folder_path = File::Spec->catdir($base_dir, $prefix);
    unless (-d $folder_path) {
        warn "[警告] フォルダが見つかりません: $folder_path\n";
        next;
    }

    my $image_dir  = File::Spec->catdir($folder_path, 'item', 'image');
    my $xhtml_dir  = File::Spec->catdir($folder_path, 'item', 'xhtml');
    my $opf_path   = File::Spec->catfile($folder_path, 'item', 'content.opf');
    my $combined_dir = File::Spec->catdir($combined_root, $combined_name);

    # --------------------------
    # image ファイルのリネーム
    # --------------------------
    if (-d $image_dir) {
        opendir(my $dh, $image_dir) or die "Can't open $image_dir: $!";
        my @files = readdir($dh);
        closedir($dh);

        foreach my $file (@files) {
            next unless $file =~ /^(image)-(\d{4})\.jpg$/;
            my $from = File::Spec->catfile($image_dir, $file);
            my $to   = File::Spec->catfile($image_dir, "$1-$prefix$2.jpg");
            rename($from, $to) or warn "[失敗] rename: $from → $to\n";
        }
    } else {
        warn "[警告] image ディレクトリが存在しません: $image_dir\n";
    }

    # --------------------------
    # xhtml ファイルのリネーム＆内容修正
    # --------------------------
    if (-d $xhtml_dir) {
        opendir(my $dh, $xhtml_dir) or die "Can't open $xhtml_dir: $!";
        my @files = readdir($dh);
        closedir($dh);

        foreach my $file (@files) {
            next unless $file =~ /^(p)-(\d{4})\.xhtml$/;
            my $from = File::Spec->catfile($xhtml_dir, $file);
            my $to   = File::Spec->catfile($xhtml_dir, "$1-$prefix$2.xhtml");

            open my $in,  "<:utf8", $from or die "Can't open $from: $!";
            my @lines = <$in>;
            close $in;

            # 画像参照を置換
            for (@lines) {
                s/(image-)(\d{4})(\.jpg)/$1 . $prefix . $2 . $3/e;
            }

            open my $out, ">:utf8", $to or die "Can't write $to: $!";
            print $out @lines;
            close $out;

            unlink $from or warn "[警告] 元のXHTML削除失敗: $from\n";
        }
    } else {
        warn "[警告] xhtml ディレクトリが存在しません: $xhtml_dir\n";
    }

    # --------------------------
    # 合本フォルダの作成とテンプレートコピー
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

    # ★将来的な統合処理（OPF統合、XHTML結合、コピーなど）ここに追記可
}

close $fh;
