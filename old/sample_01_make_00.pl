#!/usr/local/bin/perl

use strict;
use warnings;

use utf8;
binmode STDIN, 'encoding(cp932)';
binmode STDOUT, 'encoding(cp932)';
binmode STDERR, 'encoding(cp932)';
use Encode;

use File::Path 'mkpath';
use File::Copy;
use File::Copy::Recursive qw(rcopy);
use File::Path qw(remove_tree);
#	use File::Path qw(rmtree);

use Image::Size 'imgsize';

use Text::CSV; 

use DateTime;
use DateTime::Format::ISO8601;


    my @img_list;
    my @xhtml_list;
    my @spine_list;

    my @shosi;
    my @koumoku_content;
    
    my @standard_opf;
    my @xhtml_one;

    my $page_count;
    my $image_count;
    my @tmp_var;
        
    my $gazou_count;    
    my $count;

    my @log;
    
	my @chosha_mei;
	my @chosha_katakana;
    my @chosha_temp;
    my @go_opf_chosha;
    
    my $ichi_height;
	my $width;
        
	my @mate_folders;

	my @cut_spine_list;	
	my @go_spine_list;

	my $template_content;

	my @mokuji_list;
	my @navig_list;
	my @go_mokuji;

	my @go_navpoint;
	my $mokuji_phrase;

	my @renamed_img;
	my @renamed_xhtml;
	my @pre_print_spine;

	my @xhtml_colophon;
	my $img_count;

	my @gazou_files;
    my @adjusted_spine;

	my $playOrder_end;

	my $mokuji_fuyou_pt1;
	my $mokuji_fuyou_pt2;
	my $mokuji_cut;


#	========================================================================================================

#　要新規の作り込み	-----------------------------------------------------
#	△	書誌配列の番号書き直し
#	△	opf見開きで左右方向の分岐
#			・ltrとrtl？（各行のright、leftが逆）
#	〇	著者数の分割
#	△	templateのstandard.opfをあちこち改修
#	〇	表紙・奥付画像の別処理
#			かなり後の方で、フォルダに放り込む（情報が取り込まれる・ファイル名変更などを避ける）
#	未	表紙・奥付のxhtml出力
#	未	入稿フォルダと出力ファイル名

#	中	全体整備	-----------------------------------------------------------
#			素材入りと置き場、処理フォルダ、フォルダ名とスクリプト整理

#	p-000画像、htmlがない（spineのみある）、処理考え
#	アップデート日の記入
#		use Time::Piece;
#		my $t = localtime;  # 現在の日時を取得
#		my $today = $t->ymd;  # "YYYY-MM-DD" 形式で日付を取得
#		print "Today is $today\n";	

#	===========================================================================================================
#	rmdir("04_output/$koumoku{'kd_num'}") or die "cant delete folder\n";		#未完成。データ残りあるとあるとエラーになるのであらかじめデータ除去。	

#	=========================================================================================================
#	opfに使うタグの、imgリスト & xhtmlリスト & spineリストの取り込み 

#    open(IN_IMG_LIST, "<:encoding(UTF-8)", "01_templates/opf_img.txt") or die "cant open img_list\n";
#    @img_list = <IN_IMG_LIST>;
#    close(IN_IMG_LIST);

#    open(IN_XHTML_LIST, "<:encoding(UTF-8)", "01_templates/opf_xhtml.txt") or die "cant open xhtml_list\n";
#    @xhtml_list = <IN_XHTML_LIST>;
#    close(IN_XHTML_LIST);
    
#    open(IN_SPINE_LIST, "<:encoding(UTF-8)", "01_templates/opf_spine.txt") or die "cant open spine_list\n";
#    @spine_list = <IN_SPINE_LIST>;
#    close(IN_SPINE_LIST);


#    shosi.csvの読み込み部分   	 ===========================================================================

my $file = '03_materials/shosi.csv';
my $csv = Text::CSV->new({ binary => 1, auto_diag => 1 });

# CSVファイルを開く
open(IN_SHOSI, "<:encoding(UTF-8)", $file) or die "cant open $file: $!";
 @shosi = <IN_SHOSI>;
