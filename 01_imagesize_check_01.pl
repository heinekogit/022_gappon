use strict;
use warnings;
use utf8;
use open ':std', ':encoding(UTF-8)';
use Text::CSV;
use Image::Size;
use File::Spec;

my $csv_file = '02_assemble/shosi.csv';  # CSVパス
my $base_dir = '02_assemble';
my $log_file = 'check_image_log.txt';

my $csv = Text::CSV->new({ binary => 1, auto_diag => 1 });
open my $fh, "<:encoding(UTF-8)", $csv_file or die "cant open CSV: $csv_file\n";

# BOM除去
my $first_line = <$fh>;
$first_line =~ s/^\x{FEFF}//;
seek($fh, 0, 0);

open my $log_fh, '>:encoding(UTF-8)', $log_file or die "cant open log file: $log_file\n";
print $log_fh "=== result image size mismutch ===\n";

my $count_ng = 0;

while (my $row = $csv->getline($fh)) {
    next unless @$row >= 6;
    my ($g_id, $title, $prefix, $combined_name, $type) = @$row[1..5];

    next unless $type eq '素材';

    my $image_dir = File::Spec->catdir($base_dir, $prefix, 'item', 'image');
    next unless -d $image_dir;

    opendir(my $dh, $image_dir) or next;
    while (my $file = readdir($dh)) {
        next unless $file =~ /\.jpg$/i;
        my $full_path = File::Spec->catfile($image_dir, $file);
        my ($w, $h) = imgsize($full_path);
        next unless defined $w && defined $h;

        if ($w != 1600 || $h != 2560) {
            $count_ng++;
            print $log_fh "[$prefix] $file : ${w}x${h}\n";
        }
    }
    closedir($dh);
}

if ($count_ng == 0) {
    print $log_fh "all image size 1600x2560 ok\n";
    print "all image size in standard\n";
} else {
    print $log_fh "NG image：$count_ng subject found\n";
    print "NG image：$count_ng subject go $log_file sea\n";
}

close $log_fh;
