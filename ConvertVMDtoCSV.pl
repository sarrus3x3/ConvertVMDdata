# 2017/01/29

# ＊＊＊ ツールの目的 ＊＊＊
# VMDファイルのバイナリを解析してCSVファイルに変換する

# ＊＊＊ ツールの使い方 ＊＊＊
# ツールの配置されているディレクトリでコマンドプロンプトを開き、
#   >perl BinaryExpress.pl [vmdファイル名].vmd
# ツールと同ディレクトリに、csvに変換した
#   [vmdファイル名]_Convert.csv
# ファイルが生成される。
# ★ とりあえず、csv出力は標準出力にしておく。

# ＊＊＊ 出力形式 ＊＊＊
# 各ボーン毎に、横軸がブレーム番号と縦軸が属性（ボーン位置など）の表を出力する。
# 出力する属性は以下：
# * ボーンのX軸位置
# * ボーンのY軸位置
# * ボーンのZ軸位置
# * ボーンのクォータニオンのX
# * ボーンのクォータニオンのY
# * ボーンのクォータニオンのZ
# * ボーンのクォータニオンのW
# 補間パラメータの出力は省略

# ＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊
# ＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊
# ＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊

# ◆ vmdデータの構造
# 特にフレームデータのフォーマット情報。
# （vmdデータにはそれ以外にもカメラデータなども持っているらしいが、今回必要なのはフレームデータのみ）
# http://atupdate.web.fc2.com/vmd_format.htm

# vmdデータの日本語文字列で使われる文字コード
# 文字コードはシフトJIS
# 終端 0x00, パディング 0xFD(PMXモデルで保存した場合はパディング 0x00)
# http://harigane.at.webry.info/201103/article_1.html

# ◆ perlでのバイナリデータを扱う
# http://www.tohoho-web.com/perl/binary.htm

# ソースの元ネタ
# https://hgotoh.jp/wiki/doku.php/documents/perl/perl-0002

# フレームデータは、フレーム順に並んでいるわけではないらしいので、
# 一度、vmdデータを全て読み込んで、合成位置を計算し、
# それを書き込むために再度読み込み直す、という処理が必要になる。

# センター位置を直しただけでは上手くいかない。
# 足のIKの位置も併せて修正する必要があるよう？
# → 上手くいった、よっしゃああああ！

# ＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊

# 2017/01/29
# ・先頭と最後に変なデータが入る。（framenumがめちゃくちゃなことから、違うフォーマットであることは確か）
#   → フレームデータ以外のものだろうか... もっと詳しいフォーマット情報がないと...
#   → sortしているから、後ろの方で出力された変なデータが出力されているだけだ。気にしなくていい。
# ・IKにもクオータニオンが入る。これは困ったなぁ...
#   → この謎を解明しなくては...


# 宣言無しでの変数の使用不可
use strict;

#日本語対応。
use utf8;
use Encode qw/encode decode/;

# ------------------------ ここから ---------------------------
my $code;

###### 変数定義

# 接頭句（char[30]）"Vocaloid Motion Data 0002\0" の文字列
my $Prefix;

# モデル名（char[20]）
my $ModelName;

# フレームデータ数
my $MaxFrameNum;

# vmdデータの格納用ハッシュ
my %VmdDataHash;

###### 読み込みvmdデータの準備

my $VmdDataFile = decode('cp932', $ARGV[0] );
#my $VmdDataFile = "sampledata.vmd";

# vmdデータをopen
open ( IN, encode('cp932', $VmdDataFile ) ) or die "$!";
binmode(IN); # バイナリモードにセット

###### vmd ファイルの読み込み開始

###### ヘッダー部の解析

# 接頭句の抽出
last if undef == read(IN, $code, 30); 
$Prefix = unpack("Z*",$code);  # ヌル文字で終わる文字列。配列の最後まで処理するには最後に"*"をつけなきゃいけない。使い方についてのドキュメントが殆ど無い...

# モデル名の抽出
last if undef == read(IN, $code, 20); 
$ModelName = unpack("Z*",$code);  # ヌル文字で終わる文字列。配列の最後まで処理するには最後に"*"をつけなきゃいけない。使い方についてのドキュメントが殆ど無い...

# フレームデータ数の抽出
last if undef == read(IN, $code, 4 );
$MaxFrameNum = unpack("L",$code); # unsigned log

print "Prefix:"     , $Prefix,      "\n";
print "ModelName:"  , $ModelName,   "\n";
print "MaxFrameNum:", $MaxFrameNum, "\n";

###### フレームデータの解析開始