close(IN_SHOSI);


    foreach(@shosi)   	 
   	{
   		@koumoku_content = split(/,/);
   		 
   		&pre_check;						#prcs00		書誌とデータのチェック
   		 
   		&chosha_divide;					#prcs01		著者複数の場合

   		&output_folders;   				#prcs02		フォルダ類＆画像ファイルを出力

   		&gazou_glob;   					#prcs03		画像情報の取得
   		 
   		&make_xhtml_one;   				#prcs04		p-001xhtmlのセッティング

   		&make_xhtml_extra;   				#prcs05		p-002以降のxhtmlのセッティング

   		&make_xhtml_okuduke;   				#	奥付xhtmlのセッティング

   		&make_opf;   						#prcs06		opfファイルのセッティング

		&output_image_extra; 

		if($koumoku_content[6] eq "yes") {
			&make_mokuji;
		} else {
			&no_mokuji;
		}
   		 
   		&output_txts;   					#prcs07		テキスト類の出力

		&remove_needless;					#不要フォルダ等削除
   		 
   		&output_log;						#prcs08		ログファイルの出力

   	}

   	 open(LOGS, ">:encoding(UTF-8)", "04_output/log.txt") or die "cant open log_file\n";   	 #002以降xhtmlファイルの出力
   	 print LOGS @log;
   	 close(LOGS);


# 事前チェック    ===========================================================================
    sub pre_check{
		
		opendir(DIRHANDLE, "03_materials");		# ディレクトリエントリの取得

		foreach(readdir(DIRHANDLE)){
			next if /^\.{1,2}$/;				# '.'や'..'をスキップ
#			print "$_\n";
		}

		my $data = $koumoku_content[4];
		
		for (@mate_folders) {

		if ($_ eq $data){
  				print "ok\n";
			} else {
  				print "$data nai\n";
		}

		}


	}

# 画像情報を作成    ===========================================================================
    sub gazou_glob{

    # jpg のファイル数を取得    -----------------------------
   	@gazou_files = glob("04_output/$koumoku_content[4]/item/image/*.jpg");   		 #outpubフォルダ内画像

   	 # ファイル数カウント    -----------------------------
   	 $count = 0;

   	 while ($count < @gazou_files){

#   	my $img_count = $count + 1;							#画像が001から始まるように。
   		my $img_count = $count;							#画像が000から始まるように。

   		my $sanketa_number = sprintf("%03d", $img_count);    				#ファイル名が000の3桁なので。

   		rename $gazou_files[$count], "04_output/$koumoku_content[4]/item/image/i-$sanketa_number.jpg";
		 																		#画像リネーム 
   		push(@renamed_img, "<item media-type=\"image/jpeg\" id=\"i-$sanketa_number\" href=\"image/i-$sanketa_number.jpg\"/>\n");   				 #リネーム画像を配列入れ
   		push(@renamed_xhtml, "<item media-type=\"application/xhtml\+xml\" id=\"p-$sanketa_number\" href=\"xhtml/p-$sanketa_number.xhtml\" properties=\"svg\" fallback=\"i-$sanketa_number\"/>\n");   				 #リネーム画像を配列入れ

		push(@pre_print_spine, "<itemref linear=\"yes\" idref=\"p-$sanketa_number\" properties=\"page-spread-\"/>\n");

   			 $count ++;

   		 }
   		 
   		 my $gazou_count = $count;   												#確定の画像数
#  		 print "$koumoku_content[4] gazou count ha $gazou_count\n";   				 #確認用

   		 $page_count = $gazou_count - 1;   						 #画像数-1、が作るxhtmlページ数
#  		 print "page_count ha $page_count\n";   				 #確認用

		@gazou_files = ();	

     }


#    表紙ページxhtmlの読み込み部分    ===========================================================================

    sub make_xhtml_one{
    
		open(IN_01, "<:encoding(UTF-8)", "01_templates/p-cover.xhtml") or die "cant open cover_xhtml\n";
		@xhtml_one = <IN_01>;
		close(IN_01);

#	i-001.jpg のサイズを取得    ------------------------------------

		my $zeroone = glob("04_output/$koumoku_content[4]/item/image/front_end/i-cover.jpg");   				#
   	# .jpg のサイズを取得
		($width, $ichi_height) = imgsize("04_output/$koumoku_content[4]/item/image/front_end/i-cover.jpg");		#パターンa	001を直で指定	イキ

#   	 print $xhtml_one[0];   						 #確認用

   	 foreach(@xhtml_one){

   			 &umekomi;   								 
  			s/▼縦サイズ▼/$ichi_height/g;   			#環境変数から用意
  			s/▼横サイズ▼/$width/g;   			 	#環境変数から用意_1030に幅700pix（仕様）戻しに伴い修正追加
#			$ichi_height = ();

   		 }
    }


