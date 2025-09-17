use strict;
use warnings;
use Encode;
use Text::CSV;
use File::Copy;

my $csv_file = 'shosi.csv';
my $base_dir = '02_assemble';

my $csv = Text::CSV->new({ binary => 1 });
open my $fh, "<:encoding(utf8)", $csv_file or die "Can't open CSV: $!";

while (my $row = $csv->getline($fh)) {
    my $prefix = $row->[5];  # 6列目：フォルダ名かつprefix
    next unless $prefix;

    my $folder_path = "$base_dir/$prefix";
    unless (-d $folder_path) {
        warn "フォルダが見つかりません: $folder_path\n";
        next;
    }

    opendir(my $dh, $folder_path) or die "Can't open dir: $!";
    my @files = readdir($dh);
    closedir($dh);

    foreach my $file (@files) {
        next if $file =~ /^\./;

#        my $full_path = "$folder_path/$file";
        my $full_path = "$folder_path\/item\/image\/$file";

        # image-0001.jpg → image-k0001.jpg
        if ($file =~ /^(image)-(\d{4})\.jpg$/) {
            my $new_name = "$1-$prefix$2.jpg";
            rename($full_path, "$folder_path/$new_name") or warn "rename failed: $!";
        }

        # p-0003.xhtml → p-k0003.xhtml（中身の画像名も変換）
        elsif ($file =~ /^(p)-(\d{4})\.xhtml$/) {
            my $new_name = "$1-$prefix$2.xhtml";
            my $new_path = "$folder_path/$new_name";

            open my $in,  "<:utf8", $full_path or die "Can't open $full_path: $!";
            my @lines = <$in>;
            close $in;

            # <img src="image-0001.jpg" /> → image-k0001.jpg に置換
            for (@lines) {
                s/(image-)(\d{4})(\.jpg)/$1.$prefix.$2.$3/e;
            }

            open my $out, ">:utf8", $new_path or die "Can't write $new_path: $!";
            print $out @lines;
            close $out;

            unlink $full_path or warn "Can't remove $full_path: $!";
        }
    }
}
close $fh;
