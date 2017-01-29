# 2016/08/11

# ＊＊＊ ツールの目的 ＊＊＊
# "全ての親"ボーンの位置座標が原点になるように、
# 各ボーン※の位置座標をシフトさせます。
# ※対象となるボーン：センター、左足ＩＫ、右足ＩＫ。

# （これ、説明文がわかりにくいな。）
# 【修正】
# 見た目の各ボーンの「位置・回転」を維持したまま、
# 全ての親ボーンの位置を原点にシフトする。
# そのために、全ての親ボーンの直接の子ボーン（センター、左足ＩＫ、右足ＩＫ の３ボーン）
# の位置を補正する。（※今は回転はサポート対象外）

# なぜ、こんな変換が必要かというと、
# モーションをゲームに取り込むにあたり、
# ワールド原点位置が（ゲーム上）キャラクタの位置になるように、
# MMDで補正している。
# ゲームのモデルには、全ての親ボーンがないため、
# 全ての親ボーン補正の意味がなくなってしまうため、
# 全ての親ボーンの位置を各子ボーンに反映させるという操作が必要になる。
# i.e. 「「各子ボーンの位置を、全ての親ボーンのワールド座標に変換する。」」←この説明が一番わかり易いな。

# ＊＊＊ ツールの使い方 ＊＊＊
# ツールの配置されているディレクトリでコマンドプロンプトを開き、
#   >perl BinaryExpress.pl [vmdファイル名]
# ツールと同ディレクトリに、位置情報を変換した
#   Edited[vmdファイル名]
# ファイルが生成される。

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

# 宣言無しでの変数の使用不可
use strict;

#日本語対応。
use utf8;
use Encode qw/encode decode/;

# ------------------------ ここから ---------------------------
my $code;
my %ParentHash; # $ParentHash{フレーム番号} = "全ての親"ボーンの位置座標
#my %CenterHash; # $CenterHash{フレーム番号} = "センター"ボーンの位置座標
#my %R_FootHash; # 同、"右足ＩＫ"ボーンの位置座標
#my %L_FootHash; # 同、"左足ＩＫ"ボーンの位置座標 

my %FramesHash; # $ParentHash と $CenterHash のフレーム番号を保持

my $SuccessFlg = 1;

###### 合成の対象フレーム名を定義
my $parent; # 全ての親
my $center; # センター
my $r_foot; # 右足ＩＫ
my $l_foot; # 左足ＩＫ
$parent = encode('SJIS', "全ての親" );
$center = encode('SJIS', "センター" );
$r_foot = encode('SJIS', "右足ＩＫ" );
$l_foot = encode('SJIS', "左足ＩＫ" );

###### 読み込みvmdデータの準備

my $VmdDataFile = decode('cp932', $ARGV[0] );
#my $VmdDataFile = "sampledata.vmd";

# vmdデータをopen
open ( IN, encode('cp932', $VmdDataFile ) ) or die "$!";
binmode(IN); # バイナリモードにセット

###### vmd ファイルの読み込み開始
last if undef == read(IN, $code, 50); # フレームデータの場所までシフト

my $MaxFrameNum; # フレームデータ数
last if undef == read(IN, $code, 4 );
$MaxFrameNum = unpack("L",$code); # unsigned log
print "MaxFrameNum:", $MaxFrameNum, "\n";

while(1)
{
	my @binarray; # 読みだしたバイナリを格納
	
	my $bonename; # "頭\0"などのボーン名の文字列
	my $framenum; # フレーム番号
	my $boneposX; # ボーンのX軸位置。位置データがない場合は0
	my $boneposY; # ボーンのY軸位置。位置データがない場合は0
	my $boneposZ; # ボーンのZ軸位置。位置データがない場合は0
	
	# 回転データは今回はサポート外だが、将来の拡張に備えて宣言だけはしておく
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

	# 残りのバイナリを読みだし。補間パラメータはよくわからないのでサポート対象外
	my $remsize = 4 + 4 + 4 + 4 + 64; # 俺はコンパイラの最適化を信じるぜ！
	last if undef == read(IN, $binarray[5], $remsize );

	$bonename = unpack("Z*",$binarray[0]);  # ヌル文字で終わる文字列。配列の最後まで処理するには最後に"*"をつけなきゃいけない。使い方についてのドキュメントが殆ど無い...
	$framenum = unpack("L" ,$binarray[1]);  # unsigned log
	$boneposX = unpack("f" ,$binarray[2]);
	$boneposY = unpack("f" ,$binarray[3]);
	$boneposZ = unpack("f" ,$binarray[4]);
	
	if($parent eq $bonename)
	{
		# "全ての親"ボーンの場合
		$ParentHash{$framenum} = { 
			'X' => $boneposX,
			'Y' => $boneposY,
			'Z' => $boneposZ 
			};
		$FramesHash{$framenum} += 1;
	}
	
	# 出力
	print "Bone  Name:", $bonename, "\n";
	print "Frame Name:", $framenum, "\n";
	print "Bone Pos X:", $boneposX, "\n";
	print "Bone Pos Y:", $boneposY, "\n";
	print "Bone Pos Z:", $boneposZ, "\n";
	print "\n\n";

} 
close(IN);