#    p-002.xhtml以降の作成部分    ===========================================================================

    sub make_xhtml_extra{
   	 
    #    xhtmlの2枚目以降を作成   	 ----------------------------------------
    
   	 my $pcounter = 0;

   	 while ($pcounter <= $page_count) {
   		 
# 		my $page_num = $pcounter + 1;		#xhtmlが001から始まるように
   		my $page_num = $pcounter;
   		 
   			 # p-3桁のファイル連番を作成    -----------------------
   				 my $sanketa_name = sprintf("%03d", $page_num);
#   				 print $sanketa . "\n";

   	 my $two_after = glob("04_output/$koumoku_content[4]/item/image/i-$sanketa_name.jpg");   		 #materialフォルダ内画像

   	 # .jpg のサイズを取得
#   		 (my $width, my $two_after_height) = imgsize($two_after);
   		 (my $width, my $two_after_height) = imgsize("04_output/$koumoku_content[4]/item/image/i-$sanketa_name.jpg");

#   			 print "$width and $two_after_height\n";   										#画像サイズ    確認テスト

   			 # p-002のテンプレを読み込む    -----------------------

   				 open(IN_02, "<:encoding(UTF-8)", "01_templates/p-00n.xhtml") or die "cant open 02xhtml\n";;
   				 my @xhtml_extra = <IN_02>;
   				 close(IN_02);
   	 
    #   		 ----------------------------------------

   			 foreach(@xhtml_extra) {
   						 &umekomi;    
    					s/▼ファイル名数字▼/$sanketa_name/g;   		#xhtmlファイル名
  						s/▼縦サイズ▼/$two_after_height/g;   			 #環境変数から用意
  						s/▼横サイズ▼/$width/g;   			 		#環境変数から用意_1030に幅700pix（仕様）戻しに伴い修正追加
   					 }

   			 # p-002以降のhtml名を生成    -----------------------
   			 my $file_count_name = "p-" . $sanketa_name . ".xhtml";   								 #    
#   			 print $file_count_name ."\n";   										 #xhtmファイル名テスト　1枚ずつ出力

#   			 print $sanketa_name ." sanketa\n";   										 #上がる

   	 open(OUT_02, ">:encoding(UTF-8)", "04_output/$koumoku_content[4]/item/xhtml/$file_count_name") or die "cant open xhtml_extra\n";   	 #002以降xhtmlファイルの出力
   	 print OUT_02 @xhtml_extra;
   	 close(OUT_02);
   	 
   	     	$pcounter ++;
   		 }

    }

#    奥付xhtmlの作成部分    ===========================================================================

    sub make_xhtml_okuduke {

		open(IN_OKU, "<:encoding(UTF-8)", "01_templates/p-colophon.xhtml") or die "cant open colophon_xhtml\n";
		@xhtml_colophon = <IN_OKU>;
		close(IN_OKU);

		foreach(@xhtml_colophon){

   			 &umekomi;   								 
  			s/▼縦サイズ▼/$ichi_height/g;   			#環境変数から用意
  			s/▼横サイズ▼/$width/g;   			 	#環境変数から用意_1030に幅700pix（仕様）戻しに伴い修正追加
		}
	}