foreach my $f ( 0 .. $MaxFrameNum-1 )
{
	my @binarray; # 読みだしたバイナリを格納
	
	my $bonename; # "頭\0"などのボーン名の文字列
	my $framenum; # フレーム番号
	
	my $boneposX; # ボーンのX軸位置。位置データがない場合は0
	my $boneposY; # ボーンのY軸位置。位置データがない場合は0
	my $boneposZ; # ボーンのZ軸位置。位置データがない場合は0
	
	my $QuatnioX; # ボーンのクォータニオンのX。データがない場合は0
	my $QuatnioY; # ボーンのクォータニオンのY。データがない場合は0
	my $QuatnioZ; # ボーンのクォータニオンのZ。データがない場合は0
	my $QuatnioW; # ボーンのクォータニオンのW。データがない場合は0
	
	# ボーン名 ～ ボーン位置情報までを読出し
	last if undef == read(IN, $binarray[0], 15); # ボーン名
	last if undef == read(IN, $binarray[1], 4);  # フレーム番号
	last if undef == read(IN, $binarray[2], 4);  # ボーンのX軸位置
	last if undef == read(IN, $binarray[3], 4);  # ボーンのY軸位置
	last if undef == read(IN, $binarray[4], 4);  # ボーンのZ軸位置
	last if undef == read(IN, $binarray[5], 4);  # ボーンのクォータニオンのX
	last if undef == read(IN, $binarray[6], 4);  # ボーンのクォータニオンのY
	last if undef == read(IN, $binarray[7], 4);  # ボーンのクォータニオンのZ
	last if undef == read(IN, $binarray[8], 4);  # ボーンのクォータニオンのW
	last if undef == read(IN, $binarray[9], 64 ); # 補間パラメータ（使用しない）

	$bonename = unpack("Z*",$binarray[0]);  # ヌル文字で終わる文字列。配列の最後まで処理するには最後に"*"をつけなきゃいけない。使い方についてのドキュメントが殆ど無い...
	$framenum = unpack("L" ,$binarray[1]);  # unsigned log
	$boneposX = unpack("f" ,$binarray[2]);
	$boneposY = unpack("f" ,$binarray[3]);
	$boneposZ = unpack("f" ,$binarray[4]);
	$QuatnioX = unpack("f" ,$binarray[5]);
	$QuatnioY = unpack("f" ,$binarray[6]);
	$QuatnioZ = unpack("f" ,$binarray[7]);
	$QuatnioW = unpack("f" ,$binarray[8]);
	
	# 念のため、ボーン名を内部文字列に変換しておく
	$bonename = decode('SJIS', $bonename );
	
	# フレームデータをハッシュに格納
	$VmdDataHash{$bonename}{$framenum} = { 
		'boneposX' => $boneposX,
		'boneposY' => $boneposY,
		'boneposZ' => $boneposZ,
		'QuatnioX' => $QuatnioX,
		'QuatnioY' => $QuatnioY,
		'QuatnioZ' => $QuatnioZ,
		'QuatnioW' => $QuatnioW
		};
	
	
}

# csv出力（タブ区切り）
foreach my $bonename ( sort keys %VmdDataHash ){
	# ボーン名を出力
	print encode('cp932', $bonename );
	print encode('cp932', "\n" );
	
	# 各属性のラインを定義
	my $line_framenum ="framenum:";
	my $line_boneposX ="boneposX:";
	my $line_boneposY ="boneposY:";
	my $line_boneposZ ="boneposZ:";
	my $line_QuatnioX ="QuatnioX:";
	my $line_QuatnioY ="QuatnioY:";;
	my $line_QuatnioZ ="QuatnioZ:";;
	my $line_QuatnioW ="QuatnioW:";;
	
	foreach my $framenum ( sort {$a <=> $b} keys %{$VmdDataHash{$bonename}} ){ # 数値昇順ソートする
		$line_framenum .= "\t". $framenum;
		$line_boneposX .= "\t". $VmdDataHash{$bonename}{$framenum}{'boneposX'};
		$line_boneposY .= "\t". $VmdDataHash{$bonename}{$framenum}{'boneposY'};
		$line_boneposZ .= "\t". $VmdDataHash{$bonename}{$framenum}{'boneposZ'};
		$line_QuatnioX .= "\t". $VmdDataHash{$bonename}{$framenum}{'QuatnioX'};
		$line_QuatnioY .= "\t". $VmdDataHash{$bonename}{$framenum}{'QuatnioY'};
		$line_QuatnioZ .= "\t". $VmdDataHash{$bonename}{$framenum}{'QuatnioZ'};
		$line_QuatnioW .= "\t". $VmdDataHash{$bonename}{$framenum}{'QuatnioW'};
		
	}
	
	# 最後に改行を付与
	$line_framenum .= "\n";
	$line_boneposX .= "\n";
	$line_boneposY .= "\n";
	$line_boneposZ .= "\n";
	$line_QuatnioX .= "\n";
	$line_QuatnioY .= "\n";
	$line_QuatnioZ .= "\n";
	$line_QuatnioW .= "\n";
	
	# 各属性のラインを出力
	print encode('cp932', $line_framenum );
	print encode('cp932', $line_boneposX );
	print encode('cp932', $line_boneposY );
	print encode('cp932', $line_boneposZ );
	print encode('cp932', $line_QuatnioX );
	print encode('cp932', $line_QuatnioY );
	print encode('cp932', $line_QuatnioZ );
	print encode('cp932', $line_QuatnioW );
	
	# ボーンの区切り
	print encode('cp932', "--------------\n" );
	
	
}


