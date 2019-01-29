#!/bin/sh

# directories
SOURCE="v1.5"
FAT="FFmpeg-tvOS"

SCRATCH="scratch-tvos"
# must be an absolute path
THIN=`pwd`/"thin-tvos"

# absolute path to x264 library
#X264=`pwd`/../x264-ios/x264-iOS

#FDK_AAC=`pwd`/fdk-aac/fdk-aac-ios

CONFIGURE_FLAGS="--enable-cross-compile --disable-debug --disable-programs \
                 --disable-doc --enable-pic --disable-indev=avfoundation --disable-sdl2"

if [ "$X264" ]
then
	CONFIGURE_FLAGS="$CONFIGURE_FLAGS --enable-gpl --enable-libx264"
fi

if [ "$FDK_AAC" ]
then
	CONFIGURE_FLAGS="$CONFIGURE_FLAGS --enable-libfdk-aac"
fi

# avresample
#CONFIGURE_FLAGS="$CONFIGURE_FLAGS --enable-avresample"

CONFIGURE_FLAGS="$CONFIGURE_FLAGS --disable-encoders --disable-decoders --disable-hwaccels"

DECODERS="vc1 h263 h264 hevc mpeg1video mpeg2video mpeg4 aac_latm dca png apng bmp mjpeg thp gif vp8 vp9 dirac ffv1 ffvhuff huffyuv rawvideo zero12v ayuv r210 v210 v210x v308 v408 v410 y41p yuv4 ansi flac vorbis opus pcm_f32be pcm_f32le pcm_f64be pcm_f64le pcm_lxf pcm_s16be pcm_s16be_planar pcm_s16le pcm_s16le_planar pcm_s24be pcm_s24le pcm_s24le_planar pcm_s32be pcm_s32le pcm_s32le_planar pcm_s8 pcm_s8_planar pcm_u16be pcm_u16le pcm_u24be pcm_u24le pcm_u32be pcm_u32le pcm_u8 pcm_alaw pcm_mulaw ass dvbsub dvdsub ccaption pgssub jacosub microdvd movtext mpl2 pjs realtext sami ssa stl subrip subviewer subviewer1 text vplayer webvtt xsub aac_at alac_at ac3_at eac3_at mp1_at mp2_at mp3_at mp1 mp2"

for DECODER in $(echo $DECODERS | tr " " "\n"); do
	CONFIGURE_FLAGS="$CONFIGURE_FLAGS --enable-decoder=$DECODER"
done

# ENCODERS="flac alac libvorbis libopus mjpeg wrapped_avframe ass dvbsub dvdsub movtext ssa subrip text webvtt xsub pcm_f32be pcm_f32le pcm_f64be pcm_f64le pcm_s8 pcm_s8_planar pcm_s16be pcm_s16be_planar pcm_s16le pcm_s16le_planar pcm_s24be pcm_s24le pcm_s24le_planar pcm_s32be pcm_s32le pcm_s32le_planar pcm_u8 pcm_u16be pcm_u16le pcm_u24be pcm_u24le pcm_u32be pcm_u32le aac_at"
ENCODERS="png"

for ENCODER in $(echo $ENCODERS | tr " " "\n"); do
	CONFIGURE_FLAGS="$CONFIGURE_FLAGS --enable-encoder=$ENCODER"
done

HWACCELS="h263_videotoolbox mpeg1_videotoolbox h264_videotoolbox mpeg2_videotoolbox hevc_videotoolbox mpeg4_videotoolbox"

for HWACCEL in $(echo $HWACCELS | tr " " "\n"); do
	CONFIGURE_FLAGS="$CONFIGURE_FLAGS --enable-hwaccel=$HWACCEL"
done

ARCHS="arm64 x86_64"

COMPILE="y"
LIPO="y"

DEPLOYMENT_TARGET="11.0"