#    standard.opfの作成    ===========================================================================

    sub make_opf{   				 

   	 open(IN_STD, "<:encoding(UTF-8)", "01_templates/standard.opf")  or die "cant open opf\n";
   	 @standard_opf = <IN_STD>;
   	 close(IN_STD);

#   		 print $standard_opf[0];   											 #確認用

   	$image_count = $page_count - 1;
   				 
	&make_spine;

   	foreach(@standard_opf)   	 
   		 {
   			&umekomi;   												 #

   			s/▼著者情報テキスト挿入位置▼/join "", @go_opf_chosha/eg;   			 #サブルーチン chosha_divide の生成テキストを挿入

   			s/▼画像ファイルタグ印字位置▼/join "", @renamed_img/e;   			 #これがいちばんマシ

   			s/▼xhtmlファイルタグ印字位置▼/join "", @renamed_xhtml/eg;   		 #環境変数から用意
 
   			s/▼spineタグ印字位置▼/join "", @adjusted_spine/eg;   				 #環境変数から用意。古い書き方
#   			s/▼spineタグ印字位置▼/join "", @pre_print_spine/eg;   				 #環境変数から用意。古い書き方
#			my $replacement = join "\n", @go_spine_list; 				# 改行で結合
#			s/▼spineタグ印字位置▼/$replacement/g;
   		 }
   		 
   	@go_opf_chosha = ();											#opfに埋め込む著者情報の配列を初期化
	@renamed_img = ();
	@renamed_xhtml = ();
	@pre_print_spine = ();
    @adjusted_spine = ();

    }


# 	サブルーチン　opf内のspine作成  	=========================================================================
#		ltr・rtlの分岐とleft・rightの交互出力

	sub make_spine{

    # 読み方向 (ltr または rtl)
    my $reading_direction = $koumoku_content[5];

    # 初期のプロパティを決定
    my $left_property = 'left';
    my $right_property = 'right';

# 配列の内容を調整
my $first_direction;  # 最初の要素のプロパティ
my $last_direction;   # 最後の要素のプロパティ

for my $i (0 .. $#pre_print_spine) {
    my $itemref = $pre_print_spine[$i];
    
    # 最初の要素のプロパティを設定
    if ($i == 0) {
        $first_direction = ($reading_direction eq 'rtl') ? $right_property : $left_property;
    }

    # 交互にプロパティを設定
    my $direction = ($i % 2 == 0) ? $first_direction : ($first_direction eq 'left' ? 'right' : 'left');   
    # 最後のプロパティを保存
    $last_direction = $direction;  

    $itemref =~ s/page-spread-/page-spread-$direction/;
    push @adjusted_spine, $itemref;
}

	# 最後のページ（奥付）のプロパティを設定（直前と異なるようにする）
	my $final_direction = ($last_direction eq 'left') ? 'right' : 'left';
	my $final_itemref = '<itemref linear="yes" idref="p-colophon" properties="page-spread-' . $final_direction . '"/>';
	push @adjusted_spine, $final_itemref;


	}


#    出力    ===========================================================================

