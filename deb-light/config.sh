#!/bin/bash
scriptname=`readlink -e "$0"`
scriptpath=`dirname "$scriptname"`
set -e

gitbasedir=`git rev-parse --show-toplevel`
projname=`basename $PWD`

if [[ -f $HOME/.buildrc ]] ; then
    . $HOME/.buildrc
fi

if [[ "$BUILD_METHOD" == '' ]] ; then
    BUILD_METHOD=cmake
fi

if [[ "$BUILD_PRESET" == '' ]] ; then
    BUILD_PRESET=qt5
fi

if [[ "$BUILD_TYPE" == '' ]] ; then
    BUILD_TYPE=Debug
fi

. "$scriptpath/setccache.source"
branch=`git branch | grep '*'| cut -f2 -d' '`
if [[ "$branch" == '(HEAD' ]] ; then
    branch=`git branch | grep '*'| cut -f3 -d' '`
fi
# support for bisect:
if [[ "$branch" == '(no' ]] ; then
    branch=detached
fi
projdir=$(basename "$gitbasedir")
echo "chroot: $SCHROOT_CHROOT_NAME" > $gitbasedir/../config_${projdir}.out
echo "arch: $arch codename: $codename projdir: $projdir branch: $branch" >> $gitbasedir/../config_${projdir}.out
echo "$chprefix$arch/$codename/$branch" > $gitbasedir/../config_${projdir}.branch

case $projname in
    mythtv)
        git clean -Xfd
        if which $BUILD_PREPARE ; then
            $BUILD_PREPARE
        fi
        case $BUILD_METHOD in
            cmake)
                . "$scriptpath/getdestdir.source"
                cd ..
                rm -rf build-$BUILD_PRESET
                rm -rf $destdir
                set -o pipefail
                set -x
                cmake --preset $BUILD_PRESET \
                    -DMYTH_BUILD_PLUGINS=OFF \
                    -DCMAKE_BUILD_TYPE=$BUILD_TYPE \
                    -DCMAKE_INSTALL_PREFIX=$destdir/usr \
                    -DMYTH_RUN_PREFIX=/usr \
                    $MYTHTV_CONFIG_OPT_EXTRA \
                    |& tee -a $gitbasedir/../config_${projdir}.out
                set +x
                set +o pipefail
                ;;
            make)
                if [ "$arch" = "aarch64" ] || [ "$arch" = "arm64" ] ; then
                    config_opt="--enable-libmp3lame --disable-vdpau \
                      --enable-opengl  \
                      --disable-vaapi \
                      --cpu=cortex-a72 --arch=aarch64  \
                      $MYTHTV_CONFIG_OPT_EXTRA"
                elif [[ $arch == arm* ]] ; then
                    config_opt="--enable-libmp3lame --disable-vdpau \
                      --enable-opengl  \
                      --disable-vaapi \
                      --cpu=cortex-a7 --arch=armv7 --extra-cflags=-mfpu=neon \
                      --extra-cxxflags=-mfpu=neon \
                      $MYTHTV_CONFIG_OPT_EXTRA"
                else
                    config_opt="--enable-libmp3lame --enable-libx264 --enable-vulkan $MYTHTV_CONFIG_OPT_EXTRA"
                fi
                ;;
            *)
                echo "ERROR: Invalid Build Method $BUILD_METHOD"
                exit 2
                ;;
        esac
        if [[ "$BUILD_METHOD" == make ]] ; then
            set -x
            ./configure --prefix=/usr $config_opt "$@" |& tee -a $gitbasedir/../config_${projdir}.out
            set +x
        fi
        ;;
    mythplugins)
        git clean -Xfd
        if which $BUILD_PREPARE ; then
            $BUILD_PREPARE
        fi
        case $BUILD_METHOD in
            cmake)
                . "$scriptpath/getdestdir.source"
                cd ..
                rm -rf build-$BUILD_PRESET
                rm -rf $destdir
                set -o pipefail
                set -x
                cmake --preset $BUILD_PRESET \
                    -DMYTH_BUILD_PLUGINS=ON \
                    -DCMAKE_BUILD_TYPE=BUILD_TYPE \
                    -DCMAKE_INSTALL_PREFIX=$destdir/usr \
                    -DMYTH_RUN_PREFIX=/usr \
                    $MYTHTV_CONFIG_OPT_EXTRA \
                    |& tee -a  $gitbasedir/../config_${projdir}.out
                set +x
                set +o pipefail
                ;;
            make)
                # Reset the mythtv config because this overwrites it
                rm -f $gitbasedir/../config_${projdir}.branch
                . "$scriptpath/getdestdir.source"
                mkdir -p $destdir
                sourcedir=`echo $destdir|sed s/mythplugins/mythtv/`
                gitver=`git describe --dirty|cut -c2-`
                packagever=`env LD_LIBRARY_PATH=$sourcedir/usr/lib $sourcedir/usr/bin/mythutil --version |grep "MythTV Version"|cut -d ' ' -f 4|cut -c2-`
                if [[ "$packagever" != "$gitver" ]] ; then
                    echo ERROR Package version $packagever does not match git version $gitver
                    exit 2
                fi
                cd ../mythtv
                git clean -Xfd
                if [ "$arch" = "aarch64" ] || [ "$arch" = "arm64" ] ; then
                    config_opt="--enable-libmp3lame --disable-vdpau \
                      --enable-opengl  \
                      --disable-vaapi \
                      --cpu=cortex-a72 --arch=aarch64  \
                      $MYTHTV_CONFIG_OPT_EXTRA"
                elif [[ $arch == arm* ]] ; then
                    config_opt="--enable-libmp3lame --disable-vdpau \
                      --enable-opengl  \
                      --disable-vaapi \
                      --cpu=cortex-a7 --arch=armv7 --extra-cflags=-mfpu=neon \
                      --extra-cxxflags=-mfpu=neon \
                      $MYTHTV_CONFIG_OPT_EXTRA"
                else
                    config_opt="--enable-libmp3lame --enable-libx264 --enable-vulkan $MYTHTV_CONFIG_OPT_EXTRA"
                fi
                set -x
                set -o pipefail
                ./configure --prefix=$destdir/usr \
                  --runprefix=/usr $config_opt "$@" |& tee -a  $gitbasedir/../config_${projdir}.out
                set +o pipefail
                set +x
                rm -rf $destdir
                cp -a $sourcedir/ $destdir/
                cp libs/libmythbase/mythconfig.h libs/libmythbase/mythconfig.mak \
                 $destdir/usr/include/mythtv/
                cd ../mythplugins
                git clean -Xfd
                basedir=$destdir/usr
                export PYTHONPATH=`ls -d $basedir/local/lib/python*/dist-packages`
                config_opt=
                ./configure --prefix=$destdir/usr \
                    $config_opt "$@" |& tee -a  $gitbasedir/../config_${projdir}.out
                set -
                ;;
        esac
        ;;
    *)
        echo "ERROR Unrecognized project $projname"
        exit 2
        ;;
esac
echo Completed configure