if [ "$*" ]
then
	if [ "$*" = "lipo" ]
	then
		# skip compile
		COMPILE=
	else
		ARCHS="$*"
		if [ $# -eq 1 ]
		then
			# skip lipo
			LIPO=
		fi
	fi
fi

if [ "$COMPILE" ]
then
	if [ ! `which yasm` ]
	then
		echo 'Yasm not found'
		if [ ! `which brew` ]
		then
			echo 'Homebrew not found. Trying to install...'
                        ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)" \
				|| exit 1
		fi
		echo 'Trying to install Yasm...'
		brew install yasm || exit 1
	fi
	if [ ! `which gas-preprocessor.pl` ]
	then
		echo 'gas-preprocessor.pl not found. Trying to install...'
		(curl -L https://github.com/libav/gas-preprocessor/raw/master/gas-preprocessor.pl \
			-o /usr/local/bin/gas-preprocessor.pl \
			&& chmod +x /usr/local/bin/gas-preprocessor.pl) \
			|| exit 1
	fi

	if [ ! -r $SOURCE ]
	then
		echo 'FFmpeg source not found. Trying to download...'
		# curl https://github.com/plexinc/plex-media-server-ffmpeg-gpl/archive/$SOURCE.zip | tar xj \
		git clone -b $SOURCE --depth 1 git@github.com:plexinc/plex-media-server-ffmpeg-gpl.git $SOURCE \
			|| exit 1
	fi

	CWD=`pwd`
	for ARCH in $ARCHS
	do
		echo "building $ARCH..."
		mkdir -p "$SCRATCH/$ARCH"
		cd "$SCRATCH/$ARCH"

		CFLAGS="-arch $ARCH"
		if [ "$ARCH" = "x86_64" ]
		then
		    PLATFORM="AppleTVSimulator"
		    CFLAGS="$CFLAGS -mtvos-simulator-version-min=$DEPLOYMENT_TARGET"
		else
		    PLATFORM="AppleTVOS"
		    CFLAGS="$CFLAGS -mtvos-version-min=$DEPLOYMENT_TARGET -fembed-bitcode"
		    if [ "$ARCH" = "arm64" ]
		    then
		        EXPORT="GASPP_FIX_XCODE5=1"
		    fi
		fi

		XCRUN_SDK=`echo $PLATFORM | tr '[:upper:]' '[:lower:]'`
		CC="xcrun -sdk $XCRUN_SDK clang"
		AR="xcrun -sdk $XCRUN_SDK ar"
		CXXFLAGS="$CFLAGS"
		LDFLAGS="$CFLAGS"
		if [ "$X264" ]
		then
			CFLAGS="$CFLAGS -I$X264/include"
			LDFLAGS="$LDFLAGS -L$X264/lib"
		fi
		if [ "$FDK_AAC" ]
		then
			CFLAGS="$CFLAGS -I$FDK_AAC/include"
			LDFLAGS="$LDFLAGS -L$FDK_AAC/lib"
		fi

		TMPDIR=${TMPDIR/%\/} $CWD/$SOURCE/configure \
		    --target-os=darwin \
		    --arch=$ARCH \
		    --cc="$CC" \
		    --ar="$AR" \
		    $CONFIGURE_FLAGS \
		    --extra-cflags="$CFLAGS" \
		    --extra-ldflags="$LDFLAGS" \
		    --prefix="$THIN/`basename $PWD`" \
		|| exit 1

		xcrun -sdk $XCRUN_SDK make -j3 install $EXPORT || exit 1
		cd $CWD
	done
fi

if [ "$LIPO" ]
then
	echo "building fat binaries..."
	mkdir -p $FAT/lib
	set - $ARCHS
	CWD=`pwd`
	cd $THIN/$1/lib
	for LIB in *.a
	do
		cd $CWD
		echo lipo -create `find $THIN -name $LIB` -output $FAT/lib/$LIB 1>&2
		lipo -create `find $THIN -name $LIB` -output $FAT/lib/$LIB || exit 1
	done

	cd $CWD
	cp -rf $THIN/$1/include $FAT
fi

echo Done