#    フォルダ・画像類の出力・コピー    ------------------------------------------

    sub output_folders{

#   	 $koumoku_name[4];   							 #話のファイル名

   	 mkdir("04_output/$koumoku_content[4]", 0755) or die "話のフォルダを作成できませんでした\n";
   	 mkdir("04_output/$koumoku_content[4]/item", 0755) or die "itemフォルダを作成できませんでした\n";
   	 mkdir("04_output/$koumoku_content[4]/META-INF", 0755) or die "META-INFのフォルダを作成できませんでした\n";
   	 mkdir("04_output/$koumoku_content[4]/item/xhtml", 0755) or die "xmlフォルダを作成できませんでした\n";
   	 mkdir("04_output/$koumoku_content[4]/item/style", 0755) or die "styleのフォルダを作成できませんでした\n";
   	 mkdir("04_output/$koumoku_content[4]/item/image", 0755) or die "話の画像のフォルダを作成できませんでした\n";

   	#    テンプレよりテキスト類のコピー    -----------    

   	 rcopy("01_templates/META-INF/container.xml","04_output/$koumoku_content[4]/META-INF") or die "container.xmlをコピーできません\n";
   	 rcopy("01_templates/mimetype","04_output/$koumoku_content[4]") or die "mimetypeをコピーできません\n";
   	 rcopy("01_templates/item/style","04_output/$koumoku_content[4]/item/style") or die "styleをコピーできません\n";

  	 #    画像ファイルコピー    -----------    

   	 rcopy("03_materials/$koumoku_content[4]","04_output/$koumoku_content[4]/item/image") or die "$koumoku_content[4]の画像をコピーできません\n";
					#注意：英数字以外のファイル名が引っかかるっぽい

  	 #    shosi.csvを生成xhtml階層にログ的コピー保存    -----------    

   	 rcopy("03_materials/shosi.csv","04_output") or die "shosiを履歴用にコピーできません\n";
   	 rcopy("03_materials/$koumoku_content[4]/front_end/mokuji.csv","04_output") or die "mokujiを履歴用にコピーできません\n";

    }


	#    情報処理の後、本体以外（前付・後付）の画像配置   ------------------------------------------

    sub output_image_extra {
		rcopy("03_materials/$koumoku_content[4]/front_end/i-cover.jpg","04_output/$koumoku_content[4]/item/image") or die "カバー画像をコピーできません\n";
		rcopy("03_materials/$koumoku_content[4]/front_end/i-colophon.jpg","04_output/$koumoku_content[4]/item/image") or die "奥付画像をコピーできません\n";
	}


    #    テキスト類の出力    ----------------------------------------------------------------------------
    
   	 sub output_txts{

		open(OUT_STD, ">:encoding(UTF-8)", "04_output/$koumoku_content[4]/item/standard.opf") or die "cant make opf\n";   		 #opfファイルの出力
		print OUT_STD @standard_opf;
		close(OUT_STD);

		open(OUT_01, ">:encoding(UTF-8)", "04_output/$koumoku_content[4]/item/xhtml/p-cover.xhtml") or die "cant make cover_xhtml\n";   	 #001のxhtmlファイルの出力
		print OUT_01 @xhtml_one;
		close(OUT_01);

		open(OUT_END, ">:encoding(UTF-8)", "04_output/$koumoku_content[4]/item/xhtml/p-colophon.xhtml") or die "cant make okuduke\n";   	 #001のxhtmlファイルの出力
		print OUT_END @xhtml_colophon;
		close(OUT_END);

    }

	#	不要フォルダの削除    ----------------------------------------------------------------------------

	sub remove_needless {

		my $directory = "04_output/$koumoku_content[4]/item/image/front_end";  # 削除したいディレクトリのパス

		# フォルダ内のファイルを取得
			opendir(my $dh, $directory) or die "can't opendir $directory: $!";
			my @files = grep { -f "$directory/$_" } readdir($dh);
			closedir $dh;

		# ファイルを削除
		foreach my $file (@files) {
    		my $path = "$directory/$file";
    		unlink $path or warn "unlink $path failed: $!";
		}

		# フォルダが空かどうかを再度確認
		if (not glob("$directory/*")) {
    		print "Directory $directory is now empty.\n";
		} else {
    		print "Failed to delete all files in directory $directory.\n";
		}

		# ディレクトリを削除
			remove_tree($directory, { error => \my $err });

		# エラーチェック
			if (@$err) {
				for my $diag (@$err) {
				my ($file, $message) = %$diag;
					if ($file eq '') {
            			print "General error: $message\n";
        			} else {
            			print "Problem unlinking $file: $message\n";
        			}
    			}
			} else {
				    print "Directory $directory removed successfully.\n";
			}
	}


# サブルーチン　文字変換    ===========================================================================

sub umekomi {
    s/●タイトル名●/$koumoku_content[0]/g;   			 #2L以上は使わない
    s/●話巻順番●/$koumoku_content[1]/g;   			 #2L以上は使わない
    s/●タイトル名カタカナ●/$koumoku_content[9]/g;   	 #2L以上は使わない
    s/●話数3桁●/$koumoku_content[2]/g;   			 	#2L以上は使わない

    s/●出版社名●/$koumoku_content[11]/g;   			 #2L以上は使わない
    s/●出版社名カタカナ●/$koumoku_content[13]/g;   	 #2L以上は使わない

	$mokuji_fuyou_pt1 = '<item media-type="application/x-dtbncx+xml" id="ncx" href="toc.ncx"/>';
	$mokuji_fuyou_pt2 = ' toc="ncx"';

	if ($koumoku_content[6] ne "yes") {
		s/\Q$mokuji_fuyou_pt1\E//;			# 正規表現の中で変数を展開する際は、// を \Q...\E で囲む
		s/\Q$mokuji_fuyou_pt2\E//;
	} 

    s/●読み方向●/$koumoku_content[5]/g;   	 #2L以上は使わない

	# 現在の日時を取得
	my $dt = DateTime->now;
	# ISO 8601形式で出力
	my $iso8601_string = $dt->iso8601 . 'Z';
    s/●作業日時●/$iso8601_string/g;   	 

    s/●基準幅●/$width/g;   	 
    s/●基準高●/$ichi_height/g;   	

}