###### 出力vmdデータの準備

# 書き戻しのために、入力vmdデータファイルを開き直す
open ( IN, encode('cp932', $VmdDataFile ) ) or die "$!";
binmode(IN); # バイナリモードにセット

# 書き戻し用のファイルを開く
my $EditedVmdDataFile = "Edited" . $VmdDataFile ;
open ( OUT, encode('cp932', ">$EditedVmdDataFile" ) ) or die "$!"; 
binmode(OUT); # バイナリモードにセット


###### vmdデータの書き戻し開始

# フレームデータの場所までシフト
read( IN, $code, 54 ); 
print OUT $code ;

# フレームデータの読み込み
foreach my $f ( 0 .. $MaxFrameNum-1 )
{
	my @binarray; # 読みだしたバイナリを格納
	
	my $bonename; # "頭\0"などのボーン名の文字列
	my $framenum; # フレーム番号
	my $boneposX; # ボーンのX軸位置。位置データがない場合は0
	my $boneposY; # ボーンのY軸位置。位置データがない場合は0
	my $boneposZ; # ボーンのZ軸位置。位置データがない場合は0
	
	# ボーン名 ～ ボーン位置情報までを読出し
	last if undef == read(IN, $binarray[0], 15); # ボーン名
	last if undef == read(IN, $binarray[1], 4);  # フレーム番号
	last if undef == read(IN, $binarray[2], 4);  # ボーンのX軸位置
	last if undef == read(IN, $binarray[3], 4);  # ボーンのY軸位置
	last if undef == read(IN, $binarray[4], 4);  # ボーンのZ軸位置

	# 残りのバイナリを読みだし
	my $remsize = 4 + 4 + 4 + 4 + 64; # 俺はコンパイラの最適化を信じるぜ！ → インタプリタだから最適化なんてしないか。
	last if undef == read(IN, $binarray[5], $remsize );

	$bonename = unpack("Z*",$binarray[0]);  # ヌル文字で終わる文字列。配列の最後まで処理するには最後に"*"をつけなきゃいけない。使い方についてのドキュメントが殆ど無い...
	$framenum = unpack("L" ,$binarray[1]);  # unsigned log
	$boneposX = unpack("f" ,$binarray[2]);
	$boneposY = unpack("f" ,$binarray[3]);
	$boneposZ = unpack("f" ,$binarray[4]);
	
	# バイナリデータの編集
	if( $parent eq $bonename )
	{
		# 全ての親ボーンの位置を原点に設定
		$binarray[2] = pack("f" , 0.0 );
		$binarray[3] = pack("f" , 0.0 );
		$binarray[4] = pack("f" , 0.0 );
	}
	elsif( 
		($center eq $bonename) || 
		($r_foot eq $bonename) || 
		($l_foot eq $bonename) )
	{
		if( exists($ParentHash{$framenum}) )
		{
			# 全ての親ボーンの位置が原点にくるように、センターボーンの位置をシフトさせる。
			$binarray[2] = pack("f" , $boneposX + $ParentHash{$framenum}->{X} );
			$binarray[3] = pack("f" , $boneposY + $ParentHash{$framenum}->{Y} );
			$binarray[4] = pack("f" , $boneposZ + $ParentHash{$framenum}->{Z} );
		}
		else
		{
			$SuccessFlg = 0;
			my $bonename_decode = decode('SJIS', $bonename );
			my $outstring = "${bonename_decode}処理中、${framenum}フレーム目、全ての親のキーフレームがありません。\n";
			print encode('cp932', $outstring );
			#die;
			# 同じフレームに、"全ての親"ボーンのキーフレーム打っていない場合はサポート対象外！
			# ない場合は、エディタ（MMD）で事前にキーフレームを打っておくこと。
		}
	}
	
	# バイナリデータを書き戻し ...
	foreach my $i ( 0 .. 5 )
	{
		print OUT $binarray[$i] ;
	}
	
}

# 残りのバイナリデータを読みだして、書き戻す。
while( read(IN, $code, 1) )
{
	print OUT $code ;
}


# 成功／失敗の出力
if( $SuccessFlg == 1 )
{
	print encode('cp932', "成功" );
}
else
{
	print encode('cp932', "失敗" );
}

print "\n--- end\n";