# サブルーチン　ログ出力    ===========================================================================

    sub output_log{

   	 push(@log, "$koumoku_content[4]," . "$koumoku_content[0],". "$koumoku_content[2]\n");   		#0901 update

	}


# サブルーチン　著者分割    ===========================================================================
#	12から23が著者名と著者名カタカナに交互に並ぶ。
#	人数分出力と、カウント回し

    sub chosha_divide{
    
    	  @chosha_mei = ($koumoku_content[14], 
		 					$koumoku_content[16], 
		  					$koumoku_content[18], 
							$koumoku_content[20], 
							$koumoku_content[22], 
							$koumoku_content[24]);    	  
    	  @chosha_katakana = ($koumoku_content[15], 
								$koumoku_content[17], 
								$koumoku_content[19], 
								$koumoku_content[21], 
								$koumoku_content[23], 
								$koumoku_content[25]);

		my @chosha_meibo;  # 空の配列を初期化する

		# 特定のインデックスから始まる要素をチェックし、カラであればループを終了する
			for my $index (14, 16, 18, 20, 22, 24) {
   				my $element = $koumoku_content[$index];
				last unless defined $element && $element ne '';  # カラでないことをチェックしてループを終了する
    			push @chosha_meibo, $element;  # 配列に要素を追加する
			}

			my $chosha_counter = 0;

   			while ($chosha_counter < @chosha_meibo){
   			 
				my $fig_counter = $chosha_counter + 1;
#				print $fig_counter . "回目\n";
				
    			open(CHOSHA_TEMP, "<:encoding(UTF-8)", "01_templates/opf_choshamei.txt") or die "cant open opf_choshamei\n";		#著者情報のテンプレを読み込み
   	 			@chosha_temp = <CHOSHA_TEMP>;
    			close(CHOSHA_TEMP);

				foreach(@chosha_temp){

						s/●作家名●/$chosha_mei[$chosha_counter]/g;   			 						#サブルーチンに移管
						s/●作家名カタカナ●/$chosha_katakana[$chosha_counter]/g;   							#サブルーチンに移管
						s/▼作家順番▼/$fig_counter/g;
				}

   				push(@go_opf_chosha, @chosha_temp);
    	     	@chosha_temp = ();

    	     	$chosha_counter ++;
    	     	   	     
  		 	}
	}



# 	サブルーチン　目次のnavigation-documents.xhtml作成  	===========================================================================
#	
	sub make_mokuji	{

		# 目次テキストを読み込む
			open(IN_MOKUJI_LIST, "<:encoding(UTF-8)", "03_materials/$koumoku_content[4]/front_end/mokuji.csv") or die "can't open mokuji_csv\n";
			my @mokuji_list = <IN_MOKUJI_LIST>;
			close(IN_MOKUJI_LIST);

		&make_tocncx;			#	toc.ncxのサブルーチンへ

			open(IN_NAVIG_LIST, "<:encoding(UTF-8)", "01_templates/navigation-documents.xhtml") or die "can't open navigation_documents_xhtml\n";
			my @navig_list = <IN_NAVIG_LIST>;
			close(IN_NAVIG_LIST);

		# 目次行のテンプレート
			my $temp_row = '<li><a href="xhtml/p-%03d.xhtml">%s</a></li>';

		# 目次リストを処理して新しい配列に追加
			my @go_mokuji;

			foreach my $line (@mokuji_list) {
				chomp($line);  # 改行を削除
				my ($mokuji_phrase, $nonble) = split(/,/, $line);  # カンマで分割
				$nonble =~ s/^\s+|\s+$//g;  # 数値の前後の空白を削除
				if ($nonble =~ /^\d+$/) {  # 数値チェック
					push @go_mokuji, sprintf $temp_row, $nonble, $mokuji_phrase;
				} else {
					warn "Invalid page number '$nonble' in line: $line\n";
				}
			}

		# navigation-documents.xhtmlのテンプレートを処理
			foreach my $line (@navig_list) {
				$line =~ s/▼目次行印字位置▼/join("\n", @go_mokuji)/eg;  # 目次行を挿入
			}

			foreach (@navig_list) {
				s/●目次xhtmlファイル名●/$koumoku_content[7]/g;   	 #2L以上は使わない
			}


		# 処理されたテンプレートを出力（必要に応じてファイルに書き出し）
		open(OUT_NAVIG_LIST, ">:encoding(UTF-8)", "04_output/$koumoku_content[4]/item/navigation-documents.xhtml") or die "can't open output file\n";
		print OUT_NAVIG_LIST @navig_list;
		close(OUT_NAVIG_LIST);
	
	}


#   サブルーチン　旧目次仕様 toc.ncxの作成    ===========================================================================

    sub make_tocncx{   				 

		# ファイルを読み込む
		my $csv_file = "03_materials/$koumoku_content[4]/front_end/mokuji.csv";
		my $template_file = "01_templates/toc_ncx_navPoint.txt";
		my $ncx_file = "01_templates/toc.ncx";
		my $output_file = "04_output/$koumoku_content[4]/item/toc.ncx";

		open(my $fh_csv, "<:encoding(UTF-8)", $csv_file) or die "can't open $csv_file: $!";
		open(my $fh_template, "<:encoding(UTF-8)", $template_file) or die "can't open $template_file: $!";
		open(my $fh_ncx, "<:encoding(UTF-8)", $ncx_file) or die "can't open $ncx_file: $!";

		my @mokuji_list = <$fh_csv>;
		close($fh_csv);

		my $template = do { local $/; <$fh_template> };
		close($fh_template);

		my @ncx_content = <$fh_ncx>;
		close($fh_ncx);

		# 目次の各行を処理してテンプレートに挿入
			my $playOrder = 1;
			my $navPoint_id = 1;;
			my @navPoints;

		foreach my $line (@mokuji_list) {
		    chomp($line);
	    	my ($title, $page) = split(/,/, $line);
    		my $id = sprintf("p-%03d", $page);
    		my $navPoint = $template;
    		$navPoint =~ s/●navPoint_id●/xhtml-n-$navPoint_id/g;
	    	$navPoint =~ s/▼playOrder順番▼/$playOrder/g;
    		$navPoint =~ s/●目次項目●/$title/g;
	    	$navPoint =~ s/●xhtmlファイル名●/$id.xhtml/g;
	    	push @navPoints, $navPoint;
    		$playOrder++;
    		$navPoint_id++;
		}

		$playOrder_end = $playOrder;

		# ncxファイルの内容に目次を埋め込む
		my $navPoints_text = join("\n", @navPoints);
		foreach my $line (@ncx_content) {
    		$line =~ s/▼navPointタグ印字位置▼/$navPoints_text/eg;

			$line =~ s/●playorder_end●/$playOrder_end/g;
		}

		# 処理された内容を出力ファイルに書き出し
		open(my $fh_output, ">:encoding(UTF-8)", $output_file) or die "can't open $output_file: $!";
		print $fh_output @ncx_content;
		close($fh_output);

	}

# 	サブルーチン　目次を作らない 	===========================================================================
#		navigation-documents.xhtmlの目次をカット & toc.ncxを作らない

	sub no_mokuji {

			open(GET_NAVIG_LIST, "<:encoding(UTF-8)", "01_templates/navigation-documents.xhtml") or die "can't open navigation_documents_xhtml\n";
			my @navigate_list = <GET_NAVIG_LIST>;
			close(GET_NAVIG_LIST);

			$mokuji_cut = '<li><a epub:type="toc" href="xhtml/p-●目次xhtmlファイル名●.xhtml">目次</a></li>';


				foreach(@navigate_list){

						s/▼目次行印字位置▼//g;   			 						#サブルーチンに移管
						s/$mokuji_cut//;   							#サブルーチンに移管
				}

		open(PUT_NAVIG_LIST, ">:encoding(UTF-8)", "04_output/$koumoku_content[4]/item/navigation-documents.xhtml") or die "can't open output file\n";
		print PUT_NAVIG_LIST @navigate_list;
		close(PUT_NAVIG_LIST);

	}




